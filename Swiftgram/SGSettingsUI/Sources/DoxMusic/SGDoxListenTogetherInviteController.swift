import Foundation
import UIKit
import Display
import TelegramCore
import AccountContext
import TelegramPresentationData
import SGSimpleSettings

public final class SGDoxListenTogetherInviteController: ViewController {
    private let context: AccountContext
    private var currentSession: SGDoxListenTogetherSessionInfo
    private var presentationData: PresentationData
    
    // MARK: - UI Elements
    private let dimmingView = UIView()
    private let cardContainer = UIView()
    private let blurView = UIVisualEffectView()
    private let sheenGradient = CAGradientLayer()
    private let artworkGlowView = UIView()
    private let artworkGlowLayer = CAGradientLayer()
    
    private let closeButton = UIButton(type: .system)
    private let headerBadgeContainer = UIView()
    private let headerBadgeIcon = UIImageView()
    private let headerBadgeLabel = UILabel()
    
    private let senderLabel = UILabel()
    private let artworkImageView = UIImageView()
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    private let statusPill = UIView()
    private let statusDot = UIView()
    private let statusLabel = UILabel()
    
    private let joinButton = UIButton(type: .system)
    private let joinGradientLayer = CAGradientLayer()
    private let declineButton = UIButton(type: .system)
    
    private var elapsedTimer: Foundation.Timer?
    private var hasAnimatedIn = false
    
    public init(context: AccountContext, session: SGDoxListenTogetherSessionInfo) {
        self.context = context
        self.currentSession = session
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
        self.elapsedTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
    
    public override func loadDisplayNode() {
        super.loadDisplayNode()
        self.displayNode.backgroundColor = .clear
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .clear
        
        self.setupViews()
        self.updateSessionContent(animated: false)
        
        // Listen for real-time dynamic track changes while invite is open
        NotificationCenter.default.addObserver(self, selector: #selector(self.sessionUpdatedNotification(_:)), name: NSNotification.Name("SGDoxListenTogetherUpdated"), object: nil)
        
        // Timer to update live playback elapsed time every second
        self.elapsedTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateLiveStatus()
        }
        
        // Pan gesture to swipe down card
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(self.handlePanGesture(_:)))
        self.cardContainer.addGestureRecognizer(panGesture)
        
        // Initial offscreen transform
        self.dimmingView.alpha = 0.0
        let screenHeight = UIScreen.main.bounds.height
        self.cardContainer.transform = CGAffineTransform(translationX: 0, y: screenHeight > 0 ? screenHeight : 800)
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !self.hasAnimatedIn {
            self.hasAnimatedIn = true
            UIView.animate(withDuration: 0.38, delay: 0, usingSpringWithDamping: 0.84, initialSpringVelocity: 0.4, options: [.curveEaseOut, .allowUserInteraction], animations: {
                self.dimmingView.alpha = 1.0
                self.cardContainer.transform = .identity
            }, completion: nil)
        }
    }
    
    // MARK: - Setup Views
    
