import Foundation
import UIKit
import Display
import AsyncDisplayKit
import TelegramCore
import SwiftSignalKit
import TelegramPresentationData
import TelegramUIPreferences
import TelegramVoip
import TelegramAudio
import AccountContext
import TelegramNotices
import AppBundle
import TooltipUI
import CallScreen
import PresentationDataUtils
import Postbox

protocol CallControllerNodeProtocol: AnyObject {
    var isMuted: Bool { get set }
    
    var toggleMute: (() -> Void)? { get set }
    var setCurrentAudioOutput: ((AudioSessionOutput) -> Void)? { get set }
    var beginAudioOuputSelection: ((Bool) -> Void)? { get set }
    var acceptCall: (() -> Void)? { get set }
    var endCall: (() -> Void)? { get set }
    var back: (() -> Void)? { get set }
    var presentCallRating: ((CallId, Bool) -> Void)? { get set }
    var present: ((ViewController) -> Void)? { get set }
    var callEnded: ((Bool) -> Void)? { get set }
    var willBeDismissedInteractively: (() -> Void)? { get set }
    var dismissedInteractively: (() -> Void)? { get set }
    var dismissAllTooltips: (() -> Void)? { get set }
    
    func updateAudioOutputs(availableOutputs: [AudioSessionOutput], currentOutput: AudioSessionOutput?)
    func updateCallState(_ callState: PresentationCallState)
    func updatePeer(accountPeer: EnginePeer, peer: EnginePeer, hasOther: Bool)
    
    func animateIn()
    func animateOut(completion: @escaping () -> Void)
    func expandFromPipIfPossible()
    
    func containerLayoutUpdated(_ layout: ContainerViewLayout, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition)
}

public final class CallController: ViewController {
    private var controllerNode: CallControllerNodeProtocol {
        return self.displayNode as! CallControllerNodeProtocol
    }
    
    private let _ready = Promise<Bool>(false)
    override public var ready: Promise<Bool> {
        return self._ready
    }
    
    private let isDataReady = Promise<Bool>(false)
    private let isContentsReady = Promise<Bool>(false)
    
    private let sharedContext: SharedAccountContext
    private let account: Account
    public let call: PresentationCall
    private let easyDebugAccess: Bool
    
    private var presentationData: PresentationData
    private var didPlayPresentationAnimation = false
    
    private var peerDisposable: Disposable?
    private var disposable: Disposable?
    
    private var callMutedDisposable: Disposable?
    private var isMuted: Bool = false
    
    private var presentedCallRating = false
    
    private var audioOutputStateDisposable: Disposable?
    private var audioOutputState: ([AudioSessionOutput], AudioSessionOutput?)?
    
    private let idleTimerExtensionDisposable = MetaDisposable()
    
    public var restoreUIForPictureInPicture: ((@escaping (Bool) -> Void) -> Void)?
    
    public var onViewDidAppear: (() -> Void)?
    public var onViewDidDisappear: (() -> Void)?
    
    private var isAnimatingDismiss: Bool = false
    private var isDismissed: Bool = false
    private var recordingDevice: OngoingCallContext.AudioDevice?
    private var recording: CallVoiceRecording?
    private var videoRecording: CallVideoRecording?
    private let incomingRecordingVideo = MetaDisposable()
    private let outgoingRecordingVideo = MetaDisposable()
    private var recordingRemoteEndpoint: String?
    private var recordingLocalEndpoint: String?
    private var lastRecordingState: PresentationCallState?
    private var callCanRecord = false
    private var recordingBusy = false
    private let recordButton = UIButton(type: .system)
    
