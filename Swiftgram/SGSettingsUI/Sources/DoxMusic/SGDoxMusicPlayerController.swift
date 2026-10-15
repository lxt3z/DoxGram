import Foundation
import UIKit
import AVFoundation
import MediaPlayer
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import TelegramPresentationData
import UndoUI
import OverlayStatusController
import AppBundle
import SGSimpleSettings

public final class SGDoxMusicPlayerController: ViewController, UIGestureRecognizerDelegate, UITableViewDataSource, UITableViewDelegate {
    private let context: AccountContext
    private var presentationData: PresentationData
    
    // Background Layers
    private let backgroundImageView = UIImageView()
    private let ambientGradientLayer = CAGradientLayer()
    private let backgroundBlurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let darkDimOverlay = UIView()
    
    // Video Clip Background (Animated Canvas)
    private let videoContainerView = UIView()
    private var videoPlayer: AVPlayer?
    private var videoPlayerLayer: AVPlayerLayer?
    private var videoItem: AVPlayerItem?
    private var currentVideoClipUrl: String?
    private var videoEndObserver: Any?
    private let videoDimOverlay = UIView()
    
    // Top Grabber
    private let grabberView = UIView()
    
    // Hidden System Volume Controller & Route Picker
    private let hiddenVolumeView = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 1, height: 1))
    private var volumeObservation: NSKeyValueObservation?
    
    // Navigation Modes
    public enum PlayerMode: Int {
        case nowPlaying = 0
        case lyrics = 1
        case queue = 2
    }
    private var currentMode: PlayerMode = .nowPlaying
    
    // Center Content Containers
    private let nowPlayingContainerView = UIView()
    private let lyricsContainerView = UIView()
    private let queueContainerView = UIView()
    
    // Shared Bottom Playback Controls Container
    private let bottomControlsContainer = UIView()
    
    // MARK: - Now Playing Center UI
    private let artworkAmbientGlowView = UIView()
    private let artworkGlowGradientLayer = CAGradientLayer()
    private let artworkContainerView = UIView()
    private let artworkImageView = UIImageView()
    
    private let infoContainerView = UIView()
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    private let favoriteButton = UIButton(type: .system)
    private let moreButton = UIButton(type: .system)
    
    // MARK: - Shared Bottom Controls UI (Apple Music Authentic)
    // Scrubber & Times
    private let progressSlider = UISlider()
    private let currentTimeLabel = UILabel()
    private let remainingTimeLabel = UILabel()
    private let formatBadgeButton = UIButton(type: .system)
    
    // Transport Controls
    private let controlsContainerView = UIView()
    private let shuffleButton = UIButton(type: .system)
    private let previousButton = UIButton(type: .system)
    private let playPauseButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let repeatButton = UIButton(type: .system)
    
    // Volume Row
    private let volumeContainerView = UIView()
    private let volumeMinIcon = UIImageView()
    private let volumeSlider = UISlider()
    private let volumeMaxIcon = UIImageView()
    
    // Bottom Bar (Lyrics | AirPlay | Queue)
    private let bottomBarContainer = UIView()
    private let bottomLyricsButton = UIButton(type: .system)
    private let bottomAirplayButton = UIButton(type: .system)
    private let bottomQueueButton = UIButton(type: .system)
    
    // MARK: - Lyrics Center UI
    private let lyricsHeaderView = UIView()
    private let lyricsHeaderArtwork = UIImageView()
    private let lyricsHeaderInfoView = UIView()
    private let lyricsTrackTitle = UILabel()
    private let lyricsTrackArtist = UILabel()
    private let lyricsFavoriteButton = UIButton(type: .system)
    private let lyricsMoreButton = UIButton(type: .system)
    
    private let lyricsTableContainer = UIView()
    private let lyricsTableView = UITableView(frame: .zero, style: .plain)
    private let lyricsPlainTextView = UITextView()
    private let lyricsLoadingIndicator = UIActivityIndicatorView(style: .medium)
    private let lyricsStatusLabel = UILabel()
    private let lyricsSingButton = UIButton(type: .system) // Mic
    
    private var currentLyrics: SGDoxLyrics?
    private var activeLyricsIndex: Int = -1
    private var isUserScrollingLyrics = false
    private var userScrollTimer: Foundation.Timer?
    private var lyricsHeightCache: [Int: CGFloat] = [:]
    
    // MARK: - Queue Center UI
    private let queueHeaderView = UIView()
    private let queueTitleLabel = UILabel()
    private let queueCountLabel = UILabel()
    private let queueShuffleButton = UIButton(type: .system)
    private let queueClearButton = UIButton(type: .system)
    private let queueTableView = UITableView(frame: .zero, style: .plain)
    
    private var cachedQueue: [SGDoxMusicTrack] = []
    private var isDraggingSlider = false
    private var displayedTrackId: String?
    private var stateToken: UUID?
    private var timeToken: UUID?
    private var validLayout: ContainerViewLayout?
    private var lastDisplayedSecond: Int = -1
    
    public var onDismiss: (() -> Void)?
    public var onDismissBegin: (() -> Void)?
    private var hasBegunDismissal = false
    private var isDismissing = false
    
    private static weak var currentPresentedPlayer: SGDoxMusicPlayerController?
    
    // MARK: - Static Presentation Helper
    public static func present(context: AccountContext, onDismissBegin: (() -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        if currentPresentedPlayer != nil {
            return
        }
        
        let player = SGDoxMusicPlayerController(context: context)
        currentPresentedPlayer = player
        player.onDismissBegin = onDismissBegin
        player.onDismiss = {
            if currentPresentedPlayer === player {
                currentPresentedPlayer = nil
            }
            onDismiss?()
        }
        
        if let mainWindow = context.sharedContext.mainWindow {
            if let rootNav = mainWindow.viewController as? NavigationController {
                for c in rootNav.viewControllers {
                    if let stalePlayer = c as? SGDoxMusicPlayerController {
                        rootNav.filterController(stalePlayer, animated: false)
                    }
                }
                rootNav.pushViewController(player)
            } else if let vc = mainWindow.viewController as? ViewController {
                vc.push(player)
            }
        }
    }
    
    public init(context: AccountContext) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: nil)
        self.navigationPresentation = .flatModal
        self.flatReceivesModalTransition = true
        self.statusBar.statusBarStyle = .White
        self.ready.set(.single(true))
    }
    
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        if SGDoxMusicPlayerController.currentPresentedPlayer === self {
            SGDoxMusicPlayerController.currentPresentedPlayer = nil
        }
        self.detachListeners()
    }
    
    public override func loadDisplayNode() {
        super.loadDisplayNode()
        self.displayNode.backgroundColor = .clear
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .clear
        
        self.setupViews()
        self.updateContent()
        self.reloadQueueData()
        
        if let layout = self.validLayout {
            self.applyLayout(bounds: CGRect(origin: .zero, size: layout.size), safeArea: layout.safeInsets)
        } else if self.view.bounds.width > 0 && self.view.bounds.height > 0 {
            self.applyLayout(bounds: self.view.bounds, safeArea: self.view.safeAreaInsets)
        }
        
        self.darkDimOverlay.alpha = 1.0
        self.backgroundBlurView.alpha = 1.0
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.attachListeners()
        self.updateContent()
        self.reloadQueueData()
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.triggerDismissBeginIfNeeded()
    }
    
    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        self.detachListeners()
        self.triggerDismissBeginIfNeeded()
        if !self.isDismissing {
            self.isDismissing = true
            self.onDismiss?()
        }
    }
    
    public override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        self.validLayout = layout
        self.displayNode.frame = CGRect(origin: .zero, size: layout.size)
        let bounds = CGRect(origin: .zero, size: layout.size)
        let safeArea = layout.safeInsets
        self.applyLayout(bounds: bounds, safeArea: safeArea)
    }
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let layout = self.validLayout {
            self.applyLayout(bounds: CGRect(origin: .zero, size: layout.size), safeArea: layout.safeInsets)
        } else if self.view.bounds.width > 0 && self.view.bounds.height > 0 {
            self.applyLayout(bounds: self.view.bounds, safeArea: self.view.safeAreaInsets)
        }
    }
    
    private func triggerDismissBeginIfNeeded() {
        guard !self.hasBegunDismissal else { return }
        self.hasBegunDismissal = true
        self.onDismissBegin?()
    }
    
    private func attachListeners() {
        guard self.stateToken == nil else { return }
        self.stateToken = SGDoxMusicManager.shared.addStateListener { [weak self] in
            DispatchQueue.main.async {
                self?.updateContent()
                self?.reloadQueueData()
                if let p = self?.videoPlayer {
                    if SGDoxMusicManager.shared.isPlaying {
                        p.play()
                    } else {
                        p.pause()
                    }
                }
            }
        }
        
        self.timeToken = SGDoxMusicManager.shared.addTimeListener { [weak self] current, duration in
            guard let self = self, !self.isDraggingSlider else { return }
            let d = duration > 0 ? duration : 30.0
            let currentSecond = Int(current)
            let progress = Float(current / d)
            
            if let vp = self.videoPlayer {
                let vTime = vp.currentTime().seconds
                if vTime.isFinite && !vTime.isNaN && abs(vTime - current) > 1.2 {
                    vp.seek(to: CMTime(seconds: current, preferredTimescale: 600))
                }
            }
            
            let timeStr = self.formatTime(current)
            let remStr = "-\(self.formatTime(max(0, d - current)))"
            
            self.progressSlider.value = progress
            if currentSecond != self.lastDisplayedSecond {
                self.lastDisplayedSecond = currentSecond
                self.currentTimeLabel.text = timeStr
                self.remainingTimeLabel.text = remStr
            }
            
            if self.currentMode == .lyrics {
                self.syncLyricsPosition(currentTime: current)
            }
        }
        
        // System Volume Listener
        self.volumeSlider.value = AVAudioSession.sharedInstance().outputVolume
        self.volumeObservation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            DispatchQueue.main.async {
                if let newVol = change.newValue {
                    self?.volumeSlider.value = newVol
                }
            }
        }
    }
    
    private func detachListeners() {
        self.userScrollTimer?.invalidate()
        self.userScrollTimer = nil
        self.volumeObservation?.invalidate()
        self.volumeObservation = nil
        self.teardownVideoPlayback(animated: false)
        if let token = self.stateToken {
            SGDoxMusicManager.shared.removeStateListener(token)
            self.stateToken = nil
        }
        if let token = self.timeToken {
            SGDoxMusicManager.shared.removeTimeListener(token)
            self.timeToken = nil
        }
    }
    
    // MARK: - Dismissal
    @objc private func dismissPressed() {
        self.dismiss(animated: true)
    }
    
    public override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        guard !self.isDismissing else { return }
        self.isDismissing = true
        self.detachListeners()
        self.triggerDismissBeginIfNeeded()
        
        let finish = { [weak self] in
            guard let self = self else { return }
            self.finishDismiss(completion: completion)
        }
        
        if flag {
            let height = self.view.bounds.height > 0 ? self.view.bounds.height : UIScreen.main.bounds.height
            UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseIn], animations: {
                self.view.transform = CGAffineTransform(translationX: 0, y: height)
                self.darkDimOverlay.alpha = 0.0
                self.backgroundBlurView.alpha = 0.0
            }) { _ in
                finish()
            }
        } else {
            finish()
        }
    }
    
    private func finishDismiss(completion: (() -> Void)? = nil) {
        if SGDoxMusicPlayerController.currentPresentedPlayer === self {
            SGDoxMusicPlayerController.currentPresentedPlayer = nil
        }
        if let navigationController = self.navigationController as? NavigationController {
            navigationController.filterController(self, animated: false)
        } else if let rootNav = self.context.sharedContext.mainWindow?.viewController as? NavigationController {
            rootNav.filterController(self, animated: false)
        } else if let presenting = self.presentingViewController {
            presenting.dismiss(animated: false, completion: nil)
        } else {
            self.dismiss()
        }
        completion?()
    }
    
    // MARK: - Setup Views
    private func setupViews() {
        // 1. Background Layers
        self.backgroundImageView.contentMode = .scaleAspectFill
        self.backgroundImageView.clipsToBounds = true
        self.view.addSubview(self.backgroundImageView)
        
        self.ambientGradientLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        self.ambientGradientLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        self.view.layer.addSublayer(self.ambientGradientLayer)
        
        self.backgroundBlurView.effect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        self.view.addSubview(self.backgroundBlurView)
        
        self.darkDimOverlay.backgroundColor = UIColor(red: 0.05, green: 0.06, blue: 0.10, alpha: 0.38)
        self.view.addSubview(self.darkDimOverlay)
        
        // Video layer (Animated cover canvas)
        self.videoContainerView.clipsToBounds = true
        self.videoContainerView.backgroundColor = .clear
        self.videoContainerView.alpha = 0.0
        self.view.insertSubview(self.videoContainerView, aboveSubview: self.darkDimOverlay)
        self.videoDimOverlay.backgroundColor = UIColor(white: 0.0, alpha: 0.35)
        self.videoContainerView.addSubview(self.videoDimOverlay)
        
        // Grabber
        self.grabberView.backgroundColor = UIColor(white: 1.0, alpha: 0.35)
        self.grabberView.layer.cornerRadius = 2.5
        self.grabberView.isUserInteractionEnabled = true
        self.grabberView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.dismissPressed)))
        self.view.addSubview(self.grabberView)
        
        // Hidden System Volume View
        self.view.addSubview(self.hiddenVolumeView)
        
        // Center Content Panes
        self.view.addSubview(self.nowPlayingContainerView)
        self.view.addSubview(self.lyricsContainerView)
        self.view.addSubview(self.queueContainerView)
        
        self.lyricsContainerView.alpha = 0.0
        self.lyricsContainerView.isHidden = true
        self.queueContainerView.alpha = 0.0
        self.queueContainerView.isHidden = true
        
        // Shared Bottom Controls Container
        self.view.addSubview(self.bottomControlsContainer)
        
        self.setupNowPlayingPane()
        self.setupLyricsPane()
        self.setupQueuePane()
        self.setupSharedBottomControls()
    }
    
    // MARK: - Setup Now Playing Pane (Center Content)
    private func setupNowPlayingPane() {
        self.artworkAmbientGlowView.clipsToBounds = false
        self.artworkGlowGradientLayer.type = .radial
        self.artworkGlowGradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        self.artworkGlowGradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        self.artworkGlowGradientLayer.locations = [0.0, 0.45, 1.0]
        self.artworkAmbientGlowView.layer.addSublayer(self.artworkGlowGradientLayer)
        self.nowPlayingContainerView.addSubview(self.artworkAmbientGlowView)

        self.artworkContainerView.layer.cornerRadius = 24
        self.artworkContainerView.layer.cornerCurve = .continuous
        self.artworkContainerView.layer.shadowOffset = CGSize(width: 0, height: 16)
        self.artworkContainerView.layer.shadowOpacity = 0.38
        self.artworkContainerView.layer.shadowRadius = 24
        self.artworkContainerView.layer.shadowColor = UIColor.black.cgColor
        self.artworkContainerView.isUserInteractionEnabled = true
        self.artworkContainerView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.artworkTapped)))
        self.nowPlayingContainerView.addSubview(self.artworkContainerView)
        
        self.artworkImageView.contentMode = .scaleAspectFill
        self.artworkImageView.clipsToBounds = true
        self.artworkImageView.layer.cornerRadius = 24
        self.artworkImageView.layer.cornerCurve = .continuous
        self.artworkImageView.backgroundColor = UIColor(white: 0.15, alpha: 1.0)
        self.artworkContainerView.addSubview(self.artworkImageView)
        
        // Info Row: Title, Artist, Star, More
        self.nowPlayingContainerView.addSubview(self.infoContainerView)
        
        self.titleLabel.textColor = .white
        self.titleLabel.font = UIFont.systemFont(ofSize: 22, weight: .bold)
        self.titleLabel.lineBreakMode = .byTruncatingTail
        self.infoContainerView.addSubview(self.titleLabel)
        
        self.artistLabel.textColor = UIColor(white: 1.0, alpha: 0.65)
        self.artistLabel.font = UIFont.systemFont(ofSize: 17, weight: .regular)
        self.artistLabel.lineBreakMode = .byTruncatingTail
        self.artistLabel.isUserInteractionEnabled = true
        self.artistLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.artistLabelTapped)))
        self.infoContainerView.addSubview(self.artistLabel)
        
        let starConfig = UIImage.SymbolConfiguration(pointSize: 21, weight: .medium)
        self.favoriteButton.setImage(UIImage(systemName: "star", withConfiguration: starConfig), for: .normal)
        self.favoriteButton.tintColor = .white
        self.favoriteButton.addTarget(self, action: #selector(self.favoritePressed), for: .touchUpInside)
        self.infoContainerView.addSubview(self.favoriteButton)
        
        let moreConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        self.moreButton.setImage(UIImage(systemName: "ellipsis", withConfiguration: moreConfig), for: .normal)
        self.moreButton.tintColor = .white
        self.moreButton.addTarget(self, action: #selector(self.morePressed), for: .touchUpInside)
        self.infoContainerView.addSubview(self.moreButton)
    }
    
    // MARK: - Setup Shared Bottom Controls (Apple Music Authentic)
    private func setupSharedBottomControls() {
        // Scrubber
        self.progressSlider.minimumValue = 0.0
        self.progressSlider.maximumValue = 1.0
        self.progressSlider.minimumTrackTintColor = .white
        self.progressSlider.maximumTrackTintColor = UIColor(white: 1.0, alpha: 0.20)
        self.progressSlider.setThumbImage(self.generateSliderThumb(size: 7.0), for: .normal)
        self.progressSlider.addTarget(self, action: #selector(self.sliderTouchBegan), for: .touchDown)
        self.progressSlider.addTarget(self, action: #selector(self.sliderValueChanged), for: .valueChanged)
        self.progressSlider.addTarget(self, action: #selector(self.sliderTouchEnded), for: [.touchUpInside, .touchUpOutside])
        self.bottomControlsContainer.addSubview(self.progressSlider)
        
        self.currentTimeLabel.textColor = UIColor(white: 1.0, alpha: 0.55)
        self.currentTimeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12.0, weight: .regular)
        self.currentTimeLabel.text = "0:00"
        self.bottomControlsContainer.addSubview(self.currentTimeLabel)
        
        self.remainingTimeLabel.textColor = UIColor(white: 1.0, alpha: 0.55)
        self.remainingTimeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12.0, weight: .regular)
        self.remainingTimeLabel.text = "-0:00"
        self.remainingTimeLabel.textAlignment = .right
        self.bottomControlsContainer.addSubview(self.remainingTimeLabel)
        
        // Format Badge Pill (Lossless / Dolby Atmos)
        self.setupFormatBadge(self.formatBadgeButton)
        self.bottomControlsContainer.addSubview(self.formatBadgeButton)
        
        // Transport Controls Row: Shuffle | Prev | Play/Pause | Next | Repeat
        let subConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        self.shuffleButton.setImage(UIImage(systemName: "shuffle", withConfiguration: subConfig), for: .normal)
        self.shuffleButton.tintColor = UIColor(white: 1.0, alpha: 0.60)
        self.shuffleButton.addTarget(self, action: #selector(self.shufflePressed), for: .touchUpInside)
        self.controlsContainerView.addSubview(self.shuffleButton)
        
        let skipConfig = UIImage.SymbolConfiguration(pointSize: 28, weight: .bold)
        self.previousButton.setImage(UIImage(systemName: "backward.fill", withConfiguration: skipConfig), for: .normal)
        self.previousButton.tintColor = .white
        self.previousButton.addTarget(self, action: #selector(self.previousPressed), for: .touchUpInside)
        self.controlsContainerView.addSubview(self.previousButton)
        
        let playConfig = UIImage.SymbolConfiguration(pointSize: 42, weight: .bold)
        self.playPauseButton.setImage(UIImage(systemName: "play.fill", withConfiguration: playConfig), for: .normal)
        self.playPauseButton.tintColor = .white
        self.playPauseButton.addTarget(self, action: #selector(self.playPausePressed), for: .touchUpInside)
        self.controlsContainerView.addSubview(self.playPauseButton)
        
        self.nextButton.setImage(UIImage(systemName: "forward.fill", withConfiguration: skipConfig), for: .normal)
        self.nextButton.tintColor = .white
        self.nextButton.addTarget(self, action: #selector(self.nextPressed), for: .touchUpInside)
        self.controlsContainerView.addSubview(self.nextButton)
        
        self.repeatButton.setImage(UIImage(systemName: "repeat", withConfiguration: subConfig), for: .normal)
        self.repeatButton.tintColor = UIColor(white: 1.0, alpha: 0.60)
        self.repeatButton.addTarget(self, action: #selector(self.repeatPressed), for: .touchUpInside)
        self.controlsContainerView.addSubview(self.repeatButton)
        
        self.bottomControlsContainer.addSubview(self.controlsContainerView)
        
        // Volume Row
        self.setupVolumeRow(container: self.volumeContainerView, minIcon: self.volumeMinIcon, slider: self.volumeSlider, maxIcon: self.volumeMaxIcon)
        self.bottomControlsContainer.addSubview(self.volumeContainerView)
        
        // Bottom Bar (Lyrics | AirPlay | Queue)
        self.setupBottomBar(container: self.bottomBarContainer, lyricsBtn: self.bottomLyricsButton, airplayBtn: self.bottomAirplayButton, queueBtn: self.bottomQueueButton)
        self.bottomControlsContainer.addSubview(self.bottomBarContainer)
    }
    
    // MARK: - Setup Lyrics Pane
    private func setupLyricsPane() {
        // Top Header: Mini Artwork + Title + Artist + Star + More
        self.lyricsContainerView.addSubview(self.lyricsHeaderView)
        
        self.lyricsHeaderArtwork.contentMode = .scaleAspectFill
        self.lyricsHeaderArtwork.clipsToBounds = true
        self.lyricsHeaderArtwork.layer.cornerRadius = 8.0
        self.lyricsHeaderArtwork.layer.cornerCurve = .continuous
        self.lyricsHeaderArtwork.backgroundColor = UIColor(white: 0.15, alpha: 1.0)
        self.lyricsHeaderArtwork.isUserInteractionEnabled = true
        self.lyricsHeaderArtwork.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.nowPlayingSegmentPressed)))
        self.lyricsHeaderView.addSubview(self.lyricsHeaderArtwork)
        
        self.lyricsHeaderInfoView.isUserInteractionEnabled = true
        self.lyricsHeaderInfoView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.nowPlayingSegmentPressed)))
        self.lyricsHeaderView.addSubview(self.lyricsHeaderInfoView)
        
        self.lyricsTrackTitle.textColor = .white
        self.lyricsTrackTitle.font = UIFont.systemFont(ofSize: 16.0, weight: .bold)
        self.lyricsTrackTitle.lineBreakMode = .byTruncatingTail
        self.lyricsHeaderInfoView.addSubview(self.lyricsTrackTitle)
        
        self.lyricsTrackArtist.textColor = UIColor(white: 1.0, alpha: 0.65)
        self.lyricsTrackArtist.font = UIFont.systemFont(ofSize: 13.5, weight: .regular)
        self.lyricsTrackArtist.lineBreakMode = .byTruncatingTail
        self.lyricsHeaderInfoView.addSubview(self.lyricsTrackArtist)
        
        let starConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        self.lyricsFavoriteButton.setImage(UIImage(systemName: "star", withConfiguration: starConfig), for: .normal)
        self.lyricsFavoriteButton.tintColor = .white
        self.lyricsFavoriteButton.addTarget(self, action: #selector(self.favoritePressed), for: .touchUpInside)
        self.lyricsHeaderView.addSubview(self.lyricsFavoriteButton)
        
        let moreConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        self.lyricsMoreButton.setImage(UIImage(systemName: "ellipsis", withConfiguration: moreConfig), for: .normal)
        self.lyricsMoreButton.tintColor = .white
        self.lyricsMoreButton.addTarget(self, action: #selector(self.morePressed), for: .touchUpInside)
        self.lyricsHeaderView.addSubview(self.lyricsMoreButton)
        
        // Static Lyrics Table Container (Holds mask so mask doesn't scroll with table offset)
        self.lyricsTableContainer.clipsToBounds = true
        self.lyricsContainerView.addSubview(self.lyricsTableContainer)
        
        self.lyricsTableView.backgroundColor = .clear
        self.lyricsTableView.separatorStyle = .none
        self.lyricsTableView.dataSource = self
        self.lyricsTableView.delegate = self
        self.lyricsTableView.showsVerticalScrollIndicator = false
        self.lyricsTableView.register(SGDoxLyricsCell.self, forCellReuseIdentifier: "SGDoxLyricsCell")
        self.lyricsTableContainer.addSubview(self.lyricsTableView)
        
        // Plain text fallback
        self.lyricsPlainTextView.backgroundColor = .clear
        self.lyricsPlainTextView.textColor = UIColor.white.withAlphaComponent(0.9)
        self.lyricsPlainTextView.font = UIFont.systemFont(ofSize: 22, weight: .semibold)
        self.lyricsPlainTextView.isEditable = false
        self.lyricsPlainTextView.isSelectable = false
        self.lyricsPlainTextView.textAlignment = .left
        self.lyricsPlainTextView.showsVerticalScrollIndicator = false
        self.lyricsPlainTextView.isHidden = true
        self.lyricsTableContainer.addSubview(self.lyricsPlainTextView)
        
        self.lyricsLoadingIndicator.color = .white
        self.lyricsLoadingIndicator.hidesWhenStopped = true
        self.lyricsContainerView.addSubview(self.lyricsLoadingIndicator)
        
        self.lyricsStatusLabel.textColor = UIColor.white.withAlphaComponent(0.60)
        self.lyricsStatusLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        self.lyricsStatusLabel.textAlignment = .center
        self.lyricsStatusLabel.numberOfLines = 0
        self.lyricsStatusLabel.isHidden = true
        self.lyricsContainerView.addSubview(self.lyricsStatusLabel)
        
        // Apple Music Sing Floating Button (Mic)
        let micConfig = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        self.lyricsSingButton.setImage(UIImage(systemName: "mic.fill", withConfiguration: micConfig), for: .normal)
        self.lyricsSingButton.tintColor = .white
        self.lyricsSingButton.backgroundColor = UIColor(white: 1.0, alpha: 0.16)
        self.lyricsSingButton.layer.cornerRadius = 21.0
        self.lyricsSingButton.layer.cornerCurve = .continuous
        self.lyricsSingButton.layer.borderWidth = 0.5
        self.lyricsSingButton.layer.borderColor = UIColor(white: 1.0, alpha: 0.22).cgColor
        self.lyricsSingButton.clipsToBounds = true
        self.lyricsSingButton.addTarget(self, action: #selector(self.singButtonPressed), for: .touchUpInside)
        self.lyricsContainerView.addSubview(self.lyricsSingButton)
    }
    
    // MARK: - Setup Queue Pane
    private func setupQueuePane() {
        self.queueContainerView.addSubview(self.queueHeaderView)
        
        self.queueTitleLabel.text = "Далее"
        self.queueTitleLabel.textColor = .white
        self.queueTitleLabel.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        self.queueHeaderView.addSubview(self.queueTitleLabel)
        
        self.queueCountLabel.textColor = UIColor(white: 1.0, alpha: 0.50)
        self.queueCountLabel.font = UIFont.systemFont(ofSize: 14, weight: .regular)
        self.queueHeaderView.addSubview(self.queueCountLabel)
        
        let shuffConfig = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        self.queueShuffleButton.setImage(UIImage(systemName: "shuffle", withConfiguration: shuffConfig), for: .normal)
        self.queueShuffleButton.tintColor = UIColor(white: 1.0, alpha: 0.85)
        self.queueShuffleButton.backgroundColor = UIColor(white: 1.0, alpha: 0.12)
        self.queueShuffleButton.layer.cornerRadius = 15
        self.queueShuffleButton.clipsToBounds = true
        self.queueShuffleButton.addTarget(self, action: #selector(self.queueShufflePressed), for: .touchUpInside)
        self.queueHeaderView.addSubview(self.queueShuffleButton)
        
        let clearConfig = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        self.queueClearButton.setImage(UIImage(systemName: "trash", withConfiguration: clearConfig), for: .normal)
        self.queueClearButton.tintColor = UIColor(white: 1.0, alpha: 0.85)
        self.queueClearButton.backgroundColor = UIColor(white: 1.0, alpha: 0.12)
        self.queueClearButton.layer.cornerRadius = 15
        self.queueClearButton.clipsToBounds = true
        self.queueClearButton.addTarget(self, action: #selector(self.queueClearPressed), for: .touchUpInside)
        self.queueHeaderView.addSubview(self.queueClearButton)
        
        self.queueTableView.backgroundColor = .clear
        self.queueTableView.separatorStyle = .singleLine
        self.queueTableView.separatorColor = UIColor(white: 1.0, alpha: 0.08)
        self.queueTableView.separatorInset = UIEdgeInsets(top: 0, left: 76, bottom: 0, right: 20)
        self.queueTableView.dataSource = self
        self.queueTableView.delegate = self
        self.queueTableView.showsVerticalScrollIndicator = false
        self.queueTableView.register(SGDoxPlayerQueueCell.self, forCellReuseIdentifier: "SGDoxPlayerQueueCell")
        self.queueContainerView.addSubview(self.queueTableView)
    }
    
    // MARK: - UI Helpers
    private func setupFormatBadge(_ button: UIButton) {
        let waveConfig = UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        button.setImage(UIImage(systemName: "waveform.path", withConfiguration: waveConfig), for: .normal)
        button.setTitle(" Lossless", for: .normal)
        button.setTitleColor(UIColor(white: 1.0, alpha: 0.85), for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 10.5, weight: .bold)
        button.tintColor = UIColor(white: 1.0, alpha: 0.85)
        button.backgroundColor = UIColor(white: 1.0, alpha: 0.12)
        button.layer.cornerRadius = 10
        button.layer.cornerCurve = .continuous
        button.clipsToBounds = true
        button.contentEdgeInsets = UIEdgeInsets(top: 2, left: 8, bottom: 2, right: 8)
        button.addTarget(self, action: #selector(self.formatBadgePressed), for: .touchUpInside)
    }
    
    private func setupVolumeRow(container: UIView, minIcon: UIImageView, slider: UISlider, maxIcon: UIImageView) {
        let minConfig = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        minIcon.image = UIImage(systemName: "speaker.fill", withConfiguration: minConfig)
        minIcon.tintColor = UIColor(white: 1.0, alpha: 0.45)
        minIcon.contentMode = .scaleAspectFit
        container.addSubview(minIcon)
        
        slider.minimumValue = 0.0
        slider.maximumValue = 1.0
        slider.value = AVAudioSession.sharedInstance().outputVolume
        slider.minimumTrackTintColor = UIColor(white: 1.0, alpha: 0.65)
        slider.maximumTrackTintColor = UIColor(white: 1.0, alpha: 0.20)
        slider.setThumbImage(self.generateVolumeThumb(), for: .normal)
        slider.addTarget(self, action: #selector(self.volumeChanged(_:)), for: .valueChanged)
        container.addSubview(slider)
        
        let maxConfig = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        maxIcon.image = UIImage(systemName: "speaker.wave.3.fill", withConfiguration: maxConfig)
        maxIcon.tintColor = UIColor(white: 1.0, alpha: 0.45)
        maxIcon.contentMode = .scaleAspectFit
        container.addSubview(maxIcon)
    }
    
    private func setupBottomBar(container: UIView, lyricsBtn: UIButton, airplayBtn: UIButton, queueBtn: UIButton) {
        let btnConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        lyricsBtn.setImage(UIImage(systemName: "quote.bubble", withConfiguration: btnConfig), for: .normal)
        lyricsBtn.tintColor = UIColor(white: 1.0, alpha: 0.70)
        lyricsBtn.layer.cornerRadius = 12.0
        lyricsBtn.layer.cornerCurve = .continuous
        lyricsBtn.clipsToBounds = true
        lyricsBtn.addTarget(self, action: #selector(self.lyricsSegmentPressed), for: .touchUpInside)
        container.addSubview(lyricsBtn)
        
        let airplayConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        airplayBtn.setImage(UIImage(systemName: "airplayaudio", withConfiguration: airplayConfig), for: .normal)
        airplayBtn.tintColor = UIColor(white: 1.0, alpha: 0.70)
        airplayBtn.layer.cornerRadius = 12.0
        airplayBtn.layer.cornerCurve = .continuous
        airplayBtn.clipsToBounds = true
        airplayBtn.addTarget(self, action: #selector(self.airplayPressed), for: .touchUpInside)
        container.addSubview(airplayBtn)
        
        let queueConfig = UIImage.SymbolConfiguration(pointSize: 19, weight: .medium)
        queueBtn.setImage(UIImage(systemName: "list.bullet", withConfiguration: queueConfig), for: .normal)
        queueBtn.tintColor = UIColor(white: 1.0, alpha: 0.70)
        queueBtn.layer.cornerRadius = 12.0
        queueBtn.layer.cornerCurve = .continuous
        queueBtn.clipsToBounds = true
        queueBtn.addTarget(self, action: #selector(self.queueSegmentPressed), for: .touchUpInside)
        container.addSubview(queueBtn)
    }
    
    private func generateSliderThumb(size: CGFloat) -> UIImage {
        let s = CGSize(width: size, height: size)
        UIGraphicsBeginImageContextWithOptions(s, false, 0.0)
        let ctx = UIGraphicsGetCurrentContext()
        ctx?.setFillColor(UIColor.white.cgColor)
        ctx?.fillEllipse(in: CGRect(origin: .zero, size: s))
        let img = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        return img
    }
    
    private func generateVolumeThumb() -> UIImage {
        let size = CGSize(width: 12, height: 12)
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        let ctx = UIGraphicsGetCurrentContext()
        ctx?.setFillColor(UIColor.white.cgColor)
        ctx?.fillEllipse(in: CGRect(origin: .zero, size: size))
        let img = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        return img
    }
    
    // MARK: - Layout Implementation
    private func applyLayout(bounds: CGRect, safeArea: UIEdgeInsets) {
        guard bounds.width > 0 && bounds.height > 0 else { return }
        
        self.backgroundImageView.frame = bounds
        self.ambientGradientLayer.frame = bounds
        self.backgroundBlurView.frame = bounds
        self.darkDimOverlay.frame = bounds
        self.videoContainerView.frame = bounds
        self.videoDimOverlay.frame = bounds
        self.videoPlayerLayer?.frame = bounds
        
        let statusBarH = self.validLayout?.statusBarHeight ?? 0.0
        let effectiveTop = max(safeArea.top, statusBarH, 48.0)
        
        // Grabber Handle
        self.grabberView.frame = CGRect(x: (bounds.width - 36.0) * 0.5, y: max(effectiveTop * 0.25, 8.0), width: 36.0, height: 5.0)
        
        // Shared Bottom Controls (Fixed at bottom of player)
        let bottomSafe = max(safeArea.bottom, 16.0)
        let bottomControlsH: CGFloat = 224.0
        let bottomControlsY = bounds.height - bottomControlsH - bottomSafe
        let bottomControlsRect = CGRect(x: 0, y: bottomControlsY, width: bounds.width, height: bottomControlsH)
        self.bottomControlsContainer.frame = bottomControlsRect
        self.layoutBottomControls(rect: self.bottomControlsContainer.bounds)
        
        // Central Content Area between top safe area and bottom controls
        let contentY = effectiveTop + 4.0
        let contentH = max(100.0, bottomControlsY - contentY - 6.0)
        let contentFrame = CGRect(x: 0, y: contentY, width: bounds.width, height: contentH)
        
        self.nowPlayingContainerView.frame = contentFrame
        self.lyricsContainerView.frame = contentFrame
        self.queueContainerView.frame = contentFrame
        
        self.layoutNowPlayingPane(bounds: self.nowPlayingContainerView.bounds)
        self.layoutLyricsPane(bounds: self.lyricsContainerView.bounds)
        self.layoutQueuePane(bounds: self.queueContainerView.bounds)
    }
    
    private func layoutBottomControls(rect: CGRect) {
        guard rect.width > 0 && rect.height > 0 else { return }
        
        // 1. Scrubber & Time labels
        self.progressSlider.frame = CGRect(x: 28.0, y: 0.0, width: rect.width - 56.0, height: 26.0)
        
        let labelY: CGFloat = 24.0
        let labelW: CGFloat = 60.0
        let labelH: CGFloat = 16.0
        self.currentTimeLabel.frame = CGRect(x: 28.0, y: labelY, width: labelW, height: labelH)
        self.remainingTimeLabel.frame = CGRect(x: rect.width - 28.0 - labelW, y: labelY, width: labelW, height: labelH)
        
        let badgeW: CGFloat = 94.0
        let badgeH: CGFloat = 20.0
        self.formatBadgeButton.frame = CGRect(x: (rect.width - badgeW) * 0.5, y: labelY - 2.0, width: badgeW, height: badgeH)
        
        // 2. Transport Controls Row
        let transY: CGFloat = 46.0
        let transH: CGFloat = 56.0
        self.controlsContainerView.frame = CGRect(x: 24.0, y: transY, width: rect.width - 48.0, height: transH)
        let cW = self.controlsContainerView.bounds.width
        let cMid = cW * 0.5
        
        let playSize: CGFloat = 52.0
        self.playPauseButton.frame = CGRect(x: cMid - playSize * 0.5, y: (transH - playSize) * 0.5, width: playSize, height: playSize)
        
        let skipSize: CGFloat = 40.0
        let skipDist: CGFloat = 64.0
        self.previousButton.frame = CGRect(x: cMid - skipDist - skipSize, y: (transH - skipSize) * 0.5, width: skipSize, height: skipSize)
        self.nextButton.frame = CGRect(x: cMid + skipDist, y: (transH - skipSize) * 0.5, width: skipSize, height: skipSize)
        
        let subSize: CGFloat = 34.0
        self.shuffleButton.frame = CGRect(x: 10.0, y: (transH - subSize) * 0.5, width: subSize, height: subSize)
        self.repeatButton.frame = CGRect(x: cW - subSize - 10.0, y: (transH - subSize) * 0.5, width: subSize, height: subSize)
        
        // 3. Volume Row
        let volY: CGFloat = 114.0
        let volH: CGFloat = 28.0
        self.volumeContainerView.frame = CGRect(x: 32.0, y: volY, width: rect.width - 64.0, height: volH)
        let vW = self.volumeContainerView.bounds.width
        self.volumeMinIcon.frame = CGRect(x: 0, y: 7, width: 14, height: 14)
        self.volumeMaxIcon.frame = CGRect(x: vW - 16, y: 6, width: 16, height: 16)
        self.volumeSlider.frame = CGRect(x: 24, y: 0, width: vW - 48, height: volH)
        
        // 4. Bottom Bar (Lyrics | AirPlay | Queue)
        let barY: CGFloat = 158.0
        let barH: CGFloat = 44.0
        self.bottomBarContainer.frame = CGRect(x: 32.0, y: barY, width: rect.width - 64.0, height: barH)
        let bW = self.bottomBarContainer.bounds.width
        let itemW: CGFloat = 44.0
        self.bottomLyricsButton.frame = CGRect(x: 0, y: 0, width: itemW, height: itemW)
        self.bottomAirplayButton.frame = CGRect(x: (bW - itemW) * 0.5, y: 0, width: itemW, height: itemW)
        self.bottomQueueButton.frame = CGRect(x: bW - itemW, y: 0, width: itemW, height: itemW)
    }
    
    private func layoutNowPlayingPane(bounds: CGRect) {
        guard bounds.width > 0 && bounds.height > 0 else { return }
        
        let infoH: CGFloat = 50.0
        let bottomPad: CGFloat = 10.0
        let availableArtH = max(120.0, bounds.height - infoH - bottomPad - 16.0)
        let artSide = min(bounds.width - 56.0, availableArtH)
        let artX = (bounds.width - artSide) * 0.5
        let artY = max(4.0, (availableArtH - artSide) * 0.5)
        
        self.artworkContainerView.frame = CGRect(x: artX, y: artY, width: artSide, height: artSide)
        self.artworkImageView.frame = self.artworkContainerView.bounds
        self.artworkContainerView.layer.shadowPath = UIBezierPath(roundedRect: self.artworkContainerView.bounds, cornerRadius: 24.0).cgPath
        
        let glowPad: CGFloat = 28.0
        self.artworkAmbientGlowView.frame = CGRect(x: artX - glowPad * 0.5, y: artY - glowPad * 0.5, width: artSide + glowPad, height: artSide + glowPad)
        self.artworkGlowGradientLayer.frame = self.artworkAmbientGlowView.bounds
        
        // Info Row below Artwork
        let infoY = self.artworkContainerView.frame.maxY + 14.0
        self.infoContainerView.frame = CGRect(x: 28.0, y: infoY, width: bounds.width - 56.0, height: infoH)
        let infoW = self.infoContainerView.bounds.width
        
        let actionBtnSize: CGFloat = 34.0
        self.moreButton.frame = CGRect(x: infoW - actionBtnSize, y: 8, width: actionBtnSize, height: actionBtnSize)
        self.favoriteButton.frame = CGRect(x: infoW - actionBtnSize * 2 - 8, y: 8, width: actionBtnSize, height: actionBtnSize)
        
        let titleW = max(0, infoW - (actionBtnSize * 2 + 16))
        self.titleLabel.frame = CGRect(x: 0, y: 1, width: titleW, height: 26)
        self.artistLabel.frame = CGRect(x: 0, y: 28, width: titleW, height: 22)
    }
    
    private func layoutLyricsPane(bounds: CGRect) {
        guard bounds.width > 0 && bounds.height > 0 else { return }
        
        // Top Header: Artwork thumbnail (44x44) + Title + Artist + Star + More
        let headerH: CGFloat = 48.0
        self.lyricsHeaderView.frame = CGRect(x: 24.0, y: 0.0, width: bounds.width - 48.0, height: headerH)
        let hW = self.lyricsHeaderView.bounds.width
        
        self.lyricsHeaderArtwork.frame = CGRect(x: 0, y: 2, width: 44, height: 44)
        
        let actionBtnSize: CGFloat = 34.0
        self.lyricsMoreButton.frame = CGRect(x: hW - actionBtnSize, y: 7, width: actionBtnSize, height: actionBtnSize)
        self.lyricsFavoriteButton.frame = CGRect(x: hW - actionBtnSize * 2 - 6, y: 7, width: actionBtnSize, height: actionBtnSize)
        
        let textX: CGFloat = 56.0
        let textW = max(0, hW - textX - (actionBtnSize * 2 + 12))
        self.lyricsHeaderInfoView.frame = CGRect(x: textX, y: 3, width: textW, height: 42)
        self.lyricsTrackTitle.frame = CGRect(x: 0, y: 1, width: textW, height: 21)
        self.lyricsTrackArtist.frame = CGRect(x: 0, y: 22, width: textW, height: 18)
        
        // Floating Sing (Mic) Button
        let micSize: CGFloat = 42.0
        let micX = bounds.width - micSize - 24.0
        let micY = bounds.height - micSize - 6.0
        self.lyricsSingButton.frame = CGRect(x: micX, y: micY, width: micSize, height: micSize)
        
        // Lyrics Table Container & Table
        let tableTop = headerH + 8.0
        let tableH = max(60.0, bounds.height - tableTop - 4.0)
        self.lyricsTableContainer.frame = CGRect(x: 0, y: tableTop, width: bounds.width, height: tableH)
        self.lyricsTableView.frame = self.lyricsTableContainer.bounds
        self.lyricsPlainTextView.frame = CGRect(x: 24.0, y: 0, width: bounds.width - 48.0, height: tableH)
        self.lyricsTableView.contentInset = UIEdgeInsets(top: 16.0, left: 0, bottom: tableH * 0.45, right: 0)
        
        self.lyricsLoadingIndicator.center = CGPoint(x: bounds.width * 0.5, y: tableTop + tableH * 0.35)
        self.lyricsStatusLabel.frame = CGRect(x: 32.0, y: tableTop + tableH * 0.30, width: bounds.width - 64.0, height: 60.0)
        
        self.updateLyricsMask()
    }
    
    private func updateLyricsMask() {
        guard self.lyricsTableContainer.bounds.width > 0 && self.lyricsTableContainer.bounds.height > 0 else { return }
        let mask = CAGradientLayer()
        mask.frame = self.lyricsTableContainer.bounds
        mask.colors = [
            UIColor.clear.cgColor,
            UIColor.black.cgColor,
            UIColor.black.cgColor,
            UIColor.clear.cgColor
        ]
        mask.locations = [0.0, 0.08, 0.88, 1.0]
        self.lyricsTableContainer.layer.mask = mask
    }
    
    private func layoutQueuePane(bounds: CGRect) {
        guard bounds.width > 0 && bounds.height > 0 else { return }
        
        // Top Header
        let headerH: CGFloat = 44.0
        self.queueHeaderView.frame = CGRect(x: 24.0, y: 0.0, width: bounds.width - 48.0, height: headerH)
        let qW = self.queueHeaderView.bounds.width
        
        self.queueTitleLabel.frame = CGRect(x: 0, y: 8, width: 80, height: 26)
        self.queueCountLabel.frame = CGRect(x: 88, y: 12, width: 100, height: 20)
        
        let actSize: CGFloat = 30.0
        self.queueClearButton.frame = CGRect(x: qW - actSize, y: 7, width: actSize, height: actSize)
        self.queueShuffleButton.frame = CGRect(x: qW - actSize * 2 - 10, y: 7, width: actSize, height: actSize)
        
        // Table View
        let tableTop = headerH + 6.0
        let tableH = max(60.0, bounds.height - tableTop)
        self.queueTableView.frame = CGRect(x: 0, y: tableTop, width: bounds.width, height: tableH)
        self.queueTableView.contentInset = UIEdgeInsets(top: 8.0, left: 0, bottom: 20.0, right: 0)
    }
    
    // MARK: - Update Content
    private func updateContent() {
        let manager = SGDoxMusicManager.shared
        guard let track = manager.currentTrack else {
            self.titleLabel.text = "Нет трека"
            self.artistLabel.text = "DoxMusic"
            self.lyricsTrackTitle.text = "Нет трека"
            self.lyricsTrackArtist.text = "DoxMusic"
            self.artworkImageView.image = SGDoxImageLoader.shared.placeholderArtwork()
            self.lyricsHeaderArtwork.image = SGDoxImageLoader.shared.placeholderArtwork()
            self.teardownVideoPlayback()
            return
        }
        
        if self.displayedTrackId != track.id {
            self.displayedTrackId = track.id
            self.titleLabel.text = track.title
            self.artistLabel.text = track.artist
            self.lyricsTrackTitle.text = track.title
            self.lyricsTrackArtist.text = track.artist
            
            // Artwork
            self.artworkImageView.image = SGDoxImageLoader.shared.placeholderArtwork()
            self.lyricsHeaderArtwork.image = SGDoxImageLoader.shared.placeholderArtwork()
            
            SGDoxImageLoader.shared.loadArtwork(for: track, targetSize: CGSize(width: 400, height: 400)) { [weak self] image in
                guard let self = self, self.displayedTrackId == track.id, let img = image else { return }
                self.artworkImageView.image = img
                self.lyricsHeaderArtwork.image = img
                self.backgroundImageView.image = img
                self.updateAmbientColor(from: img)
            }
            
            // Lyrics
            self.currentLyrics = nil
            self.activeLyricsIndex = -1
            self.loadLyricsIfNeeded()
            
            // Video Background / Animated Canvas
            SGDoxVideoClipService.shared.fetchVideoClip(for: track) { [weak self] videoUrl in
                guard let self = self, self.displayedTrackId == track.id else { return }
                self.setupVideoPlayback(urlString: videoUrl)
            }
        }
        
        // Format Badges: Lossless & Dolby Atmos
        let badgeTitle: String
        let badgeIcon: String
        if track.isDolbyAtmos {
            badgeTitle = " Dolby Atmos"
            badgeIcon = "dot.radiowaves.left.and.right"
        } else if track.isLossless {
            badgeTitle = " Lossless"
            badgeIcon = "waveform.path"
        } else {
            badgeTitle = " AAC 256k"
            badgeIcon = "waveform"
        }
        
        let waveConfig = UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        let iconImg = UIImage(systemName: badgeIcon, withConfiguration: waveConfig)
        self.formatBadgeButton.setImage(iconImg, for: .normal)
        self.formatBadgeButton.setTitle(badgeTitle, for: .normal)
        
        // Play / Pause Icons
        let playIconName = manager.isPlaying ? "pause.fill" : "play.fill"
        let playCfg = UIImage.SymbolConfiguration(pointSize: 42, weight: .bold)
        self.playPauseButton.setImage(UIImage(systemName: playIconName, withConfiguration: playCfg), for: .normal)
        
        // Star Favorite Icons
        let isFav = manager.isFavorite(track: track)
        let starName = isFav ? "star.fill" : "star"
        let starColor = isFav ? UIColor(red: 1.0, green: 0.28, blue: 0.38, alpha: 1.0) : .white
        let starConfig = UIImage.SymbolConfiguration(pointSize: 21, weight: .medium)
        let starImg = UIImage(systemName: starName, withConfiguration: starConfig)
        self.favoriteButton.setImage(starImg, for: .normal)
        self.favoriteButton.tintColor = starColor
        self.lyricsFavoriteButton.setImage(starImg, for: .normal)
        self.lyricsFavoriteButton.tintColor = starColor
        
        // Shuffle & Repeat states
        self.shuffleButton.tintColor = manager.isShuffled ? .white : UIColor(white: 1.0, alpha: 0.45)
        switch manager.repeatMode {
        case .none:
            self.repeatButton.setImage(UIImage(systemName: "repeat", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)), for: .normal)
            self.repeatButton.tintColor = UIColor(white: 1.0, alpha: 0.45)
        case .all:
            self.repeatButton.setImage(UIImage(systemName: "repeat", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)), for: .normal)
            self.repeatButton.tintColor = .white
        case .one:
            self.repeatButton.setImage(UIImage(systemName: "repeat.1", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)), for: .normal)
            self.repeatButton.tintColor = .white
        }
        
        // Mode highlights on bottom bar
        self.updateBottomBarActiveState()
    }
    
    private func updateBottomBarActiveState() {
        let activeBg = UIColor(white: 1.0, alpha: 0.22)
        self.bottomLyricsButton.backgroundColor = (self.currentMode == .lyrics) ? activeBg : .clear
        self.bottomLyricsButton.tintColor = (self.currentMode == .lyrics) ? .white : UIColor(white: 1.0, alpha: 0.70)
        
        self.bottomQueueButton.backgroundColor = (self.currentMode == .queue) ? activeBg : .clear
        self.bottomQueueButton.tintColor = (self.currentMode == .queue) ? .white : UIColor(white: 1.0, alpha: 0.70)
    }
    
    private func reloadQueueData() {
        self.cachedQueue = SGDoxMusicManager.shared.currentQueue
        self.queueCountLabel.text = "\(self.cachedQueue.count) треков"
        self.queueTableView.reloadData()
    }
    
    private func updateAmbientColor(from image: UIImage) {
        let colors = self.extractDominantColors(from: image)
        UIView.animate(withDuration: 0.6) {
            self.ambientGradientLayer.colors = [
                colors.top.withAlphaComponent(0.85).cgColor,
                colors.bottom.withAlphaComponent(0.95).cgColor
            ]
            self.artworkGlowGradientLayer.colors = [
                colors.top.withAlphaComponent(0.55).cgColor,
                colors.top.withAlphaComponent(0.15).cgColor,
                UIColor.clear.cgColor
            ]
        }
    }
    
    private func extractDominantColors(from image: UIImage) -> (top: UIColor, bottom: UIColor) {
        guard let cgImg = image.cgImage else {
            return (UIColor(red: 0.15, green: 0.12, blue: 0.25, alpha: 1.0), UIColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1.0))
        }
        let w = 8
        let h = 8
        var rawData = [UInt8](repeating: 0, count: w * h * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: &rawData, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        ctx?.draw(cgImg, in: CGRect(x: 0, y: 0, width: w, height: h))
        
        var rTop: CGFloat = 0, gTop: CGFloat = 0, bTop: CGFloat = 0
        var rBot: CGFloat = 0, gBot: CGFloat = 0, bBot: CGFloat = 0
        let half = h / 2
        
        for y in 0..<half {
            for x in 0..<w {
                let idx = (y * w + x) * 4
                rTop += CGFloat(rawData[idx])
                gTop += CGFloat(rawData[idx + 1])
                bTop += CGFloat(rawData[idx + 2])
            }
        }
        for y in half..<h {
            for x in 0..<w {
                let idx = (y * w + x) * 4
                rBot += CGFloat(rawData[idx])
                gBot += CGFloat(rawData[idx + 1])
                bBot += CGFloat(rawData[idx + 2])
            }
        }
        
        let count = CGFloat(w * half * 255)
        let top = UIColor(red: min(1.0, rTop / count * 1.3), green: min(1.0, gTop / count * 1.3), blue: min(1.0, bTop / count * 1.3), alpha: 1.0)
        let bottom = UIColor(red: rBot / count * 0.7, green: gBot / count * 0.7, blue: bBot / count * 0.7, alpha: 1.0)
        return (top, bottom)
    }
    
    // MARK: - Navigation Mode Switching (Apple Music One-Screen Fluid Morph)
    @objc private func artworkTapped() {
        self.switchMode(to: .lyrics)
    }
    
    @objc private func nowPlayingSegmentPressed() {
        self.switchMode(to: .nowPlaying)
    }
    
    @objc private func lyricsSegmentPressed() {
        if self.currentMode == .lyrics {
            self.switchMode(to: .nowPlaying)
        } else {
            self.switchMode(to: .lyrics)
        }
    }
    
    @objc private func queueSegmentPressed() {
        if self.currentMode == .queue {
            self.switchMode(to: .nowPlaying)
        } else {
            self.switchMode(to: .queue)
        }
    }
    
    private func switchMode(to targetMode: PlayerMode) {
        guard self.currentMode != targetMode else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        self.currentMode = targetMode
        
        self.updateBottomBarActiveState()
        
        if targetMode == .lyrics {
            self.loadLyricsIfNeeded()
        } else if targetMode == .queue {
            self.reloadQueueData()
        }
        
        let activeContainer: UIView
        switch targetMode {
        case .nowPlaying: activeContainer = self.nowPlayingContainerView
        case .lyrics: activeContainer = self.lyricsContainerView
        case .queue: activeContainer = self.queueContainerView
        }
        
        let hiddenContainers = [self.nowPlayingContainerView, self.lyricsContainerView, self.queueContainerView].filter { $0 !== activeContainer }
        
        activeContainer.isHidden = false
        activeContainer.alpha = 0.0
        
        // Fluid spring transition
        UIView.animate(withDuration: 0.32, delay: 0, usingSpringWithDamping: 0.84, initialSpringVelocity: 0.5, options: [.allowUserInteraction], animations: {
            activeContainer.alpha = 1.0
            for c in hiddenContainers {
                c.alpha = 0.0
            }
        }) { _ in
            for c in hiddenContainers {
                c.isHidden = true
            }
            if targetMode == .lyrics {
                self.syncLyricsPosition(currentTime: SGDoxMusicManager.shared.currentTime, animated: false)
                self.updateLyricsMask()
            }
        }
    }
    
    // MARK: - Lyrics Real-Time Progressive Logic
    private func loadLyricsIfNeeded() {
        guard let track = SGDoxMusicManager.shared.currentTrack else {
            self.showLyricsStatus("Нет воспроизводимого трека")
            return
        }
        
        self.lyricsTrackTitle.text = track.title
        self.lyricsTrackArtist.text = track.artist
        
        if let current = self.currentLyrics, current.trackId == track.id {
            self.updateLyricsDisplay(current)
            return
        }
        
        self.currentLyrics = nil
        self.activeLyricsIndex = -1
        self.lyricsTableView.isHidden = true
        self.lyricsPlainTextView.isHidden = true
        self.lyricsStatusLabel.isHidden = true
        self.lyricsLoadingIndicator.startAnimating()
        
        SGDoxLyricsService.shared.fetchLyrics(for: track) { [weak self] lyrics in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard let currentTrack = SGDoxMusicManager.shared.currentTrack, currentTrack.id == track.id else { return }
                self.lyricsLoadingIndicator.stopAnimating()
                
                if let lyrics = lyrics, (!lyrics.lines.isEmpty || !(lyrics.plainLyrics?.isEmpty ?? true)) {
                    self.currentLyrics = lyrics
                    self.updateLyricsDisplay(lyrics)
                    self.syncLyricsPosition(currentTime: SGDoxMusicManager.shared.currentTime, animated: false)
                } else {
                    self.showLyricsStatus("Текст песни не найден")
                }
            }
        }
    }
    
    private func showLyricsStatus(_ text: String) {
        self.lyricsLoadingIndicator.stopAnimating()
        self.lyricsTableView.isHidden = true
        self.lyricsPlainTextView.isHidden = true
        self.lyricsStatusLabel.text = text
        self.lyricsStatusLabel.isHidden = false
    }
    
    private func updateLyricsDisplay(_ lyrics: SGDoxLyrics) {
        self.lyricsStatusLabel.isHidden = true
        self.lyricsHeightCache.removeAll(keepingCapacity: true)
        if !lyrics.lines.isEmpty {
            self.lyricsTableView.isHidden = false
            self.lyricsPlainTextView.isHidden = true
            self.lyricsTableView.reloadData()
            self.updateLyricsMask()
        } else if let plain = lyrics.plainLyrics, !plain.isEmpty {
            self.lyricsTableView.isHidden = true
            self.lyricsPlainTextView.isHidden = false
            self.lyricsPlainTextView.text = plain
        } else {
            self.showLyricsStatus("Текст песни пуст")
        }
    }
    
    private func syncLyricsPosition(currentTime: Double, animated: Bool = true) {
        guard let lyrics = self.currentLyrics, !lyrics.lines.isEmpty else { return }
        
        var newIndex = -1
        for (i, line) in lyrics.lines.enumerated() {
            if line.time <= currentTime {
                newIndex = i
            } else {
                break
            }
        }
        
        let lineDuration: Double
        if newIndex >= 0 && newIndex < lyrics.lines.count {
            let nextTimestamp = (newIndex + 1 < lyrics.lines.count) ? lyrics.lines[newIndex + 1].timestamp : (lyrics.lines[newIndex].timestamp + 4.5)
            lineDuration = max(1.0, nextTimestamp - lyrics.lines[newIndex].timestamp)
        } else {
            lineDuration = 4.0
        }
        
        if newIndex != self.activeLyricsIndex {
            let previousIndex = self.activeLyricsIndex
            self.activeLyricsIndex = newIndex
            
            var indexPathsToReload: [IndexPath] = []
            if previousIndex >= 0 && previousIndex < lyrics.lines.count {
                indexPathsToReload.append(IndexPath(row: previousIndex, section: 0))
            }
            if newIndex >= 0 && newIndex < lyrics.lines.count {
                indexPathsToReload.append(IndexPath(row: newIndex, section: 0))
            }
            
            for indexPath in indexPathsToReload {
                if let cell = self.lyricsTableView.cellForRow(at: indexPath) as? SGDoxLyricsCell {
                    let line = lyrics.lines[indexPath.row]
                    cell.configure(line: line, isActive: indexPath.row == newIndex, currentTime: currentTime, lineDuration: lineDuration)
                }
            }
            
            if !self.isUserScrollingLyrics && newIndex >= 0 && newIndex < lyrics.lines.count {
                let targetIndexPath = IndexPath(row: newIndex, section: 0)
                self.lyricsTableView.scrollToRow(at: targetIndexPath, at: .middle, animated: animated)
            }
        } else if newIndex >= 0 && newIndex < lyrics.lines.count {
            let activeIndexPath = IndexPath(row: newIndex, section: 0)
            if let cell = self.lyricsTableView.cellForRow(at: activeIndexPath) as? SGDoxLyricsCell {
                cell.updateProgress(currentTime: currentTime, lineDuration: lineDuration)
            }
        }
    }
    
    // MARK: - Actions & Volume
    @objc private func volumeChanged(_ slider: UISlider) {
        SGDoxMusicManager.shared.volume = slider.value
        if let systemSlider = self.hiddenVolumeView.subviews.first(where: { $0 is UISlider }) as? UISlider {
            systemSlider.value = slider.value
        }
    }
    
    @objc private func airplayPressed() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        for subview in self.hiddenVolumeView.subviews {
            if let btn = subview as? UIButton {
                btn.sendActions(for: .touchUpInside)
                return
            }
        }
    }
    
    @objc private func singButtonPressed() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let overlay = UndoOverlayController(presentationData: self.presentationData, content: .actionSucceeded(title: "Apple Music Sing", text: "Режим вокала активен", cancel: nil, destructive: false), elevatedLayout: false, action: { _ in return false })
        self.present(overlay, in: .window(.root))
    }
    
    @objc private func formatBadgePressed() {
        guard let track = SGDoxMusicManager.shared.currentTrack else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        
        let title: String
        let desc: String
        if track.isDolbyAtmos {
            title = "Dolby Atmos (Пространственное аудио)"
            desc = "Трек сведён с многоканальным позиционированием инструментов для создания объёмной сцены."
        } else if track.isLossless {
            title = "Apple Lossless (ALAC 24-bit/48kHz)"
            desc = "Аудиофайл воспроизводится без потерь в оригинальном студийном качестве с сохранением всех деталей."
        } else {
            title = "AAC 256 кбит/с"
            desc = "Высококачественный аудиопоток с оптимизированной компрессией."
        }
        
        let alert = UIAlertController(title: title, message: desc, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Понятно", style: .default, handler: nil))
        self.present(alert, animated: true)
    }
    
    @objc private func morePressed() {
        guard let track = SGDoxMusicManager.shared.currentTrack else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        
        let isFav = SGDoxMusicManager.shared.isFavorite(track: track)
        let isDown = SGDoxMusicOfflineManager.shared.isDownloaded(trackId: track.id)
        let isWave = SGDoxMusicManager.shared.isWaveEnabled
        
        let items: [SGDoxMusicMenuItem] = [
            SGDoxMusicMenuItem(iconName: "pin.fill", title: "Закрепить песню в профиле", action: { [weak self] in
                self?.pinToProfilePressed()
            }),
            SGDoxMusicMenuItem(iconName: isWave ? "waveform.badge.minus" : "waveform.badge.plus", title: isWave ? "Выключить Волну" : "Включить Волну", action: { [weak self] in
                SGDoxMusicManager.shared.isWaveEnabled.toggle()
                if SGDoxMusicManager.shared.isWaveEnabled { SGDoxMusicManager.shared.startWave() }
                self?.updateContent()
            }),
            SGDoxMusicMenuItem(iconName: "person.2.fill", title: "Совместный эфир", action: { [weak self] in
                self?.listenTogetherPressed()
            }),
            SGDoxMusicMenuItem(iconName: "mic.fill", title: "Перейти к артисту", subtitle: track.artist, action: { [weak self] in
                self?.artistLabelTapped()
            }),
            SGDoxMusicMenuItem(
                iconName: isDown ? "trash.fill" : "arrow.down.circle",
                title: isDown ? "Удалить из офлайна" : "Скачать для офлайна",
                isDestructive: isDown,
                action: { [weak self] in
                    self?.downloadPressed()
                }
            )
        ]
        
        let sourceBtn = (self.currentMode == .lyrics ? self.lyricsMoreButton : self.moreButton)
        SGDoxMusicContextMenu.show(
            in: self.view,
            sourceButton: sourceBtn,
            isFavorite: isFav,
            onToggleFavorite: { [weak self] in
                self?.favoritePressed()
            },
            onShare: { [weak self] in
                self?.shareCurrentTrack()
            },
            items: items
        )
    }
    
    private func shareCurrentTrack() {
        guard let track = SGDoxMusicManager.shared.currentTrack else { return }
        let shareText = "\(track.artist) — \(track.title)\nСлушайте в DoxMusic"
        let activityVc = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)
        activityVc.popoverPresentationController?.sourceView = self.view
        activityVc.popoverPresentationController?.sourceRect = CGRect(x: self.view.bounds.width * 0.5, y: self.view.bounds.height * 0.5, width: 1, height: 1)
        self.present(activityVc, animated: true)
    }
    
    private func listenTogetherPressed() {
        guard let track = SGDoxMusicManager.shared.currentTrack else { return }
        let manager = SGDoxListenTogetherManager.shared
        
        let alert = UIAlertController(title: "Совместный эфир", message: manager.isInSession ? "Вы слушаете музыку совместно." : "Слушайте музыку синхронно с друзьями в DoxGram.", preferredStyle: .actionSheet)
        alert.popoverPresentationController?.sourceView = self.view
        alert.popoverPresentationController?.sourceRect = CGRect(x: self.view.bounds.width * 0.5, y: self.view.bounds.height * 0.5, width: 1, height: 1)
        
        if manager.isInSession {
            alert.addAction(UIAlertAction(title: "Синхронизировать", style: .default, handler: { _ in
                SGDoxMusicManager.shared.seek(to: SGDoxMusicManager.shared.currentTime)
            }))
            alert.addAction(UIAlertAction(title: "Завершить эфир", style: .destructive, handler: { [weak self] _ in
                manager.leaveSession()
                self?.updateContent()
            }))
        } else {
            alert.addAction(UIAlertAction(title: "Отправить приглашение в чат", style: .default, handler: { [weak self] _ in
                self?.presentPeerSelectionForListenTogether(track: track)
            }))
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: nil))
        self.present(alert, animated: true)
    }
    
    private func presentPeerSelectionForListenTogether(track: SGDoxMusicTrack) {
        let text = SGDoxListenTogetherManager.shared.generateInviteText(for: track, offset: SGDoxMusicManager.shared.currentTime)
        let shareController = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        shareController.popoverPresentationController?.sourceView = self.view
        shareController.popoverPresentationController?.sourceRect = CGRect(x: self.view.bounds.width * 0.5, y: self.view.bounds.height * 0.5, width: 1, height: 1)
        self.present(shareController, animated: true)
    }
    
    private func pinToProfilePressed() {
        guard let track = SGDoxMusicManager.shared.currentTrack else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        SGSimpleSettings.shared.doxProfileTrackId = track.id
        SGSimpleSettings.shared.doxProfileTrackTitle = track.title
        SGSimpleSettings.shared.doxProfileTrackArtist = track.artist
        SGSimpleSettings.shared.doxProfileTrackArtworkUrl = track.artworkUrl
        
        let overlay = UndoOverlayController(presentationData: self.presentationData, content: .actionSucceeded(title: nil, text: "Трек закреплен в профиле", cancel: nil, destructive: false), elevatedLayout: false, action: { _ in return false })
        self.present(overlay, in: .window(.root))
    }
    
    private func downloadPressed() {
        guard let track = SGDoxMusicManager.shared.currentTrack else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        let isDown = SGDoxMusicOfflineManager.shared.isDownloaded(trackId: track.id)
        if isDown {
            SGDoxMusicOfflineManager.shared.deleteTrack(trackId: track.id)
            let overlay = UndoOverlayController(presentationData: self.presentationData, content: .actionSucceeded(title: nil, text: "Трек удален из офлайн-памяти", cancel: nil, destructive: false), elevatedLayout: false, action: { _ in return false })
            self.present(overlay, in: .window(.root))
        } else {
            let hud = OverlayStatusController(style: .dark, type: .loading(cancelled: nil))
            self.present(hud, in: .window(.root))
            SGDoxMusicOfflineManager.shared.downloadTrack(track: track) { [weak self, weak hud] success in
                hud?.dismiss()
                guard let self = self else { return }
                let text = success ? "Трек сохранен для прослушивания офлайн" : "Не удалось скачать аудиофайл"
                let overlay = UndoOverlayController(presentationData: self.presentationData, content: success ? .actionSucceeded(title: nil, text: text, cancel: nil, destructive: false) : .info(title: "Ошибка", text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false })
                self.present(overlay, in: .window(.root))
            }
        }
    }
    
    @objc private func favoritePressed() {
        guard let track = SGDoxMusicManager.shared.currentTrack else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        UIView.animate(withDuration: 0.14, animations: {
            self.favoriteButton.transform = CGAffineTransform(scaleX: 1.35, y: 1.35)
            self.lyricsFavoriteButton.transform = CGAffineTransform(scaleX: 1.35, y: 1.35)
        }) { _ in
            UIView.animate(withDuration: 0.14) {
                self.favoriteButton.transform = .identity
                self.lyricsFavoriteButton.transform = .identity
            }
        }
        SGDoxMusicManager.shared.toggleFavorite(track: track)
        self.updateContent()
    }
    
    @objc private func playPausePressed() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        UIView.animate(withDuration: 0.10, animations: {
            self.playPauseButton.transform = CGAffineTransform(scaleX: 0.90, y: 0.90)
        }) { _ in
            UIView.animate(withDuration: 0.14) {
                self.playPauseButton.transform = .identity
            }
        }
        SGDoxMusicManager.shared.togglePlay()
    }
    
    @objc private func nextPressed() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        UIView.animate(withDuration: 0.10, animations: {
            self.nextButton.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
        }) { _ in
            UIView.animate(withDuration: 0.14) {
                self.nextButton.transform = .identity
            }
        }
        SGDoxMusicManager.shared.next()
    }
    
    @objc private func previousPressed() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        UIView.animate(withDuration: 0.10, animations: {
            self.previousButton.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
        }) { _ in
            UIView.animate(withDuration: 0.14) {
                self.previousButton.transform = .identity
            }
        }
        SGDoxMusicManager.shared.previous()
    }
    
    @objc private func shufflePressed() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        SGDoxMusicManager.shared.toggleShuffle()
        self.updateContent()
        self.reloadQueueData()
    }
    
    @objc private func repeatPressed() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let _ = SGDoxMusicManager.shared.toggleRepeatMode()
        self.updateContent()
    }
    
    @objc private func queueShufflePressed() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        SGDoxMusicManager.shared.shuffleQueue()
        self.reloadQueueData()
    }
    
    @objc private func queueClearPressed() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        SGDoxMusicManager.shared.clearQueue()
        self.reloadQueueData()
    }
    
    @objc private func artistLabelTapped() {
        guard let track = SGDoxMusicManager.shared.currentTrack else { return }
        let artistVc = SGDoxArtistViewController(context: self.context, artistName: track.artist)
        if let topNav = self.context.sharedContext.mainWindow?.viewController as? NavigationController {
            topNav.pushViewController(artistVc)
        }
    }
    
    @objc private func sliderTouchBegan() {
        self.isDraggingSlider = true
        self.progressSlider.setThumbImage(self.generateSliderThumb(size: 13.0), for: .normal)
        UIView.animate(withDuration: 0.15) {
            self.progressSlider.transform = CGAffineTransform(scaleX: 1.0, y: 1.25)
        }
    }
    
    @objc private func sliderValueChanged() {
        self.isDraggingSlider = true
        let duration = SGDoxMusicManager.shared.duration > 0 ? SGDoxMusicManager.shared.duration : 30.0
        let val = self.progressSlider.value
        let target = Double(val) * duration
        let timeStr = self.formatTime(target)
        self.currentTimeLabel.text = timeStr
        self.remainingTimeLabel.text = "-\(self.formatTime(max(0, duration - target)))"
    }
    
    @objc private func sliderTouchEnded() {
        self.isDraggingSlider = false
        self.progressSlider.setThumbImage(self.generateSliderThumb(size: 7.0), for: .normal)
        UIView.animate(withDuration: 0.15) {
            self.progressSlider.transform = .identity
        }
        let duration = SGDoxMusicManager.shared.duration > 0 ? SGDoxMusicManager.shared.duration : 30.0
        let val = self.progressSlider.value
        let target = Double(val) * duration
        SGDoxMusicManager.shared.seek(to: target)
        self.videoPlayer?.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }
    
    // MARK: - Video Playback / Animated Canvas
    private func setupVideoPlayback(urlString: String?) {
        guard let urlString = urlString, let url = URL(string: urlString), SGDoxVideoClipService.shared.isVideoEnabled else {
            self.teardownVideoPlayback()
            return
        }
        
        self.currentVideoClipUrl = urlString
        let item = AVPlayerItem(url: url)
        SGDoxVideoClipService.shared.applyQuality(to: item)
        self.videoItem = item
        
        if let player = self.videoPlayer {
            player.replaceCurrentItem(with: item)
        } else {
            let player = AVPlayer(playerItem: item)
            player.isMuted = true
            player.actionAtItemEnd = .none
            self.videoPlayer = player
            
            let layer = AVPlayerLayer(player: player)
            layer.videoGravity = .resizeAspectFill
            layer.frame = self.videoContainerView.bounds
            self.videoContainerView.layer.insertSublayer(layer, at: 0)
            self.videoPlayerLayer = layer
        }
        
        if let obs = self.videoEndObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        self.videoEndObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            self?.videoPlayer?.seek(to: .zero)
            self?.videoPlayer?.play()
        }
        
        if SGDoxMusicManager.shared.isPlaying {
            self.videoPlayer?.play()
        }
        
        UIView.animate(withDuration: 0.40) {
            self.videoContainerView.alpha = 1.0
            // Seamless animated cover canvas playing full screen
            self.artworkContainerView.alpha = 0.0
            self.artworkAmbientGlowView.alpha = 0.0
        }
    }
    
    private func teardownVideoPlayback(animated: Bool = false) {
        if let obs = self.videoEndObserver {
            NotificationCenter.default.removeObserver(obs)
            self.videoEndObserver = nil
        }
        self.videoPlayer?.pause()
        self.videoPlayer?.replaceCurrentItem(with: nil)
        self.videoPlayer = nil
        self.videoPlayerLayer?.removeFromSuperlayer()
        self.videoPlayerLayer = nil
        self.videoItem = nil
        self.currentVideoClipUrl = nil
        self.videoContainerView.alpha = 0.0
        
        self.artworkContainerView.alpha = 1.0
        self.artworkAmbientGlowView.alpha = 1.0
    }
    
    // MARK: - UITableView DataSource & Delegate
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if tableView == self.lyricsTableView {
            return self.currentLyrics?.lines.count ?? 0
        }
        return self.cachedQueue.count
    }
    
    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if tableView == self.lyricsTableView {
            if let cached = self.lyricsHeightCache[indexPath.row] {
                return cached
            }
            guard let lyrics = self.currentLyrics, indexPath.row < lyrics.lines.count else { return 56.0 }
            let text = lyrics.lines[indexPath.row].text
            let width = max(100.0, self.lyricsTableView.bounds.width - 56.0)
            let rect = (text as NSString).boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: SGDoxLyricsCell.font],
                context: nil
            )
            let h = max(56.0, ceil(rect.height) + 28.0)
            self.lyricsHeightCache[indexPath.row] = h
            return h
        }
        return 60.0
    }
    
    public func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        if tableView == self.lyricsTableView {
            return 56.0
        }
        return 60.0
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if tableView == self.lyricsTableView {
            let cell = tableView.dequeueReusableCell(withIdentifier: "SGDoxLyricsCell", for: indexPath) as! SGDoxLyricsCell
            if let lyrics = self.currentLyrics, indexPath.row < lyrics.lines.count {
                let line = lyrics.lines[indexPath.row]
                let isActive = (indexPath.row == self.activeLyricsIndex)
                let nextTimestamp = (indexPath.row + 1 < lyrics.lines.count) ? lyrics.lines[indexPath.row + 1].timestamp : (line.timestamp + 4.5)
                let duration = max(1.0, nextTimestamp - line.timestamp)
                cell.configure(line: line, isActive: isActive, currentTime: SGDoxMusicManager.shared.currentTime, lineDuration: duration)
            }
            return cell
        }
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "SGDoxPlayerQueueCell", for: indexPath) as! SGDoxPlayerQueueCell
        if indexPath.row < self.cachedQueue.count {
            let track = self.cachedQueue[indexPath.row]
            cell.configure(track: track)
        }
        return cell
    }
    
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if tableView == self.lyricsTableView {
            guard let lyrics = self.currentLyrics, indexPath.row < lyrics.lines.count else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            let targetTime = lyrics.lines[indexPath.row].timestamp
            SGDoxMusicManager.shared.seek(to: targetTime)
            self.videoPlayer?.seek(to: CMTime(seconds: targetTime, preferredTimescale: 600))
        } else if tableView == self.queueTableView {
            guard indexPath.row < self.cachedQueue.count else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            let track = self.cachedQueue[indexPath.row]
            SGDoxMusicManager.shared.play(track: track, queue: self.cachedQueue)
            self.updateContent()
            self.reloadQueueData()
        }
    }
    
    // MARK: - UIScrollView Delegate for Lyrics
    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        if scrollView == self.lyricsTableView {
            self.isUserScrollingLyrics = true
            self.userScrollTimer?.invalidate()
        }
    }
    
    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if scrollView == self.lyricsTableView && !decelerate {
            self.scheduleResumeLyricsAutoScroll()
        }
    }
    
    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        if scrollView == self.lyricsTableView {
            self.scheduleResumeLyricsAutoScroll()
        }
    }
    
    private func scheduleResumeLyricsAutoScroll() {
        self.userScrollTimer?.invalidate()
        self.userScrollTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.isUserScrollingLyrics = false
            if self.activeLyricsIndex >= 0 && self.currentMode == .lyrics {
                let targetIndexPath = IndexPath(row: self.activeLyricsIndex, section: 0)
                self.lyricsTableView.scrollToRow(at: targetIndexPath, at: .middle, animated: true)
            }
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && !seconds.isNaN && seconds >= 0 else { return "0:00" }
        let s = Int(seconds)
        let mins = s / 60
        let secs = s % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - SGDoxLyricsCell (Apple Music Karaoke Progressive Bounce & Glow)
private final class SGDoxLyricsCell: UITableViewCell {
    public static let font = UIFont.systemFont(ofSize: 26, weight: .bold)
    private let lineLabel = UILabel()
    private var words: [(text: String, range: NSRange, weight: Double)] = []
    private var totalWeight: Double = 1.0
    private var currentLine: SGDoxLyricsLine?
    private var isCurrentActive: Bool = false
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        self.backgroundColor = .clear
        self.selectionStyle = .none
        
        self.lineLabel.font = SGDoxLyricsCell.font
        self.lineLabel.numberOfLines = 0
        self.lineLabel.lineBreakMode = .byWordWrapping
        self.lineLabel.textAlignment = .left
        self.lineLabel.textColor = UIColor.white.withAlphaComponent(0.38)
        self.contentView.addSubview(self.lineLabel)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(line: SGDoxLyricsLine, isActive: Bool, currentTime: Double, lineDuration: Double) {
        let wasActive = self.isCurrentActive
        self.currentLine = line
        self.isCurrentActive = isActive
        self.prepareWords(from: line.text)
        
        if isActive {
            if !wasActive {
                self.lineLabel.transform = CGAffineTransform(scaleX: 1.04, y: 1.04)
                UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.65, initialSpringVelocity: 0.8, options: [.allowUserInteraction], animations: {
                    self.lineLabel.transform = .identity
                })
            }
            self.lineLabel.layer.shadowColor = UIColor.white.cgColor
            self.lineLabel.layer.shadowRadius = 8.0
            self.lineLabel.layer.shadowOpacity = 0.50
            self.lineLabel.layer.shadowOffset = .zero
            self.updateProgress(currentTime: currentTime, lineDuration: lineDuration)
        } else {
            self.lineLabel.layer.shadowOpacity = 0.0
            self.lineLabel.transform = .identity
            self.lineLabel.attributedText = nil
            self.lineLabel.text = line.text
            self.lineLabel.textColor = UIColor.white.withAlphaComponent(0.38)
        }
        self.setNeedsLayout()
    }
    
    private func prepareWords(from text: String) {
        self.words.removeAll(keepingCapacity: true)
        let nsText = text as NSString
        var currentWeight: Double = 0.0
        
        let pattern = #"\S+"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                let wordStr = nsText.substring(with: match.range)
                let w = max(1.0, Double(wordStr.count))
                self.words.append((text: wordStr, range: match.range, weight: w))
                currentWeight += w
            }
        }
        self.totalWeight = max(1.0, currentWeight)
    }
    
    func updateProgress(currentTime: Double, lineDuration: Double) {
        guard let line = self.currentLine, self.isCurrentActive else { return }
        
        let text = line.text
        let elapsed = max(0.0, currentTime - line.timestamp)
        let duration = max(0.8, lineDuration)
        let progress = min(1.0, elapsed / duration)
        
        if elapsed <= 0.001 {
            self.lineLabel.attributedText = nil
            self.lineLabel.text = text
            self.lineLabel.textColor = UIColor.white.withAlphaComponent(0.38)
            return
        }
        
        if progress >= 0.999 {
            self.lineLabel.attributedText = nil
            self.lineLabel.text = text
            self.lineLabel.textColor = .white
            return
        }
        
        // Character-level smooth progressive reveal
        let attr = NSMutableAttributedString(string: text, attributes: [
            .font: SGDoxLyricsCell.font,
            .foregroundColor: UIColor.white.withAlphaComponent(0.38)
        ])
        
        var cumulativeWeight: Double = 0.0
        for item in self.words {
            let wordStartFraction = cumulativeWeight / self.totalWeight
            let wordWeightFraction = item.weight / self.totalWeight
            cumulativeWeight += item.weight
            let wordEndFraction = cumulativeWeight / self.totalWeight
            
            if progress >= wordEndFraction {
                attr.addAttribute(.foregroundColor, value: UIColor.white, range: item.range)
            } else if progress > wordStartFraction {
                let intraProgress = (progress - wordStartFraction) / max(0.0001, wordWeightFraction)
                let charCount = item.range.length
                let revealedChars = Int(Double(charCount) * intraProgress)
                
                if revealedChars > 0 {
                    let whiteRange = NSRange(location: item.range.location, length: min(charCount, revealedChars))
                    attr.addAttribute(.foregroundColor, value: UIColor.white, range: whiteRange)
                }
                if revealedChars < charCount {
                    let transitionRange = NSRange(location: item.range.location + revealedChars, length: 1)
                    attr.addAttribute(.foregroundColor, value: UIColor.white.withAlphaComponent(0.72), range: transitionRange)
                }
            }
        }
        
        self.lineLabel.attributedText = attr
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        let hInset: CGFloat = 28.0
        let vInset: CGFloat = 14.0
        let w = max(0, self.contentView.bounds.width - hInset * 2.0)
        let textH = self.lineLabel.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude)).height
        self.lineLabel.frame = CGRect(x: hInset, y: vInset, width: w, height: ceil(textH))
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        self.lineLabel.attributedText = nil
        self.lineLabel.text = nil
        self.lineLabel.textColor = UIColor.white.withAlphaComponent(0.38)
        self.lineLabel.layer.shadowOpacity = 0.0
        self.lineLabel.transform = .identity
        self.currentLine = nil
        self.isCurrentActive = false
    }
}