    private func setupViews() {
        // Dimming backdrop
        self.dimmingView.backgroundColor = UIColor(white: 0.0, alpha: 0.60)
        let tapDim = UITapGestureRecognizer(target: self, action: #selector(self.declinePressed))
        self.dimmingView.addGestureRecognizer(tapDim)
        self.view.addSubview(self.dimmingView)
        
        // Liquid Glass Card
        self.cardContainer.layer.cornerRadius = 32.0
        self.cardContainer.layer.cornerCurve = .continuous
        self.cardContainer.layer.borderWidth = 0.75
        self.cardContainer.layer.borderColor = UIColor(white: 1.0, alpha: 0.28).cgColor
        self.cardContainer.clipsToBounds = true
        self.cardContainer.backgroundColor = UIColor(red: 0.10, green: 0.11, blue: 0.16, alpha: 0.82)
        
        self.blurView.effect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        self.cardContainer.addSubview(self.blurView)
        
        // Specular Sheen Layer
        self.sheenGradient.colors = [
            UIColor(white: 1.0, alpha: 0.38).cgColor,
            UIColor(white: 1.0, alpha: 0.08).cgColor,
            UIColor.clear.cgColor
        ]
        self.sheenGradient.locations = [0.0, 0.35, 1.0]
        self.sheenGradient.startPoint = CGPoint(x: 0.5, y: 0.0)
        self.sheenGradient.endPoint = CGPoint(x: 0.5, y: 1.0)
        self.cardContainer.layer.addSublayer(self.sheenGradient)
        
        // Artwork ambient aura glow
        self.artworkGlowLayer.type = .radial
        self.artworkGlowLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        self.artworkGlowLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        self.artworkGlowLayer.colors = [
            UIColor(red: 0.85, green: 0.22, blue: 0.45, alpha: 0.55).cgColor,
            UIColor(red: 0.35, green: 0.18, blue: 0.85, alpha: 0.35).cgColor,
            UIColor.clear.cgColor
        ]
        self.artworkGlowView.layer.addSublayer(self.artworkGlowLayer)
        self.cardContainer.addSubview(self.artworkGlowView)
        
        // Close Button
        let xConfig = UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        self.closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: xConfig), for: .normal)
        self.closeButton.tintColor = UIColor(white: 1.0, alpha: 0.80)
        self.closeButton.backgroundColor = UIColor(white: 1.0, alpha: 0.12)
        self.closeButton.layer.cornerRadius = 16
        self.closeButton.clipsToBounds = true
        self.closeButton.addTarget(self, action: #selector(self.declinePressed), for: .touchUpInside)
        self.cardContainer.addSubview(self.closeButton)
        
        // Header Badge: [ 🎧 Совместное прослушивание ]
        self.headerBadgeContainer.backgroundColor = UIColor(white: 1.0, alpha: 0.14)
        self.headerBadgeContainer.layer.cornerRadius = 14
        self.headerBadgeContainer.layer.cornerCurve = .continuous
        self.headerBadgeContainer.layer.borderWidth = 0.5
        self.headerBadgeContainer.layer.borderColor = UIColor(white: 1.0, alpha: 0.22).cgColor
        self.headerBadgeContainer.clipsToBounds = true
        self.cardContainer.addSubview(self.headerBadgeContainer)
        
        let waveConfig = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        self.headerBadgeIcon.image = UIImage(systemName: "headphones", withConfiguration: waveConfig)
        self.headerBadgeIcon.tintColor = UIColor(red: 0.45, green: 0.78, blue: 1.0, alpha: 1.0)
        self.headerBadgeIcon.contentMode = .scaleAspectFit
        self.headerBadgeContainer.addSubview(self.headerBadgeIcon)
        
        self.headerBadgeLabel.text = "Слушать вместе"
        self.headerBadgeLabel.font = UIFont.systemFont(ofSize: 12.5, weight: .semibold)
        self.headerBadgeLabel.textColor = .white
        self.headerBadgeContainer.addSubview(self.headerBadgeLabel)
        
        // Sender Title
        self.senderLabel.font = UIFont.systemFont(ofSize: 14.5, weight: .medium)
        self.senderLabel.textColor = UIColor(white: 1.0, alpha: 0.75)
        self.senderLabel.textAlignment = .center
        self.senderLabel.numberOfLines = 2
        self.cardContainer.addSubview(self.senderLabel)
        
        // Artwork
        self.artworkImageView.contentMode = .scaleAspectFill
        self.artworkImageView.clipsToBounds = true
        self.artworkImageView.layer.cornerRadius = 24.0
        self.artworkImageView.layer.cornerCurve = .continuous
        self.artworkImageView.layer.borderWidth = 1.0
        self.artworkImageView.layer.borderColor = UIColor(white: 1.0, alpha: 0.25).cgColor
        self.artworkImageView.backgroundColor = UIColor(white: 0.20, alpha: 1.0)
        self.cardContainer.addSubview(self.artworkImageView)
        
        // Track Title & Artist
        self.titleLabel.font = UIFont.systemFont(ofSize: 18.0, weight: .bold)
        self.titleLabel.textColor = .white
        self.titleLabel.textAlignment = .center
        self.titleLabel.lineBreakMode = .byTruncatingTail
        self.cardContainer.addSubview(self.titleLabel)
        
        self.artistLabel.font = UIFont.systemFont(ofSize: 14.5, weight: .medium)
        self.artistLabel.textColor = UIColor(white: 1.0, alpha: 0.68)
        self.artistLabel.textAlignment = .center
        self.artistLabel.lineBreakMode = .byTruncatingTail
        self.cardContainer.addSubview(self.artistLabel)
        
        // Live status pill: [ 🟢 Сейчас играет • 0:42 ]
        self.statusPill.backgroundColor = UIColor(white: 1.0, alpha: 0.10)
        self.statusPill.layer.cornerRadius = 12.0
        self.statusPill.clipsToBounds = true
        self.cardContainer.addSubview(self.statusPill)
        
        self.statusDot.backgroundColor = UIColor(red: 0.25, green: 0.88, blue: 0.45, alpha: 1.0)
        self.statusDot.layer.cornerRadius = 4.0
        self.statusPill.addSubview(self.statusDot)
        
        self.statusLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
        self.statusLabel.textColor = UIColor(white: 1.0, alpha: 0.85)
        self.statusPill.addSubview(self.statusLabel)
        
        // Primary Join Button
        self.joinButton.layer.cornerRadius = 24.0
        self.joinButton.layer.cornerCurve = .continuous
        self.joinButton.clipsToBounds = true
        
        self.joinGradientLayer.colors = [
            UIColor(red: 0.20, green: 0.55, blue: 0.98, alpha: 1.0).cgColor,
            UIColor(red: 0.12, green: 0.38, blue: 0.92, alpha: 1.0).cgColor
        ]
        self.joinGradientLayer.startPoint = CGPoint(x: 0.0, y: 0.5)
        self.joinGradientLayer.endPoint = CGPoint(x: 1.0, y: 0.5)
        self.joinButton.layer.insertSublayer(self.joinGradientLayer, at: 0)
        
        let playConfig = UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)
        self.joinButton.setImage(UIImage(systemName: "play.fill", withConfiguration: playConfig), for: .normal)
        self.joinButton.setTitle("  Присоединиться", for: .normal)
        self.joinButton.setTitleColor(.white, for: .normal)
        self.joinButton.titleLabel?.font = UIFont.systemFont(ofSize: 16.0, weight: .bold)
        self.joinButton.tintColor = .white
        self.joinButton.addTarget(self, action: #selector(self.joinPressed), for: .touchUpInside)
        self.cardContainer.addSubview(self.joinButton)
        
        // Secondary Decline Button
        self.declineButton.setTitle("Не сейчас", for: .normal)
        self.declineButton.setTitleColor(UIColor(white: 1.0, alpha: 0.65), for: .normal)
        self.declineButton.titleLabel?.font = UIFont.systemFont(ofSize: 14.5, weight: .medium)
        self.declineButton.addTarget(self, action: #selector(self.declinePressed), for: .touchUpInside)
        self.cardContainer.addSubview(self.declineButton)
        
        self.view.addSubview(self.cardContainer)
    }
    
    // MARK: - Layout
    
    public override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let bounds = CGRect(origin: .zero, size: layout.size)
        self.dimmingView.frame = bounds
        
        let cardWidth = min(bounds.width - 40.0, 340.0)
        let cardHeight: CGFloat = 460.0
        let cardX = (bounds.width - cardWidth) * 0.5
        let cardY = (bounds.height - cardHeight) * 0.5
        
        self.cardContainer.frame = CGRect(x: cardX, y: cardY, width: cardWidth, height: cardHeight)
        self.blurView.frame = self.cardContainer.bounds
        self.sheenGradient.frame = CGRect(x: 0, y: 0, width: cardWidth, height: 160.0)
        
        self.closeButton.frame = CGRect(x: cardWidth - 44.0, y: 14.0, width: 32.0, height: 32.0)
        
        // Badge
        let badgeW: CGFloat = 145.0
        let badgeH: CGFloat = 28.0
        self.headerBadgeContainer.frame = CGRect(x: (cardWidth - badgeW) * 0.5, y: 20.0, width: badgeW, height: badgeH)
        self.headerBadgeIcon.frame = CGRect(x: 10, y: 6, width: 16, height: 16)
        self.headerBadgeLabel.frame = CGRect(x: 32, y: 4, width: badgeW - 36, height: 20)
        
        // Sender Label
        self.senderLabel.frame = CGRect(x: 20, y: self.headerBadgeContainer.frame.maxY + 10, width: cardWidth - 40, height: 22)
        
        // Artwork & Glow
        let artSide: CGFloat = 140.0
        let artX = (cardWidth - artSide) * 0.5
        let artY = self.senderLabel.frame.maxY + 14.0
        self.artworkImageView.frame = CGRect(x: artX, y: artY, width: artSide, height: artSide)
        self.artworkGlowView.frame = CGRect(x: artX - 30, y: artY - 30, width: artSide + 60, height: artSide + 60)
        self.artworkGlowLayer.frame = self.artworkGlowView.bounds
        
        // Title & Artist
        self.titleLabel.frame = CGRect(x: 16, y: self.artworkImageView.frame.maxY + 14, width: cardWidth - 32, height: 22)
        self.artistLabel.frame = CGRect(x: 16, y: self.titleLabel.frame.maxY + 3, width: cardWidth - 32, height: 18)
        
        // Live status pill
        let statusW: CGFloat = 170.0
        let statusH: CGFloat = 24.0
        self.statusPill.frame = CGRect(x: (cardWidth - statusW) * 0.5, y: self.artistLabel.frame.maxY + 10, width: statusW, height: statusH)
        self.statusDot.frame = CGRect(x: 12, y: 8, width: 8, height: 8)
        self.statusLabel.frame = CGRect(x: 26, y: 3, width: statusW - 32, height: 18)
        
        // Buttons
        let btnH: CGFloat = 48.0
        self.joinButton.frame = CGRect(x: 24, y: cardHeight - btnH - 52.0, width: cardWidth - 48, height: btnH)
        self.joinGradientLayer.frame = self.joinButton.bounds
        
        self.declineButton.frame = CGRect(x: 24, y: cardHeight - 44.0, width: cardWidth - 48, height: 34.0)
    }
    