    public init(sharedContext: SharedAccountContext, account: Account, call: PresentationCall, easyDebugAccess: Bool) {
        self.sharedContext = sharedContext
        self.account = account
        self.call = call
        self.easyDebugAccess = easyDebugAccess
        
        self.presentationData = sharedContext.currentPresentationData.with { $0 }
        
        super.init(navigationBarPresentationData: nil)
        
        if let data = call.context.currentAppConfiguration.with({ $0 }).data, data["ios_killswitch_modalcalls"] != nil {
        } else {
            self.navigationPresentation = .flatModal
            self.flatReceivesModalTransition = true
        }
        
        self._ready.set(combineLatest(queue: .mainQueue(), self.isDataReady.get(), self.isContentsReady.get())
        |> map { a, b -> Bool in
            return a && b
        }
        |> filter { $0 }
        |> take(1)
        |> timeout(2.0, queue: .mainQueue(), alternate: .single(true)))
        
        self.isOpaqueWhenInOverlay = true
        
        self.statusBar.statusBarStyle = .White
        self.statusBar.ignoreInCall = true
        
        self.supportedOrientations = ViewControllerSupportedOrientations(regularSize: .portrait, compactSize: .portrait)
        
        self.disposable = (call.state
        |> deliverOnMainQueue).start(next: { [weak self] callState in
            self?.callStateUpdated(callState)
        })
        
        self.callMutedDisposable = (call.isMuted
        |> deliverOnMainQueue).start(next: { [weak self] value in
            if let strongSelf = self {
                strongSelf.isMuted = value
                if strongSelf.isNodeLoaded {
                    strongSelf.controllerNode.isMuted = value
                }
            }
        })
        
        self.audioOutputStateDisposable = (call.audioOutputState
        |> deliverOnMainQueue).start(next: { [weak self] state in
            if let strongSelf = self {
                strongSelf.audioOutputState = state
                if strongSelf.isNodeLoaded {
                    strongSelf.controllerNode.updateAudioOutputs(availableOutputs: state.0, currentOutput: state.1)
                }
            }
        })
    }
    
    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        self.recordingDevice?.setRecordingHandler(nil, muted: true, completion: { _ in })
        self.incomingRecordingVideo.dispose()
        self.outgoingRecordingVideo.dispose()
        self.peerDisposable?.dispose()
        self.disposable?.dispose()
        self.callMutedDisposable?.dispose()
        self.audioOutputStateDisposable?.dispose()
        self.idleTimerExtensionDisposable.dispose()
    }
    
    private func callStateUpdated(_ callState: PresentationCallState) {
        self.lastRecordingState = callState
        switch callState.state {
        case .active:
            self.callCanRecord = (self.call as? PresentationCallImpl)?.recordableAudioDevice != nil
            if !self.callCanRecord { self.finishRecording() }
        case .reconnecting:
            self.callCanRecord = false
        default:
            self.callCanRecord = false
            self.finishRecording()
        }
        self.updateRecordingVideoFeeds()
        self.updateRecordButton()
        if self.isNodeLoaded {
            self.controllerNode.updateCallState(callState)
        }
    }
    
    override public func loadDisplayNode() {
        let displayNode = CallControllerNodeV2(
            sharedContext: self.sharedContext,
            presentationData: self.presentationData,
            statusBar: self.statusBar,
            debugInfo: self.call.debugInfo(),
            easyDebugAccess: self.easyDebugAccess,
            call: self.call
        )
        self.displayNode = displayNode
        self.isContentsReady.set(displayNode.isReady.get())
        
        displayNode.restoreUIForPictureInPicture = { [weak self] completion in
            guard let self, let restoreUIForPictureInPicture = self.restoreUIForPictureInPicture else {
                completion(false)
                return
            }
            restoreUIForPictureInPicture(completion)
        }
        self.displayNodeDidLoad()
        self.recordButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        self.recordButton.backgroundColor = UIColor(white: 0.13, alpha: 0.92)
        self.recordButton.layer.cornerRadius = 16
        self.recordButton.addTarget(self, action: #selector(self.recordButtonPressed), for: .touchUpInside)
        displayNode.view.addSubview(self.recordButton)
        self.updateRecordButton()
        
        self.controllerNode.toggleMute = { [weak self] in
            self?.call.toggleIsMuted()
        }
        
        self.controllerNode.setCurrentAudioOutput = { [weak self] output in
            self?.call.setCurrentAudioOutput(output)
        }
        
        self.controllerNode.beginAudioOuputSelection = { [weak self] hasMute in
            guard let strongSelf = self, let (availableOutputs, currentOutput) = strongSelf.audioOutputState else {
                return
            }
            guard availableOutputs.count >= 2 else {
                return
            }
            if availableOutputs.count == 2 {
                for output in availableOutputs {
                    if output != currentOutput {
                        strongSelf.call.setCurrentAudioOutput(output)
                        break
                    }
                }
            } else {
                let actionSheet = ActionSheetController(presentationData: strongSelf.presentationData)
                var items: [ActionSheetItem] = []
                for output in availableOutputs {
                    if hasMute, case .builtin = output {
                        continue
                    }
                    let title: String
                    var icon: UIImage?
                    switch output {
                        case .builtin:
                            title = UIDevice.current.model
                        case .speaker:
                            title = strongSelf.presentationData.strings.Call_AudioRouteSpeaker
                            icon = generateScaledImage(image: UIImage(bundleImageName: "Call/CallSpeakerButton"), size: CGSize(width: 48.0, height: 48.0), opaque: false)
                        case .headphones:
                            title = strongSelf.presentationData.strings.Call_AudioRouteHeadphones
                        case let .port(port):
                            title = port.name
                            if port.type == .bluetooth {
                                var image = UIImage(bundleImageName: "Call/CallBluetoothButton")
                                let portName = port.name.lowercased()
                                if portName.contains("airpods max") {
                                    image = UIImage(bundleImageName: "Call/CallAirpodsMaxButton")
                                } else if portName.contains("airpods pro") {
                                    image = UIImage(bundleImageName: "Call/CallAirpodsProButton")
                                } else if portName.contains("airpods") {
                                    image = UIImage(bundleImageName: "Call/CallAirpodsButton")
                                }
                                icon = generateScaledImage(image: image, size: CGSize(width: 48.0, height: 48.0), opaque: false)
                            }
                    }
                    items.append(CallRouteActionSheetItem(title: title, icon: icon, selected: output == currentOutput, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        self?.call.setCurrentAudioOutput(output)
                    }))
                }
                
                if hasMute {
                    items.append(CallRouteActionSheetItem(title: strongSelf.presentationData.strings.Call_AudioRouteMute, icon:  generateScaledImage(image: UIImage(bundleImageName: "Call/CallMuteButton"), size: CGSize(width: 48.0, height: 48.0), opaque: false), selected: strongSelf.isMuted, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        self?.call.toggleIsMuted()
                    }))
                }
                
                actionSheet.setItemGroups([ActionSheetItemGroup(items: items), ActionSheetItemGroup(items: [
                        ActionSheetButtonItem(title: strongSelf.presentationData.strings.Call_AudioRouteHide, color: .accent, font: .bold, action: { [weak actionSheet] in
                            actionSheet?.dismissAnimated()
                        })
                    ])
                ])
                strongSelf.present(actionSheet, in: .window(.calls))
            }
        }
        
        self.controllerNode.acceptCall = { [weak self] in
            let _ = self?.call.answer()
        }
        
        self.controllerNode.endCall = { [weak self] in
            let _ = self?.call.hangUp()
        }
        
        self.controllerNode.back = { [weak self] in
            let _ = self?.dismiss()
        }
        
        displayNode.conferenceAddParticipant = { [weak self] in
            guard let self else {
                return
            }
            self.conferenceAddParticipant()
        }
        
        self.controllerNode.presentCallRating = { [weak self] callId, isVideo in
            if let strongSelf = self, !strongSelf.presentedCallRating {
                strongSelf.presentedCallRating = true
                
                Queue.mainQueue().after(0.5, {
                    let window = strongSelf.window
                    let controller = callRatingController(sharedContext: strongSelf.sharedContext, account: strongSelf.account, callId: callId, userInitiated: false, isVideo: isVideo, present: { c, a in
                        if let window = window {
                            c.presentationArguments = a
                            window.present(c, on: .root, blockInteraction: false, completion: {})
                        }
                    }, push: { [weak self] c in
                        if let strongSelf = self {
                            strongSelf.push(c)
                        }
                    })
                    strongSelf.present(controller, in: .window(.root))
                })
            }
        }
        
        self.controllerNode.present = { [weak self] controller in
            if let strongSelf = self {
                strongSelf.present(controller, in: .window(.root))
            }
        }
        
        self.controllerNode.dismissAllTooltips = { [weak self] in
            if let strongSelf = self {
                strongSelf.forEachController({ controller in
                    if let controller = controller as? TooltipScreen {
                        controller.dismiss()
                    }
                    return true
                })
            }
        }
        