// MARK: - In-Player Queue Cell
private final class SGDoxPlayerQueueCell: UITableViewCell {
    private let artworkImageView = UIImageView()
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    private let dolbyBadge = UILabel()
    private let losslessBadge = UILabel()
    private let durationLabel = UILabel()
    private var currentTrackId: String?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        self.backgroundColor = .clear
        self.selectionStyle = .none
        
        self.artworkImageView.contentMode = .scaleAspectFill
        self.artworkImageView.clipsToBounds = true
        self.artworkImageView.layer.cornerRadius = 8
        self.artworkImageView.backgroundColor = UIColor(white: 0.15, alpha: 1.0)
        self.contentView.addSubview(self.artworkImageView)
        
        self.titleLabel.textColor = .white
        self.titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        self.titleLabel.lineBreakMode = .byTruncatingTail
        self.contentView.addSubview(self.titleLabel)
        
        self.artistLabel.textColor = UIColor(white: 1.0, alpha: 0.65)
        self.artistLabel.font = UIFont.systemFont(ofSize: 13, weight: .regular)
        self.artistLabel.lineBreakMode = .byTruncatingTail
        self.contentView.addSubview(self.artistLabel)
        
        self.dolbyBadge.text = "ATMOS"
        self.dolbyBadge.font = UIFont.systemFont(ofSize: 7.5, weight: .bold)
        self.dolbyBadge.textColor = UIColor(white: 1.0, alpha: 0.85)
        self.dolbyBadge.backgroundColor = UIColor(white: 1.0, alpha: 0.14)
        self.dolbyBadge.layer.cornerRadius = 2.5
        self.dolbyBadge.clipsToBounds = true
        self.dolbyBadge.textAlignment = .center
        self.dolbyBadge.isHidden = true
        self.contentView.addSubview(self.dolbyBadge)
        
