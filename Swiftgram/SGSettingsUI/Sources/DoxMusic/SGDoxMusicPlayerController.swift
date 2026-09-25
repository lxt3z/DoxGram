import Foundation
import UIKit
import Display
import TelegramCore
import AccountContext
import TelegramPresentationData
import UndoUI
import OverlayStatusController
import AppBundle

public final class SGDoxMusicPlayerController: ViewController, UIGestureRecognizerDelegate, UITableViewDataSource, UITableViewDelegate {
    private let context: AccountContext
    private var presentationData: PresentationData
    
    // Background
    private let backgroundImageView = UIImageView()
    private let ambientGradientLayer = CAGradientLayer()
    private let backgroundBlurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let darkDimOverlay = UIView()
    
    // Header
    private let grabberView = UIView()
    private let dismissButton = UIButton(type: .system)
    private let segmentContainerView = UIView()
    private let segmentIndicatorView = UIView()
    private let nowPlayingSegmentButton = UIButton(type: .system)
    private let queueSegmentButton = UIButton(type: .system)
    private let sourceBadgeContainer = UIView()
    private let sourceIconView = UIImageView()
    private let sourceLabel = UILabel()
    
    // Content Containers (All-in-One: Now Playing vs Queue)
    private let nowPlayingContainerView = UIView()
    private let queueContainerView = UIView()
    private var isQueueMode = false
    
    // --- Now Playing Pane ---
    private let artworkAmbientGlowView = UIView()
    private let artworkGlowGradientLayer = CAGradientLayer()
    private let artworkContainerView = UIView()
    private let artworkImageView = UIImageView()
    
    private let infoContainerView = UIView()
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    private let favoriteButton = UIButton(type: .system)
    
    private let progressSlider = UISlider()
    private let currentTimeLabel = UILabel()
    private let remainingTimeLabel = UILabel()
    
    private let controlsContainerView = UIView()
    private let shuffleButton = UIButton(type: .system)
    private let previousButton = UIButton(type: .system)
    private let playPauseContainer = UIView()
    private let playPauseButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let repeatButton = UIButton(type: .system)
    
    private let actionsStackView = UIStackView()
    private let pinToProfileButton = UIButton(type: .system)
    private let waveButton = UIButton(type: .system)
    private let autoplayButton = UIButton(type: .system)
    private let downloadButton = UIButton(type: .system)
    
    public var onDismiss: (() -> Void)?
    public var onDismissBegin: (() -> Void)?
    private var hasBegunDismissal = false
    
    private func triggerDismissBeginIfNeeded() {
        guard !self.hasBegunDismissal else { return }
        self.hasBegunDismissal = true
        self.onDismissBegin?()
    }
    
    // --- Queue Pane ---
    private let queueHeaderView = UIView()
    private let queueTitleLabel = UILabel()
    private let queueCountLabel = UILabel()
    private let queueShuffleButton = UIButton(type: .system)
    private let queueClearButton = UIButton(type: .system)
    private let queueTableView = UITableView(frame: .zero, style: .plain)
    
    private let queueMiniBar = UIView()
    private let queueMiniBlurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let queueMiniArtwork = UIImageView()
    private let queueMiniTitle = UILabel()
    private let queueMiniArtist = UILabel()
    private let queueMiniPlayPause = UIButton(type: .system)
    private let queueMiniNext = UIButton(type: .system)
    
    private var cachedQueue: [SGDoxMusicTrack] = []
    private var isDraggingSlider = false
    private var displayedTrackId: String?
    private var stateToken: UUID?
    private var timeToken: UUID?
    private var validLayout: ContainerViewLayout?
    