//        self.controllerNode.callEnded = { [weak self] didPresentRating in
//            if let strongSelf = self, !didPresentRating {
//                let _ = (combineLatest(strongSelf.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.callListSettings]), ApplicationSpecificNotice.getCallsTabTip(accountManager: strongSelf.sharedContext.accountManager))
//                |> map { sharedData, callsTabTip -> Int32 in
//                    var value = false
//                    if let settings = sharedData.entries[ApplicationSpecificSharedDataKeys.callListSettings]?.get(CallListSettings.self) {
//                        value = settings.showTab
//                    }
//                    if value {
//                        return 3
//                    } else {
//                        return callsTabTip
//                    }
//                } |> deliverOnMainQueue).start(next: { [weak self] callsTabTip in
//                    if let strongSelf = self {
//                        if callsTabTip == 2 {
//                            Queue.mainQueue().after(1.0) {
//                                let controller = callSuggestTabController(sharedContext: strongSelf.sharedContext)
//                                strongSelf.present(controller, in: .window(.root))
//                            }
//                        }
//                        if callsTabTip < 3 {
//                            let _ = ApplicationSpecificNotice.incrementCallsTabTips(accountManager: strongSelf.sharedContext.accountManager).start()
//                        }
//                    }
//                })
//            }
//        }
        
        self.controllerNode.willBeDismissedInteractively = { [weak self] in
            guard let self else {
                return
            }
            self.notifyDismissed()
        }
        self.controllerNode.dismissedInteractively = { [weak self] in
            guard let self else {
                return
            }
            self.didPlayPresentationAnimation = false
            self.superDismiss()
        }
        
        let callPeerView: Signal<EnginePeer?, NoError>
        callPeerView = TelegramEngine(account: self.account).data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: self.call.peerId))

        self.peerDisposable = (combineLatest(queue: .mainQueue(),
            TelegramEngine(account: self.account).data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: self.account.peerId)) |> take(1),
            callPeerView,
            self.sharedContext.activeAccountsWithInfo |> take(1)
        )
        |> deliverOnMainQueue).start(next: { [weak self] accountView, view, activeAccountsWithInfo in
            if let strongSelf = self {
                if let view {
                    if let accountPeer = accountView {
                        strongSelf.controllerNode.updatePeer(accountPeer: accountPeer, peer: view, hasOther: activeAccountsWithInfo.accounts.count > 1)
                        strongSelf.isDataReady.set(.single(true))
                    }
                } else {
                    strongSelf.isDataReady.set(.single(true))
                }
            }
        })
        
        self.controllerNode.isMuted = self.isMuted
       
        if let audioOutputState = self.audioOutputState {
            self.controllerNode.updateAudioOutputs(availableOutputs: audioOutputState.0, currentOutput: audioOutputState.1)
        }
    }
    
    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        self.isDismissed = false
        
        if !self.didPlayPresentationAnimation {
            self.didPlayPresentationAnimation = true
            
            self.controllerNode.animateIn()
        }
        
        self.idleTimerExtensionDisposable.set(self.sharedContext.applicationBindings.pushIdleTimerExtension())
        
        DispatchQueue.main.async { [weak self] in
            self?.onViewDidAppear?()
        }
    }
    
    override public func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        self.idleTimerExtensionDisposable.set(nil)
        
        self.notifyDismissed()
    }
    
    func notifyDismissed() {
        if !self.isDismissed {
            self.isDismissed = true
            DispatchQueue.main.async {
                self.onViewDidDisappear?()
            }
        }
    }
    
    final class AnimateOutToGroupChat {
        let containerView: UIView
        let incomingPeerId: EnginePeer.Id
        let incomingVideoLayer: CALayer?
        let incomingVideoPlaceholder: VideoSource.Output?
        
        init(
            containerView: UIView,
            incomingPeerId: EnginePeer.Id,
            incomingVideoLayer: CALayer?,
            incomingVideoPlaceholder: VideoSource.Output?
        ) {
            self.containerView = containerView
            self.incomingPeerId = incomingPeerId
            self.incomingVideoLayer = incomingVideoLayer
            self.incomingVideoPlaceholder = incomingVideoPlaceholder
        }
    }
    
    func animateOutToGroupChat(completion: @escaping () -> Void) -> AnimateOutToGroupChat? {
        return (self.controllerNode as? CallControllerNodeV2)?.animateOutToGroupChat(completion: completion)
    }
    
    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        
        self.controllerNode.containerLayoutUpdated(layout, navigationBarHeight: self.navigationLayout(layout: layout).navigationFrame.maxY, transition: transition)
        self.recordButton.frame = CGRect(x: layout.size.width - layout.safeInsets.right - 140,
            y: max(layout.safeInsets.top, layout.statusBarHeight ?? 0) + 58, width: 124, height: 34)
    }

    private func updateRecordButton() {
        self.recordButton.isHidden = !self.callCanRecord && self.recording == nil
        self.recordButton.isEnabled = !self.recordingBusy
        let title = self.recording == nil ? (self.recordingBusy ? "Сохранение…" : "Запись") : "Стоп записи"
        self.recordButton.setTitle(title, for: .normal)
        self.recordButton.setTitleColor(self.recording == nil ? .white : .systemRed, for: .normal)
    }

    @objc private func recordButtonPressed() {
        if self.recording != nil {
            self.finishRecording()
            return
        }
        guard self.callCanRecord, !self.recordingBusy else { return }
        var actions = [
            TextAlertAction(type: .genericAction, title: "Отмена", action: {}),
            TextAlertAction(type: .defaultAction, title: "Записать звук", action: { [weak self] in
                self?.startRecording(video: false)
            })
        ]
        if let state = self.lastRecordingState {
            let endpoints = Self.recordingEndpoints(state)
            if endpoints.local != nil || endpoints.remote != nil {
                actions.append(TextAlertAction(type: .defaultAction, title: "Записать видео", action: { [weak self] in
                    self?.startRecording(video: true)
                }))
            }
        }
        self.presentRecordingAlert(title: "Запись звонка", text: "Начните запись только после согласия собеседника.", actions: actions)
    }

    private func startRecording(video: Bool) {
        guard self.callCanRecord, self.recording == nil, !self.recordingBusy,
              let call = self.call as? PresentationCallImpl, let device = call.recordableAudioDevice else { return }
        let videoRecorder: CallVideoRecording?
        do {
            videoRecorder = try video ? CallVideoRecording(warning: { [weak self] in
                guard let self, self.videoRecording != nil else { return }
                self.presentRecordingAlert(title: "Видео больше 2 ГБ",
                    text: "Запись продолжается. Остановите её, если хотите ограничить размер файла.", actions: [
                        TextAlertAction(type: .genericAction, title: "Продолжить", action: {}),
                        TextAlertAction(type: .defaultAction, title: "Остановить", action: { [weak self] in self?.finishRecording() })
                    ])
            }, thermalStop: { [weak self] in
                guard let self, self.videoRecording != nil else { return }
                self.finishRecording()
                self.presentRecordingError("Телефон перегрелся. Запись остановлена.")
            }) : nil
        } catch {
            self.presentRecordingError(error.localizedDescription)
            return
        }
        let outputPCM: ((Data, UInt64) -> Void)? = videoRecorder.map { video in
            return { [weak video] data, time in video?.appendAudio(data, at: time) }
        }
        guard let recording = CallVoiceRecording(outputPCM: outputPCM) else {
            self.presentRecordingError("Не удалось подготовить запись.")
            return
        }
        self.recordingBusy = true
        self.recording = recording
        self.videoRecording = videoRecorder
        self.recordingDevice = device
        self.updateRecordButton()
        device.setRecordingHandler({ [weak recording] data, rate, channels, microphone in
            recording?.append(data, rate: Int(rate), channels: Int(channels), isMicrophone: microphone)
        }, muted: call.recordingMicrophoneMuted, completion: { [weak self, weak recording] started in
            guard let self, let recording, self.recording === recording else { return }
            self.recordingBusy = false
            if !started {
                self.recording = nil
                self.videoRecording = nil
                self.recordingDevice = nil
                self.presentRecordingError("Аудиопоток звонка недоступен.")
            }
            self.updateRecordingVideoFeeds()
            self.updateRecordButton()
        })
    }

    private func finishRecording() {
        guard let recording = self.recording, let device = self.recordingDevice else { return }
        let video = self.videoRecording
        self.videoRecording = nil
        self.updateRecordingVideoFeeds()
        self.recording = nil
        self.recordingDevice = nil
        self.recordingBusy = true
        self.updateRecordButton()
        device.setRecordingHandler(nil, muted: true, completion: { _ in
            recording.finish {
                if let video {
                    video.finish { result in
                        self.recordingBusy = false
                        self.updateRecordButton()
                        self.presentSavedRecording(result)
                    }
                    return
                }
                self.recordingBusy = false
                self.updateRecordButton()
                guard let (data, duration) = result else {
                    self.presentRecordingError("В записи нет доступного звука.")
                    return
                }
                self.presentRecordingAlert(title: "Отправить запись?", text: "Запись целиком отправится в чат с собеседником как голосовое сообщение.", actions: [
                    TextAlertAction(type: .genericAction, title: "Удалить", action: {}),
                    TextAlertAction(type: .defaultAction, title: "Отправить", action: { [account = self.account, peerId = self.call.peerId] in
                        let id = Int64.random(in: Int64.min ... Int64.max)
                        let resource = LocalFileMediaResource(fileId: id, size: Int64(data.count))
                        account.postbox.mediaBox.storeResourceData(resource.id, data: data)
                        let media = TelegramMediaFile(
                            fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: id), partialReference: nil,
                            resource: resource, previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil,
                            mimeType: "audio/ogg", size: Int64(data.count),
                            attributes: [.Audio(isVoice: true, duration: duration, title: nil, performer: nil, waveform: nil)],
                            alternativeRepresentations: [])
                        let message: EnqueueMessage = .message(
                            text: "", attributes: [], inlineStickers: [:], mediaReference: .standalone(media: media),
                            threadId: nil, replyToMessageId: nil, replyToStoryId: nil,
                            localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
                        let _ = enqueueMessages(account: account, peerId: peerId, messages: [message]).startStandalone()
                    })
                ])
            }
        })
    }

    private static func recordingEndpoints(_ state: PresentationCallState) -> (local: String?, remote: String?) {
        let local: String?
        let remote: String?
        if case let .active(_, endpoint) = state.videoState { local = endpoint } else { local = nil }
        if case let .active(endpoint) = state.remoteVideoState { remote = endpoint } else { remote = nil }
        return (local, remote)
    }

    private func updateRecordingVideoFeeds() {
        guard let video = self.videoRecording, !self.recordingBusy, let state = self.lastRecordingState,
              let call = self.call as? PresentationCallImpl else {
            self.incomingRecordingVideo.set(nil)
            self.outgoingRecordingVideo.set(nil)
            self.recordingRemoteEndpoint = nil
            self.recordingLocalEndpoint = nil
            return
        }
        let endpoints = Self.recordingEndpoints(state)
        if self.recordingRemoteEndpoint != endpoints.remote {
            self.recordingRemoteEndpoint = endpoints.remote
            video.clearCamera(incoming: true)
            self.incomingRecordingVideo.set(endpoints.remote.flatMap { _ in
                call.video(isIncoming: true)?.start(next: { [weak video] frame in video?.appendVideo(frame, incoming: true) })
            })
        }
        if self.recordingLocalEndpoint != endpoints.local {
            self.recordingLocalEndpoint = endpoints.local
            video.clearCamera(incoming: false)
            self.outgoingRecordingVideo.set(endpoints.local.flatMap { _ in
                call.video(isIncoming: false)?.start(next: { [weak video] frame in video?.appendVideo(frame, incoming: false) })
            })
        }
    }

    private func presentSavedRecording(_ result: Result<CallVideoRecording.SavedFile, Error>) {
        switch result {
        case let .failure(error):
            self.presentRecordingError(error.localizedDescription)
        case let .success(file):
            if let calls = self.sharedContext.callManager {
                CallRecordingCompression.shared.enqueue(file.url, calls: calls)
            }
            let size = (try? file.url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map {
                ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)
            } ?? ""
            let sizeNotice = file.exceededLimit ? "\nЗапись превышает 2 ГБ." : ""
            self.presentRecordingAlert(title: "Видео сохранено", text: "\(file.url.lastPathComponent)\n\(size)\(sizeNotice)", actions: [
                TextAlertAction(type: .genericAction, title: "Закрыть", action: {}),
                TextAlertAction(type: .defaultAction, title: "Сохранить в Файлы", action: {
                    let picker = UIDocumentPickerViewController(forExporting: [file.url], asCopy: true)
                    self.sharedContext.applicationBindings.presentNativeController(picker)
                })
            ])
        }
    }

    private func presentRecordingError(_ text: String) {
        self.presentRecordingAlert(title: "Запись звонка", text: text, actions: [
            TextAlertAction(type: .defaultAction, title: "ОК", action: {})
        ])
    }

    private func presentRecordingAlert(title: String, text: String, actions: [TextAlertAction]) {
        let alert = textAlertController(context: self.call.context, title: title, text: text, actions: actions,
            actionLayout: actions.count > 2 ? .vertical : .horizontal, dismissOnOutsideTap: false)
        if let window = self.window {
            window.present(alert, on: self.callCanRecord ? .calls : .root, blockInteraction: false, completion: {})
        } else {
            self.sharedContext.mainWindow?.present(alert, on: .root)
        }
    }
    
    override public func dismiss(completion: (() -> Void)? = nil) {
        if !self.isAnimatingDismiss {
            self.notifyDismissed()
            
            self.isAnimatingDismiss = true
            self.controllerNode.animateOut(completion: { [weak self] in
                guard let self else {
                    return
                }
                self.isAnimatingDismiss = false
                self.superDismiss()
                completion?()
            })
        }
    }
    
    public func dismissWithoutAnimation() {
        self.superDismiss()
    }
    
    private func superDismiss() {
        self.didPlayPresentationAnimation = false
        if self.navigationPresentation == .flatModal {
            super.dismiss()
        } else {
            self.presentingViewController?.dismiss(animated: false, completion: nil)
        }
    }
    
    private func conferenceAddParticipant() {
        var disablePeerIds: [EnginePeer.Id] = []
        disablePeerIds.append(self.call.context.account.peerId)
        disablePeerIds.append(self.call.peerId)
        let controller = CallController.openConferenceAddParticipant(context: self.call.context, disablePeerIds: disablePeerIds, shareLink: nil, completion: { [weak self] peers in
            guard let self else {
                return
            }
            
            let _ = self.call.upgradeToConference(invitePeers: peers, completion: { _ in
            })
        })
        self.push(controller)
    }
    
    static func openConferenceAddParticipant(context: AccountContext, disablePeerIds: [EnginePeer.Id], shareLink: (() -> Void)?, completion: @escaping ([(id: EnginePeer.Id, isVideo: Bool)]) -> Void) -> ViewController {
        let presentationData = context.sharedContext.currentPresentationData.with({ $0 }).withUpdated(theme: defaultDarkColorPresentationTheme)
        
        var options: [ContactListAdditionalOption] = []
        var openShareLinkImpl: (() -> Void)?
        if shareLink != nil {
            options.append(ContactListAdditionalOption(title: presentationData.strings.Call_ShareLink, icon: .generic(UIImage(bundleImageName: "Contact List/LinkActionIcon")!), action: {
                openShareLinkImpl?()
            }, clearHighlightAutomatically: false))
        }
        
        let controller = context.sharedContext.makeContactSelectionController(ContactSelectionControllerParams(
            context: context,
            updatedPresentationData: (initial: presentationData, signal: .single(presentationData)),
            mode: .generic,
            title: { strings in
                return strings.Call_AddMemberTitle
            },
            options: .single(options),
            displayCallIcons: true,
            multipleSelection: .disabled,
            confirmation: { peer in
                switch peer {
                case let .peer(peer, _, _):
                    guard case let .user(user) = peer else {
                        return .single(false)
                    }
                    if disablePeerIds.contains(user.id) {
                        return .single(false)
                    }
                    if user.botInfo != nil {
                        return .single(false)
                    }
                    return .single(true)
                default:
                    return .single(false)
                }
            },
            isPeerEnabled: { peer in
                switch peer {
                case let .peer(peer, _, _):
                    guard case let .user(user) = peer else {
                        return false
                    }
                    if disablePeerIds.contains(user.id) {
                        return false
                    }
                    if user.botInfo != nil {
                        return false
                    }
                    return true
                default:
                    return false
                }
            }
        ))
        
        openShareLinkImpl = { [weak controller] in
            controller?.dismiss()
            shareLink?()
        }
        
        controller.navigationPresentation = .modal
        let _ = (controller.result |> take(1) |> deliverOnMainQueue).startStandalone(next: { [weak controller] result in
            guard let result, let peer = result.0.first, case let .peer(peer, _, _) = peer else {
                controller?.dismiss()
                return
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                controller?.dismiss()
            }
            
            var isVideo = false
            switch result.1 {
            case .videoCall:
                isVideo = true
            default:
                break
            }
            
            completion([(peer.id, isVideo)])
        })
        
        return controller
    }
    
    @objc private func backPressed() {
        self.dismiss()
    }
    
    public func expandFromPipIfPossible() {
        self.controllerNode.expandFromPipIfPossible()
    }
}