        self.losslessBadge.text = "LOSSLESS"
        self.losslessBadge.font = UIFont.systemFont(ofSize: 7.5, weight: .bold)
        self.losslessBadge.textColor = UIColor(white: 1.0, alpha: 0.85)
        self.losslessBadge.backgroundColor = UIColor(white: 1.0, alpha: 0.14)
        self.losslessBadge.layer.cornerRadius = 2.5
        self.losslessBadge.clipsToBounds = true
        self.losslessBadge.textAlignment = .center
        self.losslessBadge.isHidden = true
        self.contentView.addSubview(self.losslessBadge)
        
        self.durationLabel.textColor = UIColor(white: 1.0, alpha: 0.45)
        self.durationLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .regular)
        self.durationLabel.textAlignment = .right
        self.contentView.addSubview(self.durationLabel)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(track: SGDoxMusicTrack) {
        self.currentTrackId = track.id
        self.titleLabel.text = track.title
        self.artistLabel.text = track.artist
        
        self.dolbyBadge.isHidden = !track.isDolbyAtmos
        self.losslessBadge.isHidden = !track.isLossless
        
        let d = Int(track.duration)
        self.durationLabel.text = d > 0 ? String(format: "%d:%02d", d / 60, d % 60) : ""
        
        self.artworkImageView.image = SGDoxImageLoader.shared.placeholderArtwork()
        SGDoxImageLoader.shared.loadArtwork(for: track, targetSize: CGSize(width: 88, height: 88)) { [weak self] image in
            if self?.currentTrackId == track.id, let img = image {
                self?.artworkImageView.image = img
            }
        }
        self.setNeedsLayout()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        let b = self.contentView.bounds
        let artSide: CGFloat = 44.0
        self.artworkImageView.frame = CGRect(x: 20, y: (b.height - artSide) * 0.5, width: artSide, height: artSide)
        
        let rightMargin: CGFloat = 20.0
        let durW: CGFloat = 46.0
        self.durationLabel.frame = CGRect(x: b.width - rightMargin - durW, y: (b.height - 18) * 0.5, width: durW, height: 18)
        
        let textX = self.artworkImageView.frame.maxX + 12.0
        let textW = max(0, self.durationLabel.frame.minX - textX - 8.0)
        self.titleLabel.frame = CGRect(x: textX, y: 11, width: textW, height: 20)
        
        var badgesW: CGFloat = 0.0
        if !self.dolbyBadge.isHidden { badgesW += 38.0 }
        if !self.losslessBadge.isHidden { badgesW += 48.0 }
        
        let artistSize = self.artistLabel.sizeThatFits(CGSize(width: textW, height: 18))
        let availableArtistW = max(30.0, textW - badgesW)
        let artistW = min(artistSize.width, availableArtistW)
        self.artistLabel.frame = CGRect(x: textX, y: 31, width: artistW, height: 18)
        
        var badgeX = textX + artistW + 6.0
        let badgeY: CGFloat = 34.0
        if !self.dolbyBadge.isHidden {
            let bW: CGFloat = 34.0
            self.dolbyBadge.frame = CGRect(x: badgeX, y: badgeY, width: bW, height: 12.5)
            badgeX += bW + 4.0
        }
        if !self.losslessBadge.isHidden {
            let bW: CGFloat = 44.0
            self.losslessBadge.frame = CGRect(x: badgeX, y: badgeY, width: bW, height: 12.5)
        }
    }
}
