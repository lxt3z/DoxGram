import Foundation
import UIKit
import AVFoundation
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
    
    // Video Clip Background
    private let videoContainerView = UIView()
    private var videoPlayer: AVPlayer?
    private var videoPlayerLayer: AVPlayerLayer?
    private var videoItem: AVPlayerItem?
    private var currentVideoClipUrl: String?
    private var videoEndObserver: Any?
    private let videoDimOverlay = UIView()
    
    // Top Bar
    private let grabberView = UIView()
    private let dismissButton = UIButton(type: .system)
    
    // Navigation Modes
    public enum PlayerMode: Int {
        case nowPlaying = 0
        case lyrics = 1
        case queue = 2
    }
    private var currentMode: PlayerMode = .nowPlaying
    
    // Containers
    private let nowPlayingContainerView = UIView()
    private let lyricsContainerView = UIView()
    private let queueContainerView = UIView()
    
    // MARK: - Now Playing Pane UI
    private let artworkAmbientGlowView = UIView()
    private let artworkGlowGradientLayer = CAGradientLayer()
    private let artworkContainerView = UIView()
    private let artworkImageView = UIImageView()
    
    private let infoContainerView = UIView()
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    private let favoriteButton = UIButton(type: .system)
    private let moreButton = UIButton(type: .system)
    
    // Format Badges: Lossless & Dolby Atmos (Centered below scrubber)
    private let formatBadgeButton = UIButton(type: .system)
    
    // Scrubber & Times
    private let progressSlider = UISlider()
    private let currentTimeLabel = UILabel()
    private let remainingTimeLabel = UILabel()
    
    // Transport Controls
    private let controlsContainerView = UIView()
    private let shuffleButton = UIButton(type: .system)
    private let previousButton = UIButton(type: .system)
    private let playPauseButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let repeatButton = UIButton(type: .system)
    
    // Volume Control Row
    private let volumeContainerView = UIView()
    private let volumeMinIcon = UIImageView()
    private let volumeSlider = UISlider()
    private let volumeMaxIcon = UIImageView()
    
    // Bottom Bar (Lyrics | AirPlay | Queue)
    private let bottomBarContainer = UIView()
    private let bottomLyricsButton = UIButton(type: .system)
    private let bottomAirplayButton = UIButton(type: .system)
    private let bottomQueueButton = UIButton(type: .system)
    
    // MARK: - Lyrics Pane UI (Apple Music Authentic)
    private let lyricsHeaderView = UIView()
    private let lyricsHeaderArtwork = UIImageView()
    private let lyricsHeaderInfoView = UIView()
    private let lyricsTrackTitle = UILabel()
    private let lyricsTrackArtist = UILabel()
    private let lyricsFavoriteButton = UIButton(type: .system)
    private let lyricsMoreButton = UIButton(type: .system)
    
    private let lyricsTableView = UITableView(frame: .zero, style: .plain)
    private let lyricsPlainTextView = UITextView()
    private let lyricsLoadingIndicator = UIActivityIndicatorView(style: .medium)
    private let lyricsStatusLabel = UILabel()
    private let lyricsSingButton = UIButton(type: .system) // Apple Music Sing (Mic)
    
    // Lyrics Bottom Controls (Mirror of Apple Music Lyrics Player)
    private let lyricsBottomContainer = UIView()
    private let lyricsProgressSlider = UISlider()
    private let lyricsCurrentTimeLabel = UILabel()
    private let lyricsRemainingTimeLabel = UILabel()
    private let lyricsFormatBadge = UIButton(type: .system)
    
    private let lyricsTransportContainer = UIView()
    private let lyricsPrevButton = UIButton(type: .system)
    private let lyricsPlayPauseButton = UIButton(type: .system)
    private let lyricsNextButton = UIButton(type: .system)
    
    private let lyricsVolumeContainer = UIView()
    private let lyricsVolumeMinIcon = UIImageView()
    private let lyricsVolumeSlider = UISlider()
    private let lyricsVolumeMaxIcon = UIImageView()
    
    private let lyricsBottomBar = UIView()
    private let lyricsBottomLyricsBtn = UIButton(type: .system)
    private let lyricsBottomAirplayBtn = UIButton(type: .system)
    private let lyricsBottomQueueBtn = UIButton(type: .system)
    
    private var currentLyrics: SGDoxLyrics?
    private var activeLyricsIndex: Int = -1
    private var isUserScrollingLyrics = false
    private var userScrollTimer: Foundation.Timer?
    private var lyricsHeightCache: [Int: CGFloat] = [:]
    
    // MARK: - Queue Pane UI
    private let queueHeaderView = UIView()
    private let queueTitleLabel = UILabel()
    private let queueCountLabel = UILabel()
    private let queueShuffleButton = UIButton(type: .system)
    private let queueClearButton = UIButton(type: .system)
    private let queueTableView = UITableView(frame: .zero, style: .plain)
    
    private let queueBottomBar = UIView()
    private let queueBottomLyricsBtn = UIButton(type: .system)
    private let queueBottomAirplayBtn = UIButton(type: .system)
    private let queueBottomQueueBtn = UIButton(type: .system)
    
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
    private var hasAnimatedIn = false
    
    // MARK: - Static Presentation Helper
    public static func present(context: AccountContext, onDismissBegin: (() -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        let player = SGDoxMusicPlayerController(context: context)
        player.onDismissBegin = onDismissBegin
        player.onDismiss = onDismiss
        if let mainWindow = context.sharedContext.mainWindow {
            mainWindow.present(player, on: .root)
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
        self.detachListeners()
    }
    
    public override func loadDisplayNode() {
        super.loadDisplayNode()
        self.displayNode.backgroundColor = .clear
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1.0)
        
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
        
        // Initial offscreen state for smooth spring presentation
        let screenHeight = UIScreen.main.bounds.height
        let offscreenOffset = screenHeight > 0 ? screenHeight : 900.0
        self.view.transform = CGAffineTransform(translationX: 0, y: offscreenOffset)
        
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(self.handlePanGesture(_:)))
        panGesture.delegate = self
        self.view.addGestureRecognizer(panGesture)
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.attachListeners()
        self.updateContent()
        self.reloadQueueData()
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !self.hasAnimatedIn {
            self.hasAnimatedIn = true
            UIView.animate(withDuration: 0.38, delay: 0, usingSpringWithDamping: 0.86, initialSpringVelocity: 0.4, options: [.curveEaseOut, .allowUserInteraction], animations: {
                self.view.transform = .identity
            }, completion: nil)
        }
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
            
            switch self.currentMode {
            case .nowPlaying:
                self.progressSlider.value = progress
                if currentSecond != self.lastDisplayedSecond {
                    self.lastDisplayedSecond = currentSecond
                    self.currentTimeLabel.text = timeStr
                    self.remainingTimeLabel.text = remStr
                }
            case .lyrics:
                self.lyricsProgressSlider.value = progress
                if currentSecond != self.lastDisplayedSecond {
                    self.lastDisplayedSecond = currentSecond
                    self.lyricsCurrentTimeLabel.text = timeStr
                    self.lyricsRemainingTimeLabel.text = remStr
                }
                self.syncLyricsPosition(currentTime: current)
            case .queue:
                break
            }
        }
    }
    
    private func detachListeners() {
        self.userScrollTimer?.invalidate()
        self.userScrollTimer = nil
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
    
    // MARK: - Gesture & Dismissal
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var current = touch.view
        while let v = current {
            if v is UIControl || v is UITableView || v is UITableViewCell {
                return false
            }
            current = v.superview
        }
        return true
    }
    
    @objc private func handlePanGesture(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: self.view)
        let velocity = recognizer.velocity(in: self.view)
        
        switch recognizer.state {
        case .changed:
            if translation.y > 0 {
                self.view.transform = CGAffineTransform(translationX: 0, y: translation.y)
                let dismissFraction = min(1.0, max(0.0, translation.y / (self.view.bounds.height * 0.7)))
                self.darkDimOverlay.alpha = 1.0 - dismissFraction * 0.6
                self.backgroundBlurView.alpha = 1.0 - dismissFraction * 0.3
            } else {
                self.view.transform = .identity
            }
        case .ended, .cancelled:
            if (translation.y > 120 || velocity.y > 600) && !self.isDismissing {
                self.isDismissing = true
                self.detachListeners()
                self.triggerDismissBeginIfNeeded()
                let remainingDistance = max(0, self.view.bounds.height - translation.y)
                let velocityY = max(800.0, velocity.y)
                let duration = max(0.18, min(0.28, Double(remainingDistance / velocityY)))
                
                UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseOut], animations: {
                    self.view.transform = CGAffineTransform(translationX: 0, y: self.view.bounds.height)
                    self.darkDimOverlay.alpha = 0.0
                    self.backgroundBlurView.alpha = 0.0
                }) { [weak self] _ in
                    guard let self = self else { return }
                    self.finishDismiss(completion: nil)
                }
            } else if !self.isDismissing {
                UIView.animate(withDuration: 0.28, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0.5, options: [.allowUserInteraction], animations: {
                    self.view.transform = .identity
                    self.darkDimOverlay.alpha = 1.0
                    self.backgroundBlurView.alpha = 1.0
                })
            }
        default:
            break
        }
    }
    
    @objc private func dismissPressed() {
        self.dismiss(animated: true)
    }
    
    public override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        guard !self.isDismissing else { return }
        self.isDismissing = true
        self.detachListeners()
        self.triggerDismissBeginIfNeeded()
        
        if flag {
            UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseIn], animations: {
                self.view.transform = CGAffineTransform(translationX: 0, y: self.view.bounds.height)
                self.darkDimOverlay.alpha = 0.0
                self.backgroundBlurView.alpha = 0.0
            }) { [weak self] _ in
                guard let self = self else { return }
                self.finishDismiss(completion: completion)
            }
        } else {
            self.finishDismiss(completion: completion)
        }
    }
    
    private func finishDismiss(completion: (() -> Void)? = nil) {
        self.onDismiss?()
        if let navigationController = self.navigationController as? NavigationController {
            navigationController.filterController(self, animated: false)
            completion?()
        } else if let presenting = self.presentingViewController {
            presenting.dismiss(animated: false, completion: completion)
        } else {
            super.dismiss(animated: false, completion: completion)
        }
    }
    
    // MARK: - View Setup
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
        
        // Video layer
        self.videoContainerView.clipsToBounds = true
        self.videoContainerView.backgroundColor = .clear
        self.videoContainerView.alpha = 0.0
        self.view.insertSubview(self.videoContainerView, aboveSubview: self.darkDimOverlay)
        self.videoDimOverlay.backgroundColor = UIColor(white: 0.0, alpha: 0.35)
        self.videoContainerView.addSubview(self.videoDimOverlay)
        
        // 2. Top Drag Grabber (Apple Music Capsule)
        self.grabberView.backgroundColor = UIColor(white: 1.0, alpha: 0.35)
        self.grabberView.layer.cornerRadius = 2.5
        self.grabberView.isUserInteractionEnabled = true
        self.grabberView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.dismissPressed)))
        self.view.addSubview(self.grabberView)
        
        // 3. Content Panes
        self.view.addSubview(self.nowPlayingContainerView)
        self.view.addSubview(self.lyricsContainerView)
        self.view.addSubview(self.queueContainerView)
        
        self.lyricsContainerView.alpha = 0.0
        self.lyricsContainerView.isHidden = true
        self.queueContainerView.alpha = 0.0
        self.queueContainerView.isHidden = true
        
        self.setupNowPlayingPane()
        self.setupLyricsPane()
        self.setupQueuePane()
    }
    
    // MARK: - Setup Now Playing Pane (Artwork Mode)
    private func setupNowPlayingPane() {
        // Soft Glow behind Artwork
        self.artworkAmbientGlowView.clipsToBounds = false
        self.artworkGlowGradientLayer.type = .radial
        self.artworkGlowGradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        self.artworkGlowGradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        self.artworkGlowGradientLayer.locations = [0.0, 0.45, 1.0]
        self.artworkAmbientGlowView.layer.addSublayer(self.artworkGlowGradientLayer)
        self.nowPlayingContainerView.addSubview(self.artworkAmbientGlowView)

        // Artwork (Tapping flips to Lyrics)
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
        
        // Star Favorite Button (Apple Music style)
        let starConfig = UIImage.SymbolConfiguration(pointSize: 21, weight: .medium)
        self.favoriteButton.setImage(UIImage(systemName: "star", withConfiguration: starConfig), for: .normal)
        self.favoriteButton.tintColor = .white
        self.favoriteButton.addTarget(self, action: #selector(self.favoritePressed), for: .touchUpInside)
        self.infoContainerView.addSubview(self.favoriteButton)
        
        // More Button (Apple Music style)
        let moreConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        self.moreButton.setImage(UIImage(systemName: "ellipsis", withConfiguration: moreConfig), for: .normal)
        self.moreButton.tintColor = .white
        self.moreButton.addTarget(self, action: #selector(self.morePressed), for: .touchUpInside)
        self.infoContainerView.addSubview(self.moreButton)
        
        // Scrubber
        self.progressSlider.minimumValue = 0.0
        self.progressSlider.maximumValue = 1.0
        self.progressSlider.minimumTrackTintColor = .white
        self.progressSlider.maximumTrackTintColor = UIColor(white: 1.0, alpha: 0.20)
        self.progressSlider.setThumbImage(self.generateSliderThumb(), for: .normal)
        self.progressSlider.addTarget(self, action: #selector(self.sliderValueChanged), for: .valueChanged)
        self.progressSlider.addTarget(self, action: #selector(self.sliderTouchEnded), for: [.touchUpInside, .touchUpOutside])
        self.nowPlayingContainerView.addSubview(self.progressSlider)
        
        self.currentTimeLabel.textColor = UIColor(white: 1.0, alpha: 0.55)
        self.currentTimeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12.0, weight: .regular)
        self.currentTimeLabel.text = "0:00"
        self.nowPlayingContainerView.addSubview(self.currentTimeLabel)
        
        self.remainingTimeLabel.textColor = UIColor(white: 1.0, alpha: 0.55)
        self.remainingTimeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12.0, weight: .regular)
        self.remainingTimeLabel.text = "-0:00"
        self.remainingTimeLabel.textAlignment = .right
        self.nowPlayingContainerView.addSubview(self.remainingTimeLabel)
        
        // Format Badge Pill (Lossless / Dolby Atmos)
        self.setupFormatBadge(self.formatBadgeButton)
        self.nowPlayingContainerView.addSubview(self.formatBadgeButton)
        
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
        
        self.nowPlayingContainerView.addSubview(self.controlsContainerView)
        
        // Volume Row
        self.setupVolumeRow(container: self.volumeContainerView, minIcon: self.volumeMinIcon, slider: self.volumeSlider, maxIcon: self.volumeMaxIcon)
        self.nowPlayingContainerView.addSubview(self.volumeContainerView)
        
        // Bottom Bar (Lyrics | AirPlay | Queue)
        self.setupBottomBar(container: self.bottomBarContainer, lyricsBtn: self.bottomLyricsButton, airplayBtn: self.bottomAirplayButton, queueBtn: self.bottomQueueButton, activeMode: .nowPlaying)
        self.nowPlayingContainerView.addSubview(self.bottomBarContainer)
    }
    
    // MARK: - Setup Lyrics Pane (Apple Music Authentic Lyrics)
    private func setupLyricsPane() {
        // 1. Top Header: Mini Artwork + Title + Artist + Star + More
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
        
        // 2. Lyrics Table View
        self.lyricsTableView.backgroundColor = .clear
        self.lyricsTableView.separatorStyle = .none
        self.lyricsTableView.dataSource = self
        self.lyricsTableView.delegate = self
        self.lyricsTableView.showsVerticalScrollIndicator = false
        self.lyricsTableView.register(SGDoxLyricsCell.self, forCellReuseIdentifier: "SGDoxLyricsCell")
        self.lyricsContainerView.addSubview(self.lyricsTableView)
        
        // Plain text fallback
        self.lyricsPlainTextView.backgroundColor = .clear
        self.lyricsPlainTextView.textColor = UIColor.white.withAlphaComponent(0.9)
        self.lyricsPlainTextView.font = UIFont.systemFont(ofSize: 22, weight: .semibold)
        self.lyricsPlainTextView.isEditable = false
        self.lyricsPlainTextView.isSelectable = false
        self.lyricsPlainTextView.textAlignment = .left
        self.lyricsPlainTextView.showsVerticalScrollIndicator = false
        self.lyricsPlainTextView.isHidden = true
        self.lyricsContainerView.addSubview(self.lyricsPlainTextView)
        
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
        
        // 3. Lyrics Bottom Controls (Full Apple Music Layout)
        self.lyricsContainerView.addSubview(self.lyricsBottomContainer)
        
        self.lyricsProgressSlider.minimumValue = 0.0
        self.lyricsProgressSlider.maximumValue = 1.0
        self.lyricsProgressSlider.minimumTrackTintColor = .white
        self.lyricsProgressSlider.maximumTrackTintColor = UIColor(white: 1.0, alpha: 0.20)
        self.lyricsProgressSlider.setThumbImage(self.generateSliderThumb(), for: .normal)
        self.lyricsProgressSlider.addTarget(self, action: #selector(self.sliderValueChanged), for: .valueChanged)
        self.lyricsProgressSlider.addTarget(self, action: #selector(self.sliderTouchEnded), for: [.touchUpInside, .touchUpOutside])
        self.lyricsBottomContainer.addSubview(self.lyricsProgressSlider)
        
        self.lyricsCurrentTimeLabel.textColor = UIColor(white: 1.0, alpha: 0.55)
        self.lyricsCurrentTimeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12.0, weight: .regular)
        self.lyricsCurrentTimeLabel.text = "0:00"
        self.lyricsBottomContainer.addSubview(self.lyricsCurrentTimeLabel)
        
        self.lyricsRemainingTimeLabel.textColor = UIColor(white: 1.0, alpha: 0.55)
        self.lyricsRemainingTimeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12.0, weight: .regular)
        self.lyricsRemainingTimeLabel.text = "-0:00"
        self.lyricsRemainingTimeLabel.textAlignment = .right
        self.lyricsBottomContainer.addSubview(self.lyricsRemainingTimeLabel)
        
        self.setupFormatBadge(self.lyricsFormatBadge)
        self.lyricsBottomContainer.addSubview(self.lyricsFormatBadge)
        
        // Transport Controls
        let skipConfig = UIImage.SymbolConfiguration(pointSize: 28, weight: .bold)
        self.lyricsPrevButton.setImage(UIImage(systemName: "backward.fill", withConfiguration: skipConfig), for: .normal)
        self.lyricsPrevButton.tintColor = .white
        self.lyricsPrevButton.addTarget(self, action: #selector(self.previousPressed), for: .touchUpInside)
        self.lyricsTransportContainer.addSubview(self.lyricsPrevButton)
        
        let playConfig = UIImage.SymbolConfiguration(pointSize: 42, weight: .bold)
        self.lyricsPlayPauseButton.setImage(UIImage(systemName: "play.fill", withConfiguration: playConfig), for: .normal)
        self.lyricsPlayPauseButton.tintColor = .white
        self.lyricsPlayPauseButton.addTarget(self, action: #selector(self.playPausePressed), for: .touchUpInside)
        self.lyricsTransportContainer.addSubview(self.lyricsPlayPauseButton)
        
        self.lyricsNextButton.setImage(UIImage(systemName: "forward.fill", withConfiguration: skipConfig), for: .normal)
        self.lyricsNextButton.tintColor = .white
        self.lyricsNextButton.addTarget(self, action: #selector(self.nextPressed), for: .touchUpInside)
        self.lyricsTransportContainer.addSubview(self.lyricsNextButton)
        
        self.lyricsBottomContainer.addSubview(self.lyricsTransportContainer)
        
        // Volume Row
        self.setupVolumeRow(container: self.lyricsVolumeContainer, minIcon: self.lyricsVolumeMinIcon, slider: self.lyricsVolumeSlider, maxIcon: self.lyricsVolumeMaxIcon)
        self.lyricsBottomContainer.addSubview(self.lyricsVolumeContainer)
        
        // Bottom Bar (Lyrics Active | AirPlay | Queue)
        self.setupBottomBar(container: self.lyricsBottomBar, lyricsBtn: self.lyricsBottomLyricsBtn, airplayBtn: self.lyricsBottomAirplayBtn, queueBtn: self.lyricsBottomQueueBtn, activeMode: .lyrics)
        self.lyricsBottomContainer.addSubview(self.lyricsBottomBar)
    }
    
    // MARK: - Setup Queue Pane (Up Next Mode)
    private func setupQueuePane() {
        self.queueTitleLabel.text = "Далее"
        self.queueTitleLabel.textColor = .white
        self.queueTitleLabel.font = UIFont.systemFont(ofSize: 22, weight: .bold)
        self.queueHeaderView.addSubview(self.queueTitleLabel)
        
        self.queueCountLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        self.queueCountLabel.font = UIFont.systemFont(ofSize: 12.0, weight: .semibold)
        self.queueCountLabel.textAlignment = .center
        self.queueCountLabel.backgroundColor = UIColor(white: 1.0, alpha: 0.12)
        self.queueCountLabel.layer.cornerRadius = 11
        self.queueCountLabel.layer.cornerCurve = .continuous
        self.queueCountLabel.clipsToBounds = true
        self.queueHeaderView.addSubview(self.queueCountLabel)
        
        let shuffleConfig = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        self.queueShuffleButton.setImage(UIImage(systemName: "shuffle", withConfiguration: shuffleConfig), for: .normal)
        self.queueShuffleButton.setTitle(" Перемешать", for: .normal)
        self.queueShuffleButton.setTitleColor(.white, for: .normal)
        self.queueShuffleButton.titleLabel?.font = UIFont.systemFont(ofSize: 13.0, weight: .semibold)
        self.queueShuffleButton.backgroundColor = UIColor(white: 1.0, alpha: 0.14)
        self.queueShuffleButton.layer.cornerRadius = 15
        self.queueShuffleButton.layer.cornerCurve = .continuous
        self.queueShuffleButton.layer.borderWidth = 0.5
        self.queueShuffleButton.layer.borderColor = UIColor(white: 1.0, alpha: 0.18).cgColor
        self.queueShuffleButton.tintColor = .white
        self.queueShuffleButton.clipsToBounds = true
        self.queueShuffleButton.addTarget(self, action: #selector(self.queueShufflePressed), for: .touchUpInside)
        self.queueHeaderView.addSubview(self.queueShuffleButton)
        
        let clearConfig = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        self.queueClearButton.setImage(UIImage(systemName: "trash", withConfiguration: clearConfig), for: .normal)
        self.queueClearButton.setTitle(" Очистить", for: .normal)
        self.queueClearButton.setTitleColor(UIColor(red: 1.0, green: 0.35, blue: 0.40, alpha: 1.0), for: .normal)
        self.queueClearButton.titleLabel?.font = UIFont.systemFont(ofSize: 13.0, weight: .semibold)
        self.queueClearButton.backgroundColor = UIColor(red: 1.0, green: 0.35, blue: 0.40, alpha: 0.12)
        self.queueClearButton.layer.cornerRadius = 15
        self.queueClearButton.layer.cornerCurve = .continuous
        self.queueClearButton.layer.borderWidth = 0.5
        self.queueClearButton.layer.borderColor = UIColor(red: 1.0, green: 0.35, blue: 0.40, alpha: 0.25).cgColor
        self.queueClearButton.tintColor = UIColor(red: 1.0, green: 0.35, blue: 0.40, alpha: 1.0)
        self.queueClearButton.clipsToBounds = true
        self.queueClearButton.addTarget(self, action: #selector(self.queueClearPressed), for: .touchUpInside)
        self.queueHeaderView.addSubview(self.queueClearButton)
        
        self.queueContainerView.addSubview(self.queueHeaderView)
        
        // Table View
        self.queueTableView.backgroundColor = .clear
        self.queueTableView.separatorStyle = .none
        self.queueTableView.dataSource = self
        self.queueTableView.delegate = self
        self.queueTableView.register(SGDoxPlayerQueueCell.self, forCellReuseIdentifier: "SGDoxPlayerQueueCell")
        self.queueContainerView.addSubview(self.queueTableView)
        
        // Bottom Bar (Lyrics | AirPlay | Queue Active)
        self.setupBottomBar(container: self.queueBottomBar, lyricsBtn: self.queueBottomLyricsBtn, airplayBtn: self.queueBottomAirplayBtn, queueBtn: self.queueBottomQueueBtn, activeMode: .queue)
        self.queueContainerView.addSubview(self.queueBottomBar)
    }
    
    // MARK: - UI Helpers
    private func setupFormatBadge(_ button: UIButton) {
        let waveConfig = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        button.setImage(UIImage(systemName: "waveform.path", withConfiguration: waveConfig), for: .normal)
        button.setTitle(" Lossless", for: .normal)
        button.setTitleColor(UIColor(white: 1.0, alpha: 0.85), for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 11, weight: .bold)
        button.tintColor = UIColor(white: 1.0, alpha: 0.85)
        button.backgroundColor = UIColor(white: 1.0, alpha: 0.12)
        button.layer.cornerRadius = 10
        button.layer.cornerCurve = .continuous
        button.clipsToBounds = true
        button.contentEdgeInsets = UIEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)
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
        slider.value = SGDoxMusicManager.shared.volume
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
    
    private func setupBottomBar(container: UIView, lyricsBtn: UIButton, airplayBtn: UIButton, queueBtn: UIButton, activeMode: PlayerMode) {
        let btnConfig = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        
        // Lyrics Button
        lyricsBtn.setImage(UIImage(systemName: activeMode == .lyrics ? "quote.bubble.fill" : "quote.bubble", withConfiguration: btnConfig), for: .normal)
        lyricsBtn.tintColor = activeMode == .lyrics ? .white : UIColor(white: 1.0, alpha: 0.65)
        if activeMode == .lyrics {
            lyricsBtn.backgroundColor = UIColor(white: 1.0, alpha: 0.22)
            lyricsBtn.layer.cornerRadius = 18.0
            lyricsBtn.layer.cornerCurve = .continuous
        } else {
            lyricsBtn.backgroundColor = .clear
        }
        lyricsBtn.addTarget(self, action: #selector(self.lyricsBottomPressed), for: .touchUpInside)
        container.addSubview(lyricsBtn)
        
        // AirPlay Button
        airplayBtn.setImage(UIImage(systemName: "airplayaudio", withConfiguration: btnConfig), for: .normal)
        airplayBtn.tintColor = UIColor(white: 1.0, alpha: 0.65)
        airplayBtn.addTarget(self, action: #selector(self.airplayPressed), for: .touchUpInside)
        container.addSubview(airplayBtn)
        
        // Queue Button
        queueBtn.setImage(UIImage(systemName: "list.bullet", withConfiguration: btnConfig), for: .normal)
        queueBtn.tintColor = activeMode == .queue ? .white : UIColor(white: 1.0, alpha: 0.65)
        if activeMode == .queue {
            queueBtn.backgroundColor = UIColor(white: 1.0, alpha: 0.22)
            queueBtn.layer.cornerRadius = 18.0
            queueBtn.layer.cornerCurve = .continuous
        } else {
            queueBtn.backgroundColor = .clear
        }
        queueBtn.addTarget(self, action: #selector(self.queueBottomPressed), for: .touchUpInside)
        container.addSubview(queueBtn)
    }
    
    private func generateSliderThumb() -> UIImage {
        let size = CGSize(width: 8, height: 8)
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        let ctx = UIGraphicsGetCurrentContext()
        ctx?.setFillColor(UIColor.white.cgColor)
        ctx?.fillEllipse(in: CGRect(origin: .zero, size: size))
        let img = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        return img
    }
    
    private func generateVolumeThumb() -> UIImage {
        let size = CGSize(width: 14, height: 14)
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
        
        // Top Grabber Handle (Centered)
        let topY = max(safeArea.top + 8.0, 14.0)
        self.grabberView.frame = CGRect(x: (bounds.width - 36.0) * 0.5, y: topY, width: 36.0, height: 5.0)
        
        let contentY = topY + 12.0
        let bottomSafe = max(safeArea.bottom, 18.0)
        let contentH = bounds.height - contentY - bottomSafe
        let contentFrame = CGRect(x: 0, y: contentY, width: bounds.width, height: contentH)
        
        self.nowPlayingContainerView.frame = contentFrame
        self.lyricsContainerView.frame = contentFrame
        self.queueContainerView.frame = contentFrame
        
        self.layoutNowPlayingPane(bounds: self.nowPlayingContainerView.bounds)
        self.layoutLyricsPane(bounds: self.lyricsContainerView.bounds)
        self.layoutQueuePane(bounds: self.queueContainerView.bounds)
    }
    
    private func layoutNowPlayingPane(bounds: CGRect) {
        guard bounds.width > 0 && bounds.height > 0 else { return }
        
        // Bottom Bar (fixed at bottom)
        let barH: CGFloat = 44.0
        let barY = bounds.height - barH
        self.bottomBarContainer.frame = CGRect(x: 28.0, y: barY, width: bounds.width - 56.0, height: barH)
        let barW = self.bottomBarContainer.bounds.width
        let itemW: CGFloat = 44.0
        self.bottomLyricsButton.frame = CGRect(x: 0, y: 0, width: itemW, height: itemW)
        self.bottomAirplayButton.frame = CGRect(x: (barW - itemW) * 0.5, y: 0, width: itemW, height: itemW)
        self.bottomQueueButton.frame = CGRect(x: barW - itemW, y: 0, width: itemW, height: itemW)
        
        // Volume Row
        let volH: CGFloat = 28.0
        let volY = barY - volH - 14.0
        self.volumeContainerView.frame = CGRect(x: 32.0, y: volY, width: bounds.width - 64.0, height: volH)
        let volW = self.volumeContainerView.bounds.width
        self.volumeMinIcon.frame = CGRect(x: 0, y: 7, width: 16, height: 14)
        self.volumeMaxIcon.frame = CGRect(x: volW - 18, y: 6, width: 18, height: 16)
        self.volumeSlider.frame = CGRect(x: 26, y: 0, width: volW - 52, height: volH)
        
        // Transport Controls Row
        let controlsH: CGFloat = 64.0
        let controlsY = volY - controlsH - 12.0
        self.controlsContainerView.frame = CGRect(x: 24.0, y: controlsY, width: bounds.width - 48.0, height: controlsH)
        let cW = self.controlsContainerView.bounds.width
        let midX = cW * 0.5
        
        let playBtnSize: CGFloat = 58.0
        self.playPauseButton.frame = CGRect(x: midX - playBtnSize * 0.5, y: (controlsH - playBtnSize) * 0.5, width: playBtnSize, height: playBtnSize)
        
        let skipSize: CGFloat = 46.0
        let skipOffset: CGFloat = 68.0
        self.previousButton.frame = CGRect(x: midX - skipOffset - skipSize * 0.5, y: (controlsH - skipSize) * 0.5, width: skipSize, height: skipSize)
        self.nextButton.frame = CGRect(x: midX + skipOffset - skipSize * 0.5, y: (controlsH - skipSize) * 0.5, width: skipSize, height: skipSize)
        
        let sideSize: CGFloat = 36.0
        self.shuffleButton.frame = CGRect(x: 4.0, y: (controlsH - sideSize) * 0.5, width: sideSize, height: sideSize)
        self.repeatButton.frame = CGRect(x: cW - sideSize - 4.0, y: (controlsH - sideSize) * 0.5, width: sideSize, height: sideSize)
        
        // Format Badge (Lossless / Atmos)
        let badgeH: CGFloat = 20.0
        let badgeY = controlsY - badgeH - 10.0
        let badgeSize = self.formatBadgeButton.sizeThatFits(CGSize(width: 140, height: badgeH))
        let badgeW = max(78.0, badgeSize.width + 16.0)
        self.formatBadgeButton.frame = CGRect(x: (bounds.width - badgeW) * 0.5, y: badgeY, width: badgeW, height: badgeH)
        
        // Scrubber & Times
        let sliderH: CGFloat = 24.0
        let sliderY = badgeY - sliderH - 8.0
        self.progressSlider.frame = CGRect(x: 28.0, y: sliderY, width: bounds.width - 56.0, height: sliderH)
        self.currentTimeLabel.frame = CGRect(x: 28.0, y: sliderY + 20.0, width: 60.0, height: 16.0)
        self.remainingTimeLabel.frame = CGRect(x: bounds.width - 88.0, y: sliderY + 20.0, width: 60.0, height: 16.0)
        
        // Info Row (Title, Artist, Star, More)
        let infoH: CGFloat = 52.0
        let infoY = sliderY - infoH - 14.0
        self.infoContainerView.frame = CGRect(x: 28.0, y: infoY, width: bounds.width - 56.0, height: infoH)
        let infoW = self.infoContainerView.bounds.width
        let actionBtnSize: CGFloat = 36.0
        self.moreButton.frame = CGRect(x: infoW - actionBtnSize, y: 8, width: actionBtnSize, height: actionBtnSize)
        self.favoriteButton.frame = CGRect(x: infoW - actionBtnSize * 2 - 8, y: 8, width: actionBtnSize, height: actionBtnSize)
        
        let textMaxW = infoW - actionBtnSize * 2 - 18.0
        self.titleLabel.frame = CGRect(x: 0, y: 2, width: textMaxW, height: 26)
        self.artistLabel.frame = CGRect(x: 0, y: 28, width: textMaxW, height: 22)
        
        // Artwork: Fills remaining upper space
        let artTop: CGFloat = 8.0
        let artMaxH = max(160.0, infoY - artTop - 18.0)
        let artSide = min(bounds.width - 64.0, min(artMaxH, 360.0))
        let artX = (bounds.width - artSide) * 0.5
        let artY = artTop + (infoY - artTop - artSide) * 0.5
        
        self.artworkContainerView.frame = CGRect(x: artX, y: artY, width: artSide, height: artSide)
        self.artworkImageView.frame = self.artworkContainerView.bounds
        self.artworkContainerView.layer.shadowPath = UIBezierPath(roundedRect: self.artworkContainerView.bounds, cornerRadius: 24.0).cgPath
        
        let glowPad: CGFloat = 28.0
        self.artworkAmbientGlowView.frame = CGRect(x: artX - glowPad * 0.5, y: artY - glowPad * 0.5, width: artSide + glowPad, height: artSide + glowPad)
        self.artworkGlowGradientLayer.frame = self.artworkAmbientGlowView.bounds
    }
    
    private func layoutLyricsPane(bounds: CGRect) {
        guard bounds.width > 0 && bounds.height > 0 else { return }
        
        // 1. Top Header: Artwork thumbnail (44x44) + Title + Artist + Star + More
        let headerH: CGFloat = 50.0
        self.lyricsHeaderView.frame = CGRect(x: 24.0, y: 4.0, width: bounds.width - 48.0, height: headerH)
        let hW = self.lyricsHeaderView.bounds.width
        
        self.lyricsHeaderArtwork.frame = CGRect(x: 0, y: 3, width: 44, height: 44)
        
        let actionBtnSize: CGFloat = 34.0
        self.lyricsMoreButton.frame = CGRect(x: hW - actionBtnSize, y: 8, width: actionBtnSize, height: actionBtnSize)
        self.lyricsFavoriteButton.frame = CGRect(x: hW - actionBtnSize * 2 - 6, y: 8, width: actionBtnSize, height: actionBtnSize)
        
        let textX: CGFloat = 56.0
        let textW = max(0, hW - textX - (actionBtnSize * 2 + 12))
        self.lyricsHeaderInfoView.frame = CGRect(x: textX, y: 4, width: textW, height: 42)
        self.lyricsTrackTitle.frame = CGRect(x: 0, y: 1, width: textW, height: 21)
        self.lyricsTrackArtist.frame = CGRect(x: 0, y: 22, width: textW, height: 18)
        
        // 2. Lyrics Bottom Player (Mirror of Apple Music Controls)
        let bottomH: CGFloat = 194.0
        let bottomY = bounds.height - bottomH
        self.lyricsBottomContainer.frame = CGRect(x: 0, y: bottomY, width: bounds.width, height: bottomH)
        let botW = bounds.width
        
        // Bottom Bar
        let barH: CGFloat = 40.0
        let barY = bottomH - barH
        self.lyricsBottomBar.frame = CGRect(x: 28.0, y: barY, width: botW - 56.0, height: barH)
        let bW = self.lyricsBottomBar.bounds.width
        let itemW: CGFloat = 44.0
        self.lyricsBottomLyricsBtn.frame = CGRect(x: 0, y: 0, width: itemW, height: itemW)
        self.lyricsBottomAirplayBtn.frame = CGRect(x: (bW - itemW) * 0.5, y: 0, width: itemW, height: itemW)
        self.lyricsBottomQueueBtn.frame = CGRect(x: bW - itemW, y: 0, width: itemW, height: itemW)
        
        // Volume Row
        let volH: CGFloat = 26.0
        let volY = barY - volH - 10.0
        self.lyricsVolumeContainer.frame = CGRect(x: 32.0, y: volY, width: botW - 64.0, height: volH)
        let vW = self.lyricsVolumeContainer.bounds.width
        self.lyricsVolumeMinIcon.frame = CGRect(x: 0, y: 6, width: 16, height: 14)
        self.lyricsVolumeMaxIcon.frame = CGRect(x: vW - 18, y: 5, width: 18, height: 16)
        self.lyricsVolumeSlider.frame = CGRect(x: 26, y: 0, width: vW - 52, height: volH)
        
        // Transport Controls Row (Prev | Play/Pause | Next)
        let transH: CGFloat = 52.0
        let transY = volY - transH - 8.0
        self.lyricsTransportContainer.frame = CGRect(x: 28.0, y: transY, width: botW - 56.0, height: transH)
        let tW = self.lyricsTransportContainer.bounds.width
        let tMid = tW * 0.5
        
        let playSize: CGFloat = 52.0
        self.lyricsPlayPauseButton.frame = CGRect(x: tMid - playSize * 0.5, y: 0, width: playSize, height: playSize)
        
        let skipSize: CGFloat = 42.0
        let skipOffset: CGFloat = 64.0
        self.lyricsPrevButton.frame = CGRect(x: tMid - skipOffset - skipSize * 0.5, y: (transH - skipSize) * 0.5, width: skipSize, height: skipSize)
        self.lyricsNextButton.frame = CGRect(x: tMid + skipOffset - skipSize * 0.5, y: (transH - skipSize) * 0.5, width: skipSize, height: skipSize)
        
        // Scrubber & Lossless Badge
        let badgeH: CGFloat = 18.0
        let badgeY = transY - badgeH - 6.0
        let badgeSize = self.lyricsFormatBadge.sizeThatFits(CGSize(width: 140, height: badgeH))
        let badgeW = max(76.0, badgeSize.width + 16.0)
        self.lyricsFormatBadge.frame = CGRect(x: (botW - badgeW) * 0.5, y: badgeY, width: badgeW, height: badgeH)
        
        let sliderH: CGFloat = 20.0
        let sliderY = badgeY - sliderH - 6.0
        self.lyricsProgressSlider.frame = CGRect(x: 28.0, y: sliderY, width: botW - 56.0, height: sliderH)
        self.lyricsCurrentTimeLabel.frame = CGRect(x: 28.0, y: sliderY + 18.0, width: 56.0, height: 14.0)
        self.lyricsRemainingTimeLabel.frame = CGRect(x: botW - 84.0, y: sliderY + 18.0, width: 56.0, height: 14.0)
        
        // 3. Apple Music Sing / Mic Button
        let micSize: CGFloat = 42.0
        let micX = bounds.width - micSize - 24.0
        let micY = bottomY - micSize - 10.0
        self.lyricsSingButton.frame = CGRect(x: micX, y: micY, width: micSize, height: micSize)
        
        // 4. Lyrics Table View
        let tableTop = headerH + 8.0
        let tableH = max(60.0, bottomY - tableTop - 6.0)
        self.lyricsTableView.frame = CGRect(x: 0, y: tableTop, width: bounds.width, height: tableH)
        self.lyricsPlainTextView.frame = CGRect(x: 24.0, y: tableTop, width: bounds.width - 48.0, height: tableH)
        self.lyricsTableView.contentInset = UIEdgeInsets(top: 20.0, left: 0, bottom: tableH * 0.40, right: 0)
        
        self.lyricsLoadingIndicator.center = CGPoint(x: bounds.width * 0.5, y: tableTop + tableH * 0.35)
        self.lyricsStatusLabel.frame = CGRect(x: 32.0, y: tableTop + tableH * 0.30, width: bounds.width - 64.0, height: 60.0)
        
        self.updateLyricsMask()
    }
    
    private func updateLyricsMask() {
        guard self.lyricsTableView.bounds.width > 0 && self.lyricsTableView.bounds.height > 0 else { return }
        let mask = CAGradientLayer()
        mask.frame = self.lyricsTableView.bounds
        mask.colors = [
            UIColor.clear.cgColor,
            UIColor.black.cgColor,
            UIColor.black.cgColor,
            UIColor.clear.cgColor
        ]
        mask.locations = [0.0, 0.08, 0.88, 1.0]
        self.lyricsTableView.layer.mask = mask
    }
    
    private func layoutQueuePane(bounds: CGRect) {
        guard bounds.width > 0 && bounds.height > 0 else { return }
        
        // Bottom Bar
        let barH: CGFloat = 44.0
        let barY = bounds.height - barH
        self.queueBottomBar.frame = CGRect(x: 28.0, y: barY, width: bounds.width - 56.0, height: barH)
        let qW = self.queueBottomBar.bounds.width
        let itemW: CGFloat = 44.0
        self.queueBottomLyricsBtn.frame = CGRect(x: 0, y: 0, width: itemW, height: itemW)
        self.queueBottomAirplayBtn.frame = CGRect(x: (qW - itemW) * 0.5, y: 0, width: itemW, height: itemW)
        self.queueBottomQueueBtn.frame = CGRect(x: qW - itemW, y: 0, width: itemW, height: itemW)
        
        // Header
        let headerH: CGFloat = 72.0
        self.queueHeaderView.frame = CGRect(x: 24.0, y: 4.0, width: bounds.width - 48.0, height: headerH)
        
        let countText = self.queueCountLabel.text ?? ""
        let countFont = UIFont.systemFont(ofSize: 12.0, weight: .semibold)
        let countSize = (countText as NSString).size(withAttributes: [.font: countFont])
        let badgeW = max(56.0, countSize.width + 16.0)
        let badgeH: CGFloat = 22.0
        
        self.queueCountLabel.frame = CGRect(x: (bounds.width - 48.0) - badgeW, y: 4.0, width: badgeW, height: badgeH)
        self.queueTitleLabel.frame = CGRect(x: 0, y: 2.0, width: (bounds.width - 48.0) - badgeW - 8.0, height: 26.0)
        
        let row2Y: CGFloat = 36.0
        let btnH: CGFloat = 30.0
        let shuffleW: CGFloat = 120.0
        let clearW: CGFloat = 94.0
        self.queueShuffleButton.frame = CGRect(x: 0, y: row2Y, width: shuffleW, height: btnH)
        self.queueClearButton.frame = CGRect(x: shuffleW + 8.0, y: row2Y, width: clearW, height: btnH)
        
        // Table View fills middle
        let tableTop = headerH + 8.0
        let tableH = max(60.0, barY - tableTop - 8.0)
        self.queueTableView.frame = CGRect(x: 0, y: tableTop, width: bounds.width, height: tableH)
        self.queueTableView.contentInset = UIEdgeInsets(top: 4, left: 0, bottom: 12, right: 0)
    }
    
    // MARK: - Content Updates
    private func updateContent() {
        let manager = SGDoxMusicManager.shared
        guard let track = manager.currentTrack else { return }
        
        let d = manager.duration > 0 ? manager.duration : 30.0
        if !self.isDraggingSlider {
            let progress = Float(manager.currentTime / d)
            let timeStr = self.formatTime(manager.currentTime)
            let remStr = "-\(self.formatTime(max(0, d - manager.currentTime)))"
            
            self.progressSlider.value = progress
            self.currentTimeLabel.text = timeStr
            self.remainingTimeLabel.text = remStr
            
            self.lyricsProgressSlider.value = progress
            self.lyricsCurrentTimeLabel.text = timeStr
            self.lyricsRemainingTimeLabel.text = remStr
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
            
            // Video Background
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
        self.lyricsFormatBadge.setImage(iconImg, for: .normal)
        self.lyricsFormatBadge.setTitle(badgeTitle, for: .normal)
        
        // Play / Pause Icons
        let playIconName = manager.isPlaying ? "pause.fill" : "play.fill"
        let playCfg = UIImage.SymbolConfiguration(pointSize: 42, weight: .bold)
        self.playPauseButton.setImage(UIImage(systemName: playIconName, withConfiguration: playCfg), for: .normal)
        self.lyricsPlayPauseButton.setImage(UIImage(systemName: playIconName, withConfiguration: playCfg), for: .normal)
        
        // Star Favorite Button
        let isFav = manager.isFavorite(track: track)
        let starIcon = isFav ? "star.fill" : "star"
        let starCfg = UIImage.SymbolConfiguration(pointSize: 21, weight: .medium)
        let starColor = isFav ? UIColor(red: 0.98, green: 0.18, blue: 0.38, alpha: 1.0) : .white
        self.favoriteButton.setImage(UIImage(systemName: starIcon, withConfiguration: starCfg), for: .normal)
        self.favoriteButton.tintColor = starColor
        self.lyricsFavoriteButton.setImage(UIImage(systemName: starIcon, withConfiguration: starCfg), for: .normal)
        self.lyricsFavoriteButton.tintColor = starColor
        
        // Shuffle & Repeat
        self.shuffleButton.tintColor = manager.isShuffleEnabled ? UIColor(red: 0.98, green: 0.20, blue: 0.35, alpha: 1.0) : UIColor.white.withAlphaComponent(0.60)
        
        let repCfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        switch manager.repeatMode {
        case .off:
            self.repeatButton.setImage(UIImage(systemName: "repeat", withConfiguration: repCfg), for: .normal)
            self.repeatButton.tintColor = UIColor.white.withAlphaComponent(0.60)
        case .all:
            self.repeatButton.setImage(UIImage(systemName: "repeat", withConfiguration: repCfg), for: .normal)
            self.repeatButton.tintColor = UIColor(red: 0.98, green: 0.20, blue: 0.35, alpha: 1.0)
        case .one:
            self.repeatButton.setImage(UIImage(systemName: "repeat.1", withConfiguration: repCfg), for: .normal)
            self.repeatButton.tintColor = UIColor(red: 0.98, green: 0.20, blue: 0.35, alpha: 1.0)
        }
        
        self.updateArtworkScale(isPlaying: manager.isPlaying)
    }
    
    private func updateArtworkScale(isPlaying: Bool) {
        let opacity: Float = isPlaying ? 0.42 : 0.25
        let radius: CGFloat = isPlaying ? 24.0 : 16.0
        self.artworkContainerView.layer.shadowOpacity = opacity
        self.artworkContainerView.layer.shadowRadius = radius
    }
    
    private func updateAmbientColor(from image: UIImage) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let cgImage = image.cgImage else { return }
            let width = 20
            let height = 20
            var rawData = [UInt8](repeating: 0, count: width * height * 4)
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let ctx = CGContext(data: &rawData, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
            ctx?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            
            var totalR: CGFloat = 0, totalG: CGFloat = 0, totalB: CGFloat = 0
            var maxSat: CGFloat = -1
            var accentR: CGFloat = 0.3, accentG: CGFloat = 0.25, accentB: CGFloat = 0.5
            let count = CGFloat(width * height)
            
            for i in 0..<(width * height) {
                let r = CGFloat(rawData[i * 4]) / 255.0
                let g = CGFloat(rawData[i * 4 + 1]) / 255.0
                let b = CGFloat(rawData[i * 4 + 2]) / 255.0
                totalR += r; totalG += g; totalB += b
                let maxC = max(r, max(g, b))
                let minC = min(r, min(g, b))
                let sat = maxC > 0 ? (maxC - minC) / maxC : 0
                if sat > maxSat && maxC > 0.25 {
                    maxSat = sat
                    accentR = r; accentG = g; accentB = b
                }
            }
            
            let avgColor = UIColor(red: (totalR / count) * 0.7, green: (totalG / count) * 0.7, blue: (totalB / count) * 0.7, alpha: 0.95)
            let vibrantColor = UIColor(red: min(1.0, accentR * 1.2), green: min(1.0, accentG * 1.2), blue: min(1.0, accentB * 1.2), alpha: 0.95)
            let deepColor = UIColor(red: accentR * 0.15, green: accentG * 0.15, blue: accentB * 0.20, alpha: 0.98)
            
            let newColors = [vibrantColor.cgColor, avgColor.cgColor, deepColor.cgColor]
            let glowColors = [
                vibrantColor.withAlphaComponent(0.45).cgColor,
                avgColor.withAlphaComponent(0.18).cgColor,
                UIColor.clear.cgColor
            ]
            
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.ambientGradientLayer.colors = newColors
                self.artworkGlowGradientLayer.colors = glowColors
            }
        }
    }
    
    private func reloadQueueData() {
        self.cachedQueue = SGDoxMusicManager.shared.effectiveQueue()
        let count = self.cachedQueue.count
        self.queueCountLabel.text = count == 0 ? "Пусто" : "\(count) трек\(self.pluralEnding(count))"
        self.queueClearButton.isHidden = count == 0
        self.queueTableView.reloadData()
    }
    
    private func pluralEnding(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        if mod100 >= 11 && mod100 <= 19 { return "ов" }
        if mod10 == 1 { return "" }
        if mod10 >= 2 && mod10 <= 4 { return "а" }
        return "ов"
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let s = Int(seconds)
        let mins = s / 60
        let secs = s % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    // MARK: - Mode Switching (Now Playing vs Lyrics vs Queue)
    @objc private func nowPlayingSegmentPressed() {
        self.switchMode(to: .nowPlaying)
    }
    
    @objc private func lyricsBottomPressed() {
        self.switchMode(to: self.currentMode == .lyrics ? .nowPlaying : .lyrics)
    }
    
    @objc private func queueBottomPressed() {
        self.switchMode(to: self.currentMode == .queue ? .nowPlaying : .queue)
    }
    
    @objc private func artworkTapped() {
        self.switchMode(to: .lyrics)
    }
    
    private func switchMode(to targetMode: PlayerMode) {
        guard self.currentMode != targetMode else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let oldMode = self.currentMode
        self.currentMode = targetMode
        
        if targetMode == .lyrics {
            self.loadLyricsIfNeeded()
        } else if targetMode == .queue {
            self.reloadQueueData()
        }
        
        let containerForMode: (PlayerMode) -> UIView = { mode in
            switch mode {
            case .nowPlaying: return self.nowPlayingContainerView
            case .lyrics: return self.lyricsContainerView
            case .queue: return self.queueContainerView
            }
        }
        
        let oldView = containerForMode(oldMode)
        let newView = containerForMode(targetMode)
        
        newView.isHidden = false
        newView.alpha = 0.0
        
        let movingRight = targetMode.rawValue > oldMode.rawValue
        let startX: CGFloat = movingRight ? 35.0 : -35.0
        let exitX: CGFloat = movingRight ? -35.0 : 35.0
        
        newView.transform = CGAffineTransform(translationX: startX, y: 0)
        
        UIView.animate(withDuration: 0.32, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.5, options: [.allowUserInteraction], animations: {
            oldView.alpha = 0.0
            oldView.transform = CGAffineTransform(translationX: exitX, y: 0)
            newView.alpha = 1.0
            newView.transform = .identity
        }) { _ in
            oldView.isHidden = true
            oldView.transform = .identity
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
        
        // Duration of active line
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
            // High-frequency word reveal update on the active line
            let activeIndexPath = IndexPath(row: newIndex, section: 0)
            if let cell = self.lyricsTableView.cellForRow(at: activeIndexPath) as? SGDoxLyricsCell {
                cell.updateProgress(currentTime: currentTime, lineDuration: lineDuration)
            }
        }
    }
    
    // MARK: - Actions & Volume
    @objc private func volumeChanged(_ slider: UISlider) {
        SGDoxMusicManager.shared.volume = slider.value
        self.volumeSlider.value = slider.value
        self.lyricsVolumeSlider.value = slider.value
    }
    
    @objc private func singButtonPressed() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let overlay = UndoOverlayController(presentationData: self.presentationData, content: .actionSucceeded(title: "Apple Music Sing", text: "Режим вокала активен", cancel: nil, destructive: false), elevatedLayout: false, action: { _ in return false })
        self.present(overlay, in: .window(.root))
    }
    
    @objc private func airplayPressed() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let overlay = UndoOverlayController(presentationData: self.presentationData, content: .info(title: "AirPlay", text: "Аудио транслируется на системный вывод", timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false })
        self.present(overlay, in: .window(.root))
    }
    
    @objc private func formatBadgePressed() {
        guard let track = SGDoxMusicManager.shared.currentTrack else { return }
        let isAtmos = track.isDolbyAtmos
        let isLossless = track.isLossless
        
        let title = isAtmos ? "Dolby Atmos" : (isLossless ? "Lossless Audio" : "Высокое качество")
        let desc = isAtmos ? "Пространственное аудио с полным эффектом присутствия." : (isLossless ? "24-бит / 48 кГц без потери качества звука ALAC." : "Стереопоток AAC 256 кбит/с.")
        
        let alert = UIAlertController(title: title, message: desc, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        self.present(alert, animated: true)
    }
    
    @objc private func morePressed() {
        guard let track = SGDoxMusicManager.shared.currentTrack else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        
        let alert = UIAlertController(title: track.title, message: track.artist, preferredStyle: .actionSheet)
        alert.popoverPresentationController?.sourceView = self.view
        alert.popoverPresentationController?.sourceRect = CGRect(x: self.view.bounds.width * 0.5, y: self.view.bounds.height * 0.5, width: 1, height: 1)
        
        // Favorite
        let isFav = SGDoxMusicManager.shared.isFavorite(track: track)
        alert.addAction(UIAlertAction(title: isFav ? "Удалить из избранного" : "Добавить в избранное", style: .default, handler: { [weak self] _ in
            self?.favoritePressed()
        }))
        
        // Together
        alert.addAction(UIAlertAction(title: "Совместный эфир", style: .default, handler: { [weak self] _ in
            self?.listenTogetherPressed()
        }))
        
        // Wave
        alert.addAction(UIAlertAction(title: SGDoxMusicManager.shared.isWaveEnabled ? "Выключить Волну" : "Включить Волну", style: .default, handler: { [weak self] _ in
            SGDoxMusicManager.shared.isWaveEnabled.toggle()
            if SGDoxMusicManager.shared.isWaveEnabled { SGDoxMusicManager.shared.startWave() }
            self?.updateContent()
        }))
        
        // Offline Download
        let isDown = SGDoxMusicOfflineManager.shared.isDownloaded(trackId: track.id)
        alert.addAction(UIAlertAction(title: isDown ? "Удалить из офлайн-памяти" : "Скачать для офлайна", style: .default, handler: { [weak self] _ in
            self?.downloadPressed()
        }))
        
        // Pin to Profile
        alert.addAction(UIAlertAction(title: "Закрепить в профиле", style: .default, handler: { [weak self] _ in
            self?.pinToProfilePressed()
        }))
        
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: nil))
        self.present(alert, animated: true)
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
            self.lyricsPlayPauseButton.transform = CGAffineTransform(scaleX: 0.90, y: 0.90)
        }) { _ in
            UIView.animate(withDuration: 0.14) {
                self.playPauseButton.transform = .identity
                self.lyricsPlayPauseButton.transform = .identity
            }
        }
        SGDoxMusicManager.shared.togglePlay()
    }
    
    @objc private func nextPressed() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        UIView.animate(withDuration: 0.10, animations: {
            self.nextButton.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
            self.lyricsNextButton.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
        }) { _ in
            UIView.animate(withDuration: 0.14) {
                self.nextButton.transform = .identity
                self.lyricsNextButton.transform = .identity
            }
        }
        SGDoxMusicManager.shared.next()
    }
    
    @objc private func previousPressed() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        UIView.animate(withDuration: 0.10, animations: {
            self.previousButton.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
            self.lyricsPrevButton.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
        }) { _ in
            UIView.animate(withDuration: 0.14) {
                self.previousButton.transform = .identity
                self.lyricsPrevButton.transform = .identity
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
    
    @objc private func sliderValueChanged() {
        self.isDraggingSlider = true
        let duration = SGDoxMusicManager.shared.duration > 0 ? SGDoxMusicManager.shared.duration : 30.0
        let val = self.currentMode == .lyrics ? self.lyricsProgressSlider.value : self.progressSlider.value
        let target = Double(val) * duration
        let timeStr = self.formatTime(target)
        self.currentTimeLabel.text = timeStr
        self.lyricsCurrentTimeLabel.text = timeStr
    }
    
    @objc private func sliderTouchEnded() {
        self.isDraggingSlider = false
        let duration = SGDoxMusicManager.shared.duration > 0 ? SGDoxMusicManager.shared.duration : 30.0
        let val = self.currentMode == .lyrics ? self.lyricsProgressSlider.value : self.progressSlider.value
        let target = Double(val) * duration
        SGDoxMusicManager.shared.seek(to: target)
        self.videoPlayer?.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }
    
    // MARK: - Video Playback
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
        }
    }
    
    private func teardownVideoPlayback(animated: Bool = false) {
        if let obs = self.videoEndObserver {
            NotificationCenter.default.removeObserver(obs)
            self.videoEndObserver = nil
        }
        self.videoPlayer?.pause()
        self.videoPlayer = nil
        self.videoPlayerLayer?.removeFromSuperlayer()
        self.videoPlayerLayer = nil
        self.videoItem = nil
        self.currentVideoClipUrl = nil
        self.videoContainerView.alpha = 0.0
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
        let track = self.cachedQueue[indexPath.row]
        cell.configure(track: track)
        return cell
    }
    
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if tableView == self.lyricsTableView {
            guard let lyrics = self.currentLyrics, indexPath.row < lyrics.lines.count else { return }
            let line = lyrics.lines[indexPath.row]
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            SGDoxMusicManager.shared.seek(to: line.time)
            self.isUserScrollingLyrics = false
            self.userScrollTimer?.invalidate()
            self.syncLyricsPosition(currentTime: line.time, animated: true)
            return
        }
        
        guard indexPath.row < self.cachedQueue.count else { return }
        let selectedTrack = self.cachedQueue[indexPath.row]
        let remaining = Array(self.cachedQueue.suffix(from: indexPath.row + 1))
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        SGDoxMusicManager.shared.play(track: selectedTrack, queue: remaining)
        self.reloadQueueData()
    }
    
    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        if scrollView == self.lyricsTableView {
            self.isUserScrollingLyrics = true
            self.userScrollTimer?.invalidate()
            self.userScrollTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in
                self?.isUserScrollingLyrics = false
                self?.syncLyricsPosition(currentTime: SGDoxMusicManager.shared.currentTime, animated: true)
            }
        }
    }
}

// MARK: - Apple Music Lyrics Cell with Progressive Karaoke Word Reveal
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
        self.currentLine = line
        self.isCurrentActive = isActive
        self.prepareWords(from: line.text)
        
        if isActive {
            self.updateProgress(currentTime: currentTime, lineDuration: lineDuration)
        } else {
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
        
        // Progressive word-by-word reveal (Apple Music karaoke style)
        let attr = NSMutableAttributedString(string: text, attributes: [
            .font: SGDoxLyricsCell.font,
            .foregroundColor: UIColor.white.withAlphaComponent(0.38)
        ])
        
        var cumulativeWeight: Double = 0.0
        for item in self.words {
            let wordStartFraction = cumulativeWeight / self.totalWeight
            cumulativeWeight += item.weight
            
            if progress >= wordStartFraction {
                attr.addAttribute(.foregroundColor, value: UIColor.white, range: item.range)
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