    public init(context: AccountContext) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: nil)
        self.navigationPresentation = .modal
        self.statusBar.statusBarStyle = .White
        self.ready.set(.single(true))
    }
    
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        if let token = self.stateToken {
            SGDoxMusicManager.shared.removeStateListener(token)
        }
        if let token = self.timeToken {
            SGDoxMusicManager.shared.removeTimeListener(token)
        }
    }
    
    public override func loadDisplayNode() {
        super.loadDisplayNode()
        self.displayNode.backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1.0)
    }
    
    public override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        self.validLayout = layout
        self.displayNode.frame = CGRect(origin: .zero, size: layout.size)
        self.view.frame = CGRect(origin: .zero, size: layout.size)
        let bounds = CGRect(origin: .zero, size: layout.size)
        let safeArea = layout.safeInsets
        self.applyLayout(bounds: bounds, safeArea: safeArea)
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
        
        self.stateToken = SGDoxMusicManager.shared.addStateListener { [weak self] in
            DispatchQueue.main.async {
                self?.updateContent()
                self?.reloadQueueData()
            }
        }
        
        self.timeToken = SGDoxMusicManager.shared.addTimeListener { [weak self] current, duration in
            DispatchQueue.main.async {
                guard let self = self, !self.isDraggingSlider else { return }
                let d = duration > 0 ? duration : 30.0
                self.progressSlider.value = Float(current / d)
                self.currentTimeLabel.text = self.formatTime(current)
                self.remainingTimeLabel.text = "-\(self.formatTime(max(0, d - current)))"
            }
        }
        
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(self.handlePanGesture(_:)))
        panGesture.delegate = self
        self.view.addGestureRecognizer(panGesture)
    }
    
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
            if translation.y > 120 || velocity.y > 600 {
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
                    self.dismiss(animated: false)
                }
            } else {
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
    
    private func setupViews() {
        // 1. Background Layers
        self.backgroundImageView.contentMode = .scaleAspectFill
        self.backgroundImageView.clipsToBounds = true
        self.view.addSubview(self.backgroundImageView)
        
        self.ambientGradientLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        self.ambientGradientLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        self.view.layer.addSublayer(self.ambientGradientLayer)
        
        self.backgroundBlurView.effect = UIBlurEffect(style: .dark)
        self.view.addSubview(self.backgroundBlurView)
        
        self.darkDimOverlay.backgroundColor = UIColor(red: 0.04, green: 0.04, blue: 0.07, alpha: 0.55)
        self.view.addSubview(self.darkDimOverlay)
        
        // 2. Header
        self.grabberView.backgroundColor = UIColor(white: 1.0, alpha: 0.35)
        self.grabberView.layer.cornerRadius = 2.5
        self.view.addSubview(self.grabberView)
        
        // Dismiss Chevron Button (Liquid Glass Circular Pill)
        let chevronConfig = UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        self.dismissButton.setImage(UIImage(systemName: "chevron.down", withConfiguration: chevronConfig), for: .normal)
        self.dismissButton.tintColor = UIColor(white: 1.0, alpha: 0.85)
        self.dismissButton.backgroundColor = UIColor(white: 1.0, alpha: 0.14)
        self.dismissButton.layer.cornerRadius = 16
        self.dismissButton.layer.cornerCurve = .continuous
        self.dismissButton.layer.borderWidth = 0.5
        self.dismissButton.layer.borderColor = UIColor(white: 1.0, alpha: 0.18).cgColor
        self.dismissButton.clipsToBounds = true
        self.dismissButton.addTarget(self, action: #selector(self.dismissPressed), for: .touchUpInside)
        self.view.addSubview(self.dismissButton)
        
        // Segmented Mode Switcher: [ Сейчас | Очередь ]
        self.segmentContainerView.backgroundColor = UIColor(white: 1.0, alpha: 0.12)
        self.segmentContainerView.layer.cornerRadius = 16
        self.segmentContainerView.layer.borderWidth = 0.5
        self.segmentContainerView.layer.borderColor = UIColor(white: 1.0, alpha: 0.18).cgColor
        self.segmentContainerView.clipsToBounds = true
        self.view.addSubview(self.segmentContainerView)
        
        self.segmentIndicatorView.backgroundColor = UIColor(white: 1.0, alpha: 0.28)
        self.segmentIndicatorView.layer.cornerRadius = 13
        self.segmentContainerView.addSubview(self.segmentIndicatorView)
        
        self.nowPlayingSegmentButton.setTitle("Сейчас", for: .normal)
        self.nowPlayingSegmentButton.setTitleColor(.white, for: .normal)
        self.nowPlayingSegmentButton.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        self.nowPlayingSegmentButton.addTarget(self, action: #selector(self.nowPlayingSegmentPressed), for: .touchUpInside)
        self.segmentContainerView.addSubview(self.nowPlayingSegmentButton)
        
        self.queueSegmentButton.setTitle("Очередь", for: .normal)
        self.queueSegmentButton.setTitleColor(.white, for: .normal)
        self.queueSegmentButton.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        self.queueSegmentButton.addTarget(self, action: #selector(self.queueSegmentPressed), for: .touchUpInside)
        self.segmentContainerView.addSubview(self.queueSegmentButton)
        
        // Source Badge Pill (Right)
        self.sourceBadgeContainer.backgroundColor = UIColor(white: 1.0, alpha: 0.10)
        self.sourceBadgeContainer.layer.cornerRadius = 14
        self.sourceBadgeContainer.layer.borderWidth = 0.5
        self.sourceBadgeContainer.layer.borderColor = UIColor(white: 1.0, alpha: 0.14).cgColor
        self.sourceBadgeContainer.clipsToBounds = true
        self.view.addSubview(self.sourceBadgeContainer)
        
        self.sourceIconView.contentMode = .scaleAspectFit
        self.sourceIconView.tintColor = UIColor(white: 1.0, alpha: 0.85)
        self.sourceBadgeContainer.addSubview(self.sourceIconView)
        
        self.sourceLabel.textColor = UIColor(white: 1.0, alpha: 0.85)
        self.sourceLabel.font = UIFont.systemFont(ofSize: 11.5, weight: .medium)
        self.sourceBadgeContainer.addSubview(self.sourceLabel)
        
        // 3. Content Panes
        self.view.addSubview(self.nowPlayingContainerView)
        self.view.addSubview(self.queueContainerView)
        self.queueContainerView.alpha = 0.0
        self.queueContainerView.isHidden = true
        
        self.setupNowPlayingPane()
        self.setupQueuePane()
    }
    
    private func setupNowPlayingPane() {
        // Animated Ambient Glow behind Artwork (Organic Radial Aura)
        self.artworkAmbientGlowView.clipsToBounds = false
        self.artworkGlowGradientLayer.type = .radial
        self.artworkGlowGradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        self.artworkGlowGradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        self.artworkGlowGradientLayer.locations = [0.0, 0.45, 1.0]
        self.artworkAmbientGlowView.layer.addSublayer(self.artworkGlowGradientLayer)
        self.nowPlayingContainerView.addSubview(self.artworkAmbientGlowView)

        // Artwork
        self.artworkContainerView.layer.cornerRadius = 24
        self.artworkContainerView.layer.shadowOffset = CGSize(width: 0, height: 16)
        self.artworkContainerView.layer.shadowOpacity = 0.45
        self.artworkContainerView.layer.shadowRadius = 24
        self.artworkContainerView.layer.shadowColor = UIColor.black.cgColor
        self.nowPlayingContainerView.addSubview(self.artworkContainerView)
        
        self.artworkImageView.contentMode = .scaleAspectFill
        self.artworkImageView.clipsToBounds = true
        self.artworkImageView.layer.cornerRadius = 24
        self.artworkImageView.backgroundColor = UIColor(white: 0.15, alpha: 1.0)
        self.artworkContainerView.addSubview(self.artworkImageView)
        
        // Info Area: Title, Artist, Favorite
        self.nowPlayingContainerView.addSubview(self.infoContainerView)
        
        self.titleLabel.textColor = .white
        self.titleLabel.font = UIFont.systemFont(ofSize: 22, weight: .bold)
        self.titleLabel.lineBreakMode = .byTruncatingTail
        self.infoContainerView.addSubview(self.titleLabel)
        
        self.artistLabel.textColor = UIColor.white.withAlphaComponent(0.72)
        self.artistLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        self.artistLabel.lineBreakMode = .byTruncatingTail
        self.infoContainerView.addSubview(self.artistLabel)
        
        let heartConfig = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        self.favoriteButton.setImage(UIImage(systemName: "heart", withConfiguration: heartConfig), for: .normal)
        self.favoriteButton.tintColor = UIColor.white.withAlphaComponent(0.8)
        self.favoriteButton.addTarget(self, action: #selector(self.favoritePressed), for: .touchUpInside)
        self.infoContainerView.addSubview(self.favoriteButton)
        
        // Slider & Time
        self.progressSlider.minimumValue = 0.0
        self.progressSlider.maximumValue = 1.0
        self.progressSlider.minimumTrackTintColor = .white
        self.progressSlider.maximumTrackTintColor = UIColor(white: 1.0, alpha: 0.22)
        self.progressSlider.setThumbImage(self.generateSliderThumb(), for: .normal)
        self.progressSlider.addTarget(self, action: #selector(self.sliderValueChanged), for: .valueChanged)
        self.progressSlider.addTarget(self, action: #selector(self.sliderTouchEnded), for: [.touchUpInside, .touchUpOutside])
        self.nowPlayingContainerView.addSubview(self.progressSlider)
        
        self.currentTimeLabel.textColor = UIColor(white: 1.0, alpha: 0.55)
        self.currentTimeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        self.currentTimeLabel.text = "0:00"
        self.nowPlayingContainerView.addSubview(self.currentTimeLabel)
        
        self.remainingTimeLabel.textColor = UIColor(white: 1.0, alpha: 0.55)
        self.remainingTimeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        self.remainingTimeLabel.text = "-0:00"
        self.remainingTimeLabel.textAlignment = .right
        self.nowPlayingContainerView.addSubview(self.remainingTimeLabel)
        
        // Controls Row: Shuffle | Prev | Play/Pause | Next | Repeat
        let subConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        self.shuffleButton.setImage(UIImage(systemName: "shuffle", withConfiguration: subConfig), for: .normal)
        self.shuffleButton.tintColor = UIColor.white.withAlphaComponent(0.6)
        self.shuffleButton.addTarget(self, action: #selector(self.shufflePressed), for: .touchUpInside)
        self.controlsContainerView.addSubview(self.shuffleButton)
        
        let skipConfig = UIImage.SymbolConfiguration(pointSize: 26, weight: .bold)
        self.previousButton.setImage(UIImage(systemName: "backward.fill", withConfiguration: skipConfig), for: .normal)
        self.previousButton.tintColor = .white
        self.previousButton.addTarget(self, action: #selector(self.previousPressed), for: .touchUpInside)
        self.controlsContainerView.addSubview(self.previousButton)
        
        // Play/Pause Big Glass Circle
        self.playPauseContainer.layer.cornerRadius = 34
        self.playPauseContainer.layer.cornerCurve = .continuous
        self.playPauseContainer.clipsToBounds = true
        self.playPauseContainer.backgroundColor = UIColor(white: 1.0, alpha: 0.22)
        self.playPauseContainer.layer.borderWidth = 0.5
        self.playPauseContainer.layer.borderColor = UIColor(white: 1.0, alpha: 0.35).cgColor
        
        let playConfig = UIImage.SymbolConfiguration(pointSize: 28, weight: .bold)
        self.playPauseButton.setImage(UIImage(systemName: "play.fill", withConfiguration: playConfig), for: .normal)
        self.playPauseButton.tintColor = .white
        self.playPauseButton.addTarget(self, action: #selector(self.playPausePressed), for: .touchUpInside)
        self.playPauseContainer.addSubview(self.playPauseButton)
        self.controlsContainerView.addSubview(self.playPauseContainer)
        
        self.nextButton.setImage(UIImage(systemName: "forward.fill", withConfiguration: skipConfig), for: .normal)
        self.nextButton.tintColor = .white
        self.nextButton.addTarget(self, action: #selector(self.nextPressed), for: .touchUpInside)
        self.controlsContainerView.addSubview(self.nextButton)
        
        self.repeatButton.setImage(UIImage(systemName: "repeat", withConfiguration: subConfig), for: .normal)
        self.repeatButton.tintColor = UIColor.white.withAlphaComponent(0.6)
        self.repeatButton.addTarget(self, action: #selector(self.repeatPressed), for: .touchUpInside)
        self.controlsContainerView.addSubview(self.repeatButton)
        
        self.nowPlayingContainerView.addSubview(self.controlsContainerView)
        
        // Bottom Action Buttons: Profile | Wave | Autoplay | Download
        self.actionsStackView.axis = .horizontal
        self.actionsStackView.distribution = .fillEqually
        self.actionsStackView.alignment = .fill
        self.actionsStackView.spacing = 8
        
        self.styleCapsuleButton(self.pinToProfileButton, title: "Профиль", icon: "person.circle")
        self.pinToProfileButton.addTarget(self, action: #selector(self.pinToProfilePressed), for: .touchUpInside)
        self.actionsStackView.addArrangedSubview(self.pinToProfileButton)
        
        self.styleCapsuleButton(self.waveButton, title: "Волна", icon: "waveform")
        self.waveButton.addTarget(self, action: #selector(self.wavePressed), for: .touchUpInside)
        self.actionsStackView.addArrangedSubview(self.waveButton)
        
        self.styleCapsuleButton(self.autoplayButton, title: "Авто", icon: "infinity")
        self.autoplayButton.addTarget(self, action: #selector(self.autoplayPressed), for: .touchUpInside)
        self.actionsStackView.addArrangedSubview(self.autoplayButton)

        self.styleCapsuleButton(self.downloadButton, title: "Скачать", icon: "arrow.down.circle")
        self.downloadButton.addTarget(self, action: #selector(self.downloadPressed), for: .touchUpInside)
        self.actionsStackView.addArrangedSubview(self.downloadButton)
        
        self.nowPlayingContainerView.addSubview(self.actionsStackView)
    }
    
    private func setupQueuePane() {
        // Queue Header
        self.queueTitleLabel.text = "Далее в очереди"
        self.queueTitleLabel.textColor = .white
        self.queueTitleLabel.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        self.queueHeaderView.addSubview(self.queueTitleLabel)
        
        self.queueCountLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        self.queueCountLabel.font = UIFont.systemFont(ofSize: 11.5, weight: .semibold)
        self.queueCountLabel.textAlignment = .center
        self.queueCountLabel.backgroundColor = UIColor(white: 1.0, alpha: 0.12)
        self.queueCountLabel.layer.cornerRadius = 11
        self.queueCountLabel.layer.cornerCurve = .continuous
        self.queueCountLabel.clipsToBounds = true
        self.queueHeaderView.addSubview(self.queueCountLabel)
        
        let shuffleConfig = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        self.queueShuffleButton.setImage(UIImage(systemName: "shuffle", withConfiguration: shuffleConfig), for: .normal)
        self.queueShuffleButton.setTitle(" Перемешать", for: .normal)
        self.queueShuffleButton.setTitleColor(.white, for: .normal)
        self.queueShuffleButton.titleLabel?.font = UIFont.systemFont(ofSize: 12.5, weight: .semibold)
        self.queueShuffleButton.backgroundColor = UIColor(white: 1.0, alpha: 0.14)
        self.queueShuffleButton.layer.cornerRadius = 15
        self.queueShuffleButton.layer.cornerCurve = .continuous
        self.queueShuffleButton.layer.borderWidth = 0.5
        self.queueShuffleButton.layer.borderColor = UIColor(white: 1.0, alpha: 0.18).cgColor
        self.queueShuffleButton.tintColor = .white
        self.queueShuffleButton.clipsToBounds = true
        self.queueShuffleButton.addTarget(self, action: #selector(self.queueShufflePressed), for: .touchUpInside)
        self.queueHeaderView.addSubview(self.queueShuffleButton)
        
        let clearConfig = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        self.queueClearButton.setImage(UIImage(systemName: "trash", withConfiguration: clearConfig), for: .normal)
        self.queueClearButton.setTitle(" Очистить", for: .normal)
        self.queueClearButton.setTitleColor(UIColor(red: 1.0, green: 0.35, blue: 0.40, alpha: 1.0), for: .normal)
        self.queueClearButton.titleLabel?.font = UIFont.systemFont(ofSize: 12.5, weight: .semibold)
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
        
        // Mini Bar at bottom of Queue
        self.queueMiniBar.layer.cornerRadius = 18
        self.queueMiniBar.layer.cornerCurve = .continuous
        self.queueMiniBar.layer.borderWidth = 0.5
        self.queueMiniBar.layer.borderColor = UIColor(white: 1.0, alpha: 0.16).cgColor
        self.queueMiniBar.clipsToBounds = true
        
        self.queueMiniBlurView.effect = UIBlurEffect(style: .dark)
        self.queueMiniBlurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.queueMiniBar.addSubview(self.queueMiniBlurView)
        
        let darkOverlay = UIView()
        darkOverlay.backgroundColor = UIColor(white: 0.10, alpha: 0.65)
        darkOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.queueMiniBar.addSubview(darkOverlay)
        
        self.queueMiniArtwork.contentMode = .scaleAspectFill
        self.queueMiniArtwork.clipsToBounds = true
        self.queueMiniArtwork.layer.cornerRadius = 10
        self.queueMiniArtwork.layer.cornerCurve = .continuous
        self.queueMiniBar.addSubview(self.queueMiniArtwork)
        
        self.queueMiniTitle.textColor = .white
        self.queueMiniTitle.font = UIFont.systemFont(ofSize: 13.5, weight: .semibold)
        self.queueMiniTitle.lineBreakMode = .byTruncatingTail
        self.queueMiniBar.addSubview(self.queueMiniTitle)
        
        self.queueMiniArtist.textColor = UIColor(white: 1.0, alpha: 0.65)
        self.queueMiniArtist.font = UIFont.systemFont(ofSize: 11.5, weight: .regular)
        self.queueMiniArtist.lineBreakMode = .byTruncatingTail
        self.queueMiniBar.addSubview(self.queueMiniArtist)
        
        let miniPlayCfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)
        self.queueMiniPlayPause.setImage(UIImage(systemName: "play.fill", withConfiguration: miniPlayCfg), for: .normal)
        self.queueMiniPlayPause.tintColor = .white
        self.queueMiniPlayPause.addTarget(self, action: #selector(self.playPausePressed), for: .touchUpInside)
        self.queueMiniBar.addSubview(self.queueMiniPlayPause)
        
        let miniNextCfg = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        self.queueMiniNext.setImage(UIImage(systemName: "forward.fill", withConfiguration: miniNextCfg), for: .normal)
        self.queueMiniNext.tintColor = UIColor.white.withAlphaComponent(0.85)
        self.queueMiniNext.addTarget(self, action: #selector(self.nextPressed), for: .touchUpInside)
        self.queueMiniBar.addSubview(self.queueMiniNext)
        
        let miniTap = UITapGestureRecognizer(target: self, action: #selector(self.nowPlayingSegmentPressed))
        self.queueMiniBar.addGestureRecognizer(miniTap)
        
        self.queueContainerView.addSubview(self.queueMiniBar)
    }
    
    private func styleCapsuleButton(_ button: UIButton, title: String, icon: String) {
        let config = UIImage.SymbolConfiguration(pointSize: 11.5, weight: .semibold)
        button.setImage(UIImage(systemName: icon, withConfiguration: config), for: .normal)
        button.setTitle(" \(title)", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 11.5, weight: .semibold)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.65
        button.titleLabel?.lineBreakMode = .byClipping
        button.backgroundColor = UIColor(white: 1.0, alpha: 0.14)
        button.tintColor = .white
        button.layer.cornerRadius = 16
        button.layer.cornerCurve = .continuous
        button.layer.borderWidth = 0.5
        button.layer.borderColor = UIColor(white: 1.0, alpha: 0.18).cgColor
        button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 4, bottom: 6, right: 4)
    }
    
    private func generateSliderThumb() -> UIImage {
        let size = CGSize(width: 14, height: 14)
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        let context = UIGraphicsGetCurrentContext()
        context?.setFillColor(UIColor.white.cgColor)
        context?.fillEllipse(in: CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        return image
    }
    
    // MARK: - Layout
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let layout = self.validLayout {
            self.applyLayout(bounds: CGRect(origin: .zero, size: layout.size), safeArea: layout.safeInsets)
        } else if self.view.bounds.width > 0 && self.view.bounds.height > 0 {
            self.applyLayout(bounds: self.view.bounds, safeArea: self.view.safeAreaInsets)
        }
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.triggerDismissBeginIfNeeded()
    }
    
    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        self.triggerDismissBeginIfNeeded()
        self.onDismiss?()
    }
    
    private func applyLayout(bounds: CGRect, safeArea: UIEdgeInsets) {
        guard bounds.width > 0 && bounds.height > 0 else { return }
        
        self.backgroundImageView.frame = bounds
        self.ambientGradientLayer.frame = bounds
        self.backgroundBlurView.frame = bounds
        self.darkDimOverlay.frame = bounds
        
        let topY = max(safeArea.top, 14.0)
        self.grabberView.frame = CGRect(x: (bounds.width - 38) * 0.5, y: topY + 6, width: 38, height: 5)
        
        let headerY = topY + 20
        self.dismissButton.frame = CGRect(x: 16, y: headerY + 2, width: 32, height: 32)
        self.dismissButton.layer.cornerRadius = 16
        
        // Mode Switcher (Centered)
        let segW: CGFloat = 164.0
        let segH: CGFloat = 32.0
        self.segmentContainerView.frame = CGRect(x: (bounds.width - segW) * 0.5, y: headerY + 2, width: segW, height: segH)
        let itemW = segW * 0.5
        self.nowPlayingSegmentButton.frame = CGRect(x: 0, y: 0, width: itemW, height: segH)
        self.queueSegmentButton.frame = CGRect(x: itemW, y: 0, width: itemW, height: segH)
        
        let indicatorX = self.isQueueMode ? itemW + 2 : 2
        self.segmentIndicatorView.frame = CGRect(x: indicatorX, y: 2, width: itemW - 4, height: segH - 4)
        
        // Source Badge (Right)
        let sourceW: CGFloat = 78.0
        let sourceH: CGFloat = 28.0
        self.sourceBadgeContainer.frame = CGRect(x: bounds.width - sourceW - 16, y: headerY + 4, width: sourceW, height: sourceH)
        self.sourceIconView.frame = CGRect(x: 8, y: 7, width: 14, height: 14)
        self.sourceLabel.frame = CGRect(x: 26, y: 4, width: sourceW - 32, height: 20)
        
        let contentY = headerY + 46.0
        let contentH = bounds.height - contentY - max(safeArea.bottom, 16.0)
        let contentFrame = CGRect(x: 0, y: contentY, width: bounds.width, height: contentH)
        
        self.nowPlayingContainerView.frame = contentFrame
        self.queueContainerView.frame = contentFrame
        
        self.layoutNowPlayingPane(contentH: contentH)
        self.layoutQueuePane(contentH: contentH)
    }
    
    private func layoutNowPlayingPane(contentH: CGFloat) {
        let bounds = self.nowPlayingContainerView.bounds
        guard bounds.width > 0 && bounds.height > 0 else { return }
        
        // Artwork: large square with dynamic height
        let maxArtSide = min(bounds.width - 64, bounds.height * 0.38)
        let artSide = max(160, maxArtSide)
        let artY: CGFloat = 20.0
        let artX = floor((bounds.width - artSide) * 0.5)
        self.artworkContainerView.transform = .identity
        self.artworkContainerView.frame = CGRect(x: artX, y: artY, width: artSide, height: artSide)
        self.artworkImageView.frame = self.artworkContainerView.bounds
        
        let glowSize: CGFloat = artSide * 1.10
        let glowX = artX + (artSide - glowSize) * 0.5
        let glowY = artY + (artSide - glowSize) * 0.5 + 8.0
        self.artworkAmbientGlowView.frame = CGRect(x: glowX, y: glowY, width: glowSize, height: glowSize)
        self.artworkAmbientGlowView.layer.cornerRadius = glowSize * 0.5
        self.artworkGlowGradientLayer.frame = self.artworkAmbientGlowView.bounds
        self.artworkGlowGradientLayer.cornerRadius = glowSize * 0.5
        
        // Info: Title & Artist
        let infoY = artY + artSide + 20.0
        let heartSize: CGFloat = 36.0
        self.infoContainerView.frame = CGRect(x: 32, y: infoY, width: bounds.width - 64, height: 50)
        let titleW = bounds.width - 64 - heartSize - 12
        self.titleLabel.frame = CGRect(x: 0, y: 0, width: titleW, height: 28)
        self.artistLabel.frame = CGRect(x: 0, y: 28, width: titleW, height: 20)
        self.favoriteButton.frame = CGRect(x: bounds.width - 64 - heartSize, y: 7, width: heartSize, height: heartSize)
        
        // Progress Slider
        let sliderY = infoY + 56.0
        self.progressSlider.frame = CGRect(x: 32, y: sliderY, width: bounds.width - 64, height: 26)
        self.currentTimeLabel.frame = CGRect(x: 32, y: sliderY + 22, width: 60, height: 16)
        self.remainingTimeLabel.frame = CGRect(x: bounds.width - 92, y: sliderY + 22, width: 60, height: 16)
        
        // Controls Row: deterministic frame positioning (never collapses)
        let controlsY = sliderY + 44.0
        let controlsW = bounds.width - 48.0
        self.controlsContainerView.frame = CGRect(x: 24, y: controlsY, width: controlsW, height: 68)
        
        let centerX = controlsW * 0.5
        self.playPauseContainer.frame = CGRect(x: centerX - 34.0, y: 0, width: 68.0, height: 68.0)
        self.playPauseButton.frame = self.playPauseContainer.bounds
        
        let skipSize: CGFloat = 44.0
        self.previousButton.frame = CGRect(x: centerX - 34.0 - 24.0 - skipSize, y: (68.0 - skipSize) * 0.5, width: skipSize, height: skipSize)
        self.nextButton.frame = CGRect(x: centerX + 34.0 + 24.0, y: (68.0 - skipSize) * 0.5, width: skipSize, height: skipSize)
        
        let subSize: CGFloat = 40.0
        self.shuffleButton.frame = CGRect(x: 8.0, y: (68.0 - subSize) * 0.5, width: subSize, height: subSize)
        self.repeatButton.frame = CGRect(x: controlsW - 8.0 - subSize, y: (68.0 - subSize) * 0.5, width: subSize, height: subSize)
        
        // Bottom Action Buttons
        let actionsY = controlsY + 76.0
        self.actionsStackView.frame = CGRect(x: 20, y: actionsY, width: bounds.width - 40, height: 36)
    }
    
    private func layoutQueuePane(contentH: CGFloat) {
        let bounds = self.queueContainerView.bounds
        guard bounds.width > 0 && bounds.height > 0 else { return }
        
        // Header
        let headerH: CGFloat = 72.0
        self.queueHeaderView.frame = CGRect(x: 20, y: 4, width: bounds.width - 40, height: headerH)
        
        let countText = self.queueCountLabel.text ?? ""
        let countFont = UIFont.systemFont(ofSize: 11.5, weight: .semibold)
        let countSize = (countText as NSString).size(withAttributes: [.font: countFont])
        let badgeW = max(56.0, countSize.width + 16.0)
        let badgeH: CGFloat = 22.0
        
        self.queueCountLabel.frame = CGRect(x: (bounds.width - 40) - badgeW, y: 4, width: badgeW, height: badgeH)
        self.queueTitleLabel.frame = CGRect(x: 0, y: 2, width: (bounds.width - 40) - badgeW - 8, height: 26)
        
        let row2Y: CGFloat = 36.0
        let btnH: CGFloat = 30.0
        let shuffleW: CGFloat = 118.0
        let clearW: CGFloat = 92.0
        self.queueShuffleButton.frame = CGRect(x: 0, y: row2Y, width: shuffleW, height: btnH)
        self.queueClearButton.frame = CGRect(x: shuffleW + 8.0, y: row2Y, width: clearW, height: btnH)
        
        // Mini Bar at bottom
        let miniH: CGFloat = 54.0
        let miniY = bounds.height - miniH - 10.0
        self.queueMiniBar.frame = CGRect(x: 16, y: miniY, width: bounds.width - 32, height: miniH)
        self.queueMiniBlurView.frame = self.queueMiniBar.bounds
        
        self.queueMiniArtwork.frame = CGRect(x: 7, y: 7, width: 40, height: 40)
        let miniControlsW: CGFloat = 76.0
        let miniPlayX = self.queueMiniBar.bounds.width - miniControlsW
        self.queueMiniPlayPause.frame = CGRect(x: miniPlayX, y: 9, width: 36, height: 36)
        self.queueMiniNext.frame = CGRect(x: miniPlayX + 38, y: 9, width: 34, height: 36)
        
        let miniTextX = self.queueMiniArtwork.frame.maxX + 10
        let miniTextW = max(0, miniPlayX - miniTextX - 6)
        self.queueMiniTitle.frame = CGRect(x: miniTextX, y: 9, width: miniTextW, height: 18)
        self.queueMiniArtist.frame = CGRect(x: miniTextX, y: 28, width: miniTextW, height: 16)
        
        // Table View
        let tableY: CGFloat = 82.0
        self.queueTableView.frame = CGRect(x: 0, y: tableY, width: bounds.width, height: max(60, miniY - tableY - 6))
        self.queueTableView.contentInset = UIEdgeInsets(top: 4, left: 0, bottom: 8, right: 0)
    }
    
    // MARK: - Content Updates
    
    private func updateContent() {
        let manager = SGDoxMusicManager.shared
        guard let track = manager.currentTrack else { return }
        
        let d = manager.duration > 0 ? manager.duration : 30.0
        if !self.isDraggingSlider {
            self.progressSlider.value = Float(manager.currentTime / d)
            self.currentTimeLabel.text = self.formatTime(manager.currentTime)
            self.remainingTimeLabel.text = "-\(self.formatTime(max(0, d - manager.currentTime)))"
        }
        
        if self.displayedTrackId != track.id {
            self.displayedTrackId = track.id
            self.titleLabel.text = track.title
            self.artistLabel.text = track.artist
            
            self.queueMiniTitle.text = track.title
            self.queueMiniArtist.text = track.artist
            
            // Artwork
            self.artworkImageView.image = SGDoxImageLoader.shared.placeholderArtwork()
            self.queueMiniArtwork.image = SGDoxImageLoader.shared.placeholderArtwork()
            
            SGDoxImageLoader.shared.loadArtwork(for: track, targetSize: CGSize(width: 400, height: 400)) { [weak self] image in
                guard let self = self, self.displayedTrackId == track.id, let img = image else { return }
                self.artworkImageView.image = img
                self.queueMiniArtwork.image = img
                self.backgroundImageView.image = img
                self.updateAmbientColor(from: img)
            }
        }
        
        // Source
        switch track.source {
        case .appleMusic:
            self.sourceLabel.text = "Apple"
        case .spotify:
            self.sourceLabel.text = "Spotify"
        case .telegram:
            self.sourceLabel.text = "Telegram"
        }
        self.sourceIconView.image = UIImage(systemName: track.source.iconName)
        
        // Play / Pause Icon
        let playIconName = manager.isPlaying ? "pause.fill" : "play.fill"
        let playCfg = UIImage.SymbolConfiguration(pointSize: 28, weight: .bold)
        self.playPauseButton.setImage(UIImage(systemName: playIconName, withConfiguration: playCfg), for: .normal)
        
        let miniCfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)
        self.queueMiniPlayPause.setImage(UIImage(systemName: playIconName, withConfiguration: miniCfg), for: .normal)
        
        // Favorite
        let isFav = manager.isFavorite(track: track)
        let heartIcon = isFav ? "heart.fill" : "heart"
        let heartCfg = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        self.favoriteButton.setImage(UIImage(systemName: heartIcon, withConfiguration: heartCfg), for: .normal)
        self.favoriteButton.tintColor = isFav ? UIColor(red: 1.0, green: 0.22, blue: 0.38, alpha: 1.0) : UIColor.white.withAlphaComponent(0.8)
        
        // Shuffle
        self.shuffleButton.tintColor = manager.isShuffleEnabled ? UIColor(red: 0.98, green: 0.20, blue: 0.35, alpha: 1.0) : UIColor.white.withAlphaComponent(0.6)
        
        // Repeat
        let repCfg = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        switch manager.repeatMode {
        case .off:
            self.repeatButton.setImage(UIImage(systemName: "repeat", withConfiguration: repCfg), for: .normal)
            self.repeatButton.tintColor = UIColor.white.withAlphaComponent(0.6)
        case .all:
            self.repeatButton.setImage(UIImage(systemName: "repeat", withConfiguration: repCfg), for: .normal)
            self.repeatButton.tintColor = UIColor(red: 0.98, green: 0.20, blue: 0.35, alpha: 1.0)
        case .one:
            self.repeatButton.setImage(UIImage(systemName: "repeat.1", withConfiguration: repCfg), for: .normal)
            self.repeatButton.tintColor = UIColor(red: 0.98, green: 0.20, blue: 0.35, alpha: 1.0)
        }
        
        // Action states
        self.waveButton.backgroundColor = manager.isWaveEnabled ? UIColor(red: 0.95, green: 0.25, blue: 0.50, alpha: 0.85) : UIColor(white: 1.0, alpha: 0.14)
        self.autoplayButton.backgroundColor = manager.isAutoplayEnabled ? UIColor(red: 0.98, green: 0.20, blue: 0.35, alpha: 0.85) : UIColor(white: 1.0, alpha: 0.14)
        
        let isDownloaded = SGDoxMusicOfflineManager.shared.isDownloaded(trackId: track.id)
        let downConfig = UIImage.SymbolConfiguration(pointSize: 11.5, weight: .semibold)
        if isDownloaded {
            self.downloadButton.backgroundColor = UIColor(red: 0.18, green: 0.80, blue: 0.44, alpha: 0.85)
            self.downloadButton.setTitle(" Скачано", for: .normal)
            self.downloadButton.setImage(UIImage(systemName: "checkmark.circle.fill", withConfiguration: downConfig), for: .normal)
        } else {
            self.downloadButton.backgroundColor = UIColor(white: 1.0, alpha: 0.14)
            self.downloadButton.setTitle(" Скачать", for: .normal)
            self.downloadButton.setImage(UIImage(systemName: "arrow.down.circle", withConfiguration: downConfig), for: .normal)
        }
        
        self.updateArtworkScale(isPlaying: manager.isPlaying, animated: true)
    }
    
    private func reloadQueueData() {
        self.cachedQueue = SGDoxMusicManager.shared.effectiveQueue()
        let count = self.cachedQueue.count
        self.queueCountLabel.text = count == 0 ? "Пусто" : "\(count) трек\(self.pluralEnding(count))"
        self.queueClearButton.isHidden = count == 0
        self.queueTableView.reloadData()
        self.view.setNeedsLayout()
    }
    
    private func pluralEnding(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        if mod100 >= 11 && mod100 <= 19 { return "ов" }
        if mod10 == 1 { return "" }
        if mod10 >= 2 && mod10 <= 4 { return "а" }
        return "ов"
    }
    
    private func updateArtworkScale(isPlaying: Bool, animated: Bool) {
        let opacity: Float = isPlaying ? 0.55 : 0.30
        let radius: CGFloat = isPlaying ? 26.0 : 16.0
        if animated {
            let anim = CABasicAnimation(keyPath: "shadowOpacity")
            anim.fromValue = self.artworkContainerView.layer.shadowOpacity
            anim.toValue = opacity
            anim.duration = 0.3
            self.artworkContainerView.layer.add(anim, forKey: "shadowOpacity")
        }
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
                vibrantColor.withAlphaComponent(0.65).cgColor,
                avgColor.withAlphaComponent(0.35).cgColor,
                UIColor.clear.cgColor
            ]
            
            DispatchQueue.main.async {
                guard let self = self else { return }
                let animation = CABasicAnimation(keyPath: "colors")
                animation.fromValue = self.ambientGradientLayer.colors
                animation.toValue = newColors
                animation.duration = 0.7
                self.ambientGradientLayer.add(animation, forKey: "colorsChange")
                self.ambientGradientLayer.colors = newColors
                
                self.artworkContainerView.layer.shadowColor = vibrantColor.cgColor
                
                self.artworkGlowGradientLayer.colors = glowColors
                self.artworkAmbientGlowView.layer.shadowColor = vibrantColor.cgColor
                self.artworkAmbientGlowView.layer.shadowRadius = 32.0
                self.artworkAmbientGlowView.layer.shadowOpacity = 0.65
                self.artworkAmbientGlowView.layer.shadowOffset = CGSize(width: 0, height: 6)
                self.startGlowAnimation()
            }
        }
    }
    
    private func startGlowAnimation() {
        self.artworkAmbientGlowView.layer.removeAnimation(forKey: "glowPulse")
        self.artworkAmbientGlowView.layer.removeAnimation(forKey: "glowAlpha")
        self.artworkAmbientGlowView.layer.removeAnimation(forKey: "glowRadius")
        self.artworkGlowGradientLayer.removeAnimation(forKey: "glowCenterShift")
        
        let pulseAnim = CABasicAnimation(keyPath: "transform.scale")
        pulseAnim.fromValue = 0.98
        pulseAnim.toValue = 1.05
        pulseAnim.duration = 4.2
        pulseAnim.autoreverses = true
        pulseAnim.repeatCount = .infinity
        pulseAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        self.artworkAmbientGlowView.layer.add(pulseAnim, forKey: "glowPulse")
        
        let alphaAnim = CABasicAnimation(keyPath: "opacity")
        alphaAnim.fromValue = 0.70
        alphaAnim.toValue = 0.95
        alphaAnim.duration = 3.5
        alphaAnim.autoreverses = true
        alphaAnim.repeatCount = .infinity
        alphaAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        self.artworkAmbientGlowView.layer.add(alphaAnim, forKey: "glowAlpha")
        
        let radiusAnim = CABasicAnimation(keyPath: "shadowRadius")
        radiusAnim.fromValue = 26.0
        radiusAnim.toValue = 42.0
        radiusAnim.duration = 4.8
        radiusAnim.autoreverses = true
        radiusAnim.repeatCount = .infinity
        radiusAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        self.artworkAmbientGlowView.layer.add(radiusAnim, forKey: "glowRadius")
        
        let shiftAnim = CABasicAnimation(keyPath: "startPoint")
        shiftAnim.fromValue = CGPoint(x: 0.47, y: 0.47)
        shiftAnim.toValue = CGPoint(x: 0.53, y: 0.53)
        shiftAnim.duration = 6.2
        shiftAnim.autoreverses = true
        shiftAnim.repeatCount = .infinity
        shiftAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        self.artworkGlowGradientLayer.add(shiftAnim, forKey: "glowCenterShift")
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let s = Int(seconds)
        let mins = s / 60
        let secs = s % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    // MARK: - Segment Switching (Now Playing vs Queue)
    
    @objc private func nowPlayingSegmentPressed() {
        guard self.isQueueMode else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        self.isQueueMode = false
        self.transitionPanes()
    }
    
    @objc private func queueSegmentPressed() {
        guard !self.isQueueMode else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        self.isQueueMode = true
        self.reloadQueueData()
        self.transitionPanes()
    }
    
    private func transitionPanes() {
        let segW = self.segmentContainerView.bounds.width
        let itemW = segW * 0.5
        let indicatorX = self.isQueueMode ? itemW + 2 : 2
        
        if self.isQueueMode {
            self.queueContainerView.isHidden = false
            self.queueContainerView.alpha = 0.0
            self.queueContainerView.transform = CGAffineTransform(translationX: 30, y: 0)
        } else {
            self.nowPlayingContainerView.isHidden = false
            self.nowPlayingContainerView.alpha = 0.0
            self.nowPlayingContainerView.transform = CGAffineTransform(translationX: -30, y: 0)
        }
        
        UIView.animate(withDuration: 0.32, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.5, options: [.allowUserInteraction], animations: {
            self.segmentIndicatorView.frame = CGRect(x: indicatorX, y: 2, width: itemW - 4, height: self.segmentContainerView.bounds.height - 4)
            
            if self.isQueueMode {
                self.nowPlayingContainerView.alpha = 0.0
                self.nowPlayingContainerView.transform = CGAffineTransform(translationX: -30, y: 0)
                
                self.queueContainerView.alpha = 1.0
                self.queueContainerView.transform = .identity
            } else {
                self.queueContainerView.alpha = 0.0
                self.queueContainerView.transform = CGAffineTransform(translationX: 30, y: 0)
                
                self.nowPlayingContainerView.alpha = 1.0
                self.nowPlayingContainerView.transform = .identity
            }
        }) { _ in
            if self.isQueueMode {
                self.nowPlayingContainerView.isHidden = true
            } else {
                self.queueContainerView.isHidden = true
            }
        }
    }
    
    // MARK: - Actions
    
    @objc private func dismissPressed() {
        self.triggerDismissBeginIfNeeded()
        self.dismiss()
    }
    
    @objc private func favoritePressed() {
        guard let track = SGDoxMusicManager.shared.currentTrack else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        UIView.animate(withDuration: 0.14, animations: {
            self.favoriteButton.transform = CGAffineTransform(scaleX: 1.35, y: 1.35)
        }) { _ in
            UIView.animate(withDuration: 0.14) {
                self.favoriteButton.transform = .identity
            }
        }
        SGDoxMusicManager.shared.toggleFavorite(track: track)
        self.updateContent()
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
    
    @objc private func autoplayPressed() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        SGDoxMusicManager.shared.toggleAutoplay()
        self.updateContent()
        self.reloadQueueData()
    }
    
    @objc private func downloadPressed() {
        guard let track = SGDoxMusicManager.shared.currentTrack else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        let isDown = SGDoxMusicOfflineManager.shared.isDownloaded(trackId: track.id)
        if isDown {
            SGDoxMusicOfflineManager.shared.deleteTrack(trackId: track.id)
            let overlay = UndoOverlayController(presentationData: self.presentationData, content: .actionSucceeded(title: nil, text: "Трек удален из офлайн-памяти", cancel: nil, destructive: false), elevatedLayout: false, action: { _ in return false })
            self.present(overlay, in: .window(.root))
            self.updateContent()
            self.reloadQueueData()
        } else {
            let hud = OverlayStatusController(style: .dark, type: .loading(cancelled: nil))
            self.present(hud, in: .window(.root))
            SGDoxMusicOfflineManager.shared.downloadTrack(track: track) { [weak self, weak hud] success in
                hud?.dismiss()
                guard let self = self else { return }
                if success {
                    let overlay = UndoOverlayController(presentationData: self.presentationData, content: .actionSucceeded(title: nil, text: "Трек сохранен для прослушивания офлайн", cancel: nil, destructive: false), elevatedLayout: false, action: { _ in return false })
                    self.present(overlay, in: .window(.root))
                } else {
                    let overlay = UndoOverlayController(presentationData: self.presentationData, content: .info(title: "Ошибка", text: "Не удалось скачать аудиофайл", timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false })
                    self.present(overlay, in: .window(.root))
                }
                self.updateContent()
                self.reloadQueueData()
            }
        }
    }
    
    @objc private func playPausePressed() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        UIView.animate(withDuration: 0.1, animations: {
            self.playPauseContainer.transform = CGAffineTransform(scaleX: 0.90, y: 0.90)
        }) { _ in
            UIView.animate(withDuration: 0.14) {
                self.playPauseContainer.transform = .identity
            }
        }
        SGDoxMusicManager.shared.togglePlay()
    }
    
    @objc private func nextPressed() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        UIView.animate(withDuration: 0.1, animations: {
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
        UIView.animate(withDuration: 0.1, animations: {
            self.previousButton.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
        }) { _ in
            UIView.animate(withDuration: 0.14) {
                self.previousButton.transform = .identity
            }
        }
        SGDoxMusicManager.shared.previous()
    }
    
    @objc private func sliderValueChanged() {
        self.isDraggingSlider = true
        let duration = SGDoxMusicManager.shared.duration > 0 ? SGDoxMusicManager.shared.duration : 30.0
        let target = Double(self.progressSlider.value) * duration
        self.currentTimeLabel.text = self.formatTime(target)
    }
    
    @objc private func sliderTouchEnded() {
        self.isDraggingSlider = false
        let duration = SGDoxMusicManager.shared.duration > 0 ? SGDoxMusicManager.shared.duration : 30.0
        let target = Double(self.progressSlider.value) * duration
        SGDoxMusicManager.shared.seek(to: target)
    }
    
    @objc private func wavePressed() {
        let manager = SGDoxMusicManager.shared
        manager.isWaveEnabled.toggle()
        if manager.isWaveEnabled {
            manager.startWave()
        }
        self.updateContent()
        self.reloadQueueData()
    }
    
    @objc private func pinToProfilePressed() {
        guard let track = SGDoxMusicManager.shared.currentTrack else { return }
        SGDoxMusicManager.shared.pinCurrentTrackToProfile(context: self.context) { [weak self] success, errorText in
            guard let self = self else { return }
            let text = success ? "Музыка «\(track.title)» закреплена в профиле" : (errorText ?? "Не удалось установить трек в профиль")
            let undoController = UndoOverlayController(
                presentationData: self.presentationData,
                content: .universalImage(
                    image: generateTintedImage(image: UIImage(bundleImageName: "Media Editor/SmallAudio"), color: .white) ?? UIImage(),
                    size: nil,
                    title: nil,
                    text: text,
                    customUndoText: nil,
                    timeout: 3.5
                ),
                elevatedLayout: true,
                action: { _ in return true }
            )
            self.present(undoController, in: .current)
        }
    }
    
    @objc private func queueShufflePressed() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        SGDoxMusicManager.shared.toggleShuffle()
        self.reloadQueueData()
    }
    
    @objc private func queueClearPressed() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if let current = SGDoxMusicManager.shared.currentTrack {
            SGDoxMusicManager.shared.play(track: current, queue: [])
        }
        self.reloadQueueData()
    }
    
    // MARK: - Table View (Queue)
    
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.cachedQueue.count
    }
    
    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 60.0
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SGDoxPlayerQueueCell", for: indexPath) as! SGDoxPlayerQueueCell
        let track = self.cachedQueue[indexPath.row]
        cell.configure(track: track)
        return cell
    }
    
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.row < self.cachedQueue.count else { return }
        let selectedTrack = self.cachedQueue[indexPath.row]
        let remaining = Array(self.cachedQueue.suffix(from: indexPath.row + 1))
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        SGDoxMusicManager.shared.play(track: selectedTrack, queue: remaining)
        self.reloadQueueData()
    }
}

// MARK: - In-Player Queue Cell

private final class SGDoxPlayerQueueCell: UITableViewCell {
    private let artworkImageView = UIImageView()
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    private let durationLabel = UILabel()
    private let sourceIconView = UIImageView()
    private let downloadedBadge = UIImageView()
    private var currentTrackId: String?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        self.backgroundColor = .clear
        self.selectionStyle = .none
        
        self.artworkImageView.contentMode = .scaleAspectFill
        self.artworkImageView.clipsToBounds = true
        self.artworkImageView.layer.cornerRadius = 10
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
        
        let downCfg = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        self.downloadedBadge.image = UIImage(systemName: "arrow.down.circle.fill", withConfiguration: downCfg)
        self.downloadedBadge.tintColor = UIColor(red: 0.18, green: 0.80, blue: 0.44, alpha: 0.90)
        self.downloadedBadge.contentMode = .scaleAspectFit
        self.downloadedBadge.isHidden = true
        self.contentView.addSubview(self.downloadedBadge)
        
        self.durationLabel.textColor = UIColor(white: 1.0, alpha: 0.45)
        self.durationLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .regular)
        self.durationLabel.textAlignment = .right
        self.contentView.addSubview(self.durationLabel)
        
        self.sourceIconView.contentMode = .scaleAspectFit
        self.sourceIconView.tintColor = UIColor(white: 1.0, alpha: 0.45)
        self.contentView.addSubview(self.sourceIconView)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(track: SGDoxMusicTrack) {
        self.currentTrackId = track.id
        self.titleLabel.text = track.title
        self.artistLabel.text = track.artist
        
        let isDown = SGDoxMusicOfflineManager.shared.isDownloaded(trackId: track.id)
        self.downloadedBadge.isHidden = !isDown
        
        let d = Int(track.duration)
        self.durationLabel.text = d > 0 ? String(format: "%d:%02d", d / 60, d % 60) : ""
        self.sourceIconView.image = UIImage(systemName: track.source.iconName)
        
        self.artworkImageView.image = SGDoxImageLoader.shared.placeholderArtwork()
        SGDoxImageLoader.shared.loadArtwork(for: track, targetSize: CGSize(width: 88, height: 88)) { [weak self] image in
            if self?.currentTrackId == track.id, let img = image {
                self?.artworkImageView.image = img
            }
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        let b = self.contentView.bounds
        let artSide: CGFloat = 44.0
        self.artworkImageView.frame = CGRect(x: 18, y: (b.height - artSide) * 0.5, width: artSide, height: artSide)
        
        let rightMargin: CGFloat = 18.0
        let durW: CGFloat = 46.0
        self.durationLabel.frame = CGRect(x: b.width - rightMargin - durW, y: (b.height - 18) * 0.5, width: durW, height: 18)
        
        let iconSize: CGFloat = 14.0
        self.sourceIconView.frame = CGRect(x: self.durationLabel.frame.minX - iconSize - 6, y: (b.height - iconSize) * 0.5, width: iconSize, height: iconSize)
        
        let textX = self.artworkImageView.frame.maxX + 12.0
        let textW = max(0, self.sourceIconView.frame.minX - textX - 8.0)
        self.titleLabel.frame = CGRect(x: textX, y: 11, width: textW, height: 20)
        
        if !self.downloadedBadge.isHidden {
            self.downloadedBadge.frame = CGRect(x: textX, y: 34, width: 13, height: 13)
            self.artistLabel.frame = CGRect(x: textX + 17, y: 31, width: textW - 17, height: 18)
        } else {
            self.artistLabel.frame = CGRect(x: textX, y: 31, width: textW, height: 18)
        }
    }
}