    // MARK: - Content Updates
    
    private func updateSessionContent(animated: Bool) {
        let sender = self.currentSession.senderName ?? "Собеседник"
        self.senderLabel.text = "\(sender) приглашает слушать:"
        
        if animated {
            UIView.transition(with: self.titleLabel, duration: 0.25, options: [.transitionCrossDissolve], animations: {
                self.titleLabel.text = self.currentSession.title
            }, completion: nil)
            
            UIView.transition(with: self.artistLabel, duration: 0.25, options: [.transitionCrossDissolve], animations: {
                self.artistLabel.text = self.currentSession.artist
            }, completion: nil)
        } else {
            self.titleLabel.text = self.currentSession.title
            self.artistLabel.text = self.currentSession.artist
        }
        
        self.updateLiveStatus()
        
        // Load artwork
        let placeholder = SGDoxImageLoader.shared.placeholderArtwork()
        self.artworkImageView.image = placeholder
        
        let dummyTrack = SGDoxMusicTrack(
            id: self.currentSession.trackId,
            title: self.currentSession.title,
            artist: self.currentSession.artist,
            duration: 0,
            service: .appleMusic,
            artworkUrl: self.currentSession.artworkUrl ?? "",
            previewUrl: nil
        )
        SGDoxImageLoader.shared.loadArtwork(for: dummyTrack, targetSize: CGSize(width: 280, height: 280)) { [weak self] image in
            guard let self = self, let image = image else { return }
            if animated {
                UIView.transition(with: self.artworkImageView, duration: 0.3, options: [.transitionCrossDissolve], animations: {
                    self.artworkImageView.image = image
                }, completion: nil)
            } else {
                self.artworkImageView.image = image
            }
        }
    }
    
    private func updateLiveStatus() {
        let elapsed = max(0, Int(Date().timeIntervalSince1970) - Int(self.currentSession.timestamp))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        self.statusLabel.text = String(format: "В эфире: %d:%02d", minutes, seconds)
    }
    
    @objc private func sessionUpdatedNotification(_ notification: Notification) {
        guard let peerId = notification.userInfo?["peerId"] as? EnginePeer.Id, peerId == self.currentSession.peerId else {
            return
        }
        guard let latest = SGDoxListenTogetherManager.shared.latestInvitesByPeer[peerId] else { return }
        
        if latest.trackId != self.currentSession.trackId || latest.title != self.currentSession.title {
            self.currentSession = latest
            DispatchQueue.main.async { [weak self] in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                self?.updateSessionContent(animated: true)
            }
        }
    }
    
    // MARK: - Actions
    
    @objc private func joinPressed() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let session = self.currentSession
        self.dismissWithSlideDown {
            SGDoxListenTogetherManager.shared.joinAndPlay(session: session)
        }
    }
    
    @objc private func declinePressed() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        self.dismissWithSlideDown(completion: nil)
    }
    
    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self.view)
        let velocity = gesture.velocity(in: self.view)
        
        switch gesture.state {
        case .changed:
            if translation.y > 0 {
                self.cardContainer.transform = CGAffineTransform(translationX: 0, y: translation.y)
                let alpha = max(0.0, 1.0 - translation.y / 300.0)
                self.dimmingView.alpha = alpha
            }
        case .ended, .cancelled:
            if translation.y > 100 || velocity.y > 600 {
                self.dismissWithSlideDown(completion: nil)
            } else {
                UIView.animate(withDuration: 0.28, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0.4, options: [.allowUserInteraction], animations: {
                    self.cardContainer.transform = .identity
                    self.dimmingView.alpha = 1.0
                }, completion: nil)
            }
        default:
            break
        }
    }
    
    private func dismissWithSlideDown(completion: (() -> Void)?) {
        let screenHeight = self.view.bounds.height > 0 ? self.view.bounds.height : 800.0
        UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseIn], animations: {
            self.cardContainer.transform = CGAffineTransform(translationX: 0, y: screenHeight)
            self.dimmingView.alpha = 0.0
        }) { [weak self] _ in
            guard let self = self else { return }
            self.dismiss(animated: false, completion: completion)
        }
    }
}
