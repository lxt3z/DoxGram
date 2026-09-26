import Foundation
import UIKit
import Display
import TelegramPresentationData
import AccountContext
import AppBundle

@MainActor
public final class SGDoxFloatingPlayerWidget: UIView {
    private let context: AccountContext
    private var theme: PresentationTheme
    
    public var openPlayer: (() -> Void)?
    
    private let containerView = UIView()
    private let blurView = UIVisualEffectView()
    private let tintOverlayView = UIView()
    
    private let artworkImageView = UIImageView()
    private let textContainerView = UIView()
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    
    private let playPauseContainer = UIView()
    private let playPauseButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    
    private let progressView = UIProgressView(progressViewStyle: .default)
    
    private var isHiddenForSubscreens = false
    private var currentTrackId: String?
    private var stateToken: UUID?
    private var timeToken: UUID?
    
    public init(context: AccountContext) {
        self.context = context
        self.theme = context.sharedContext.currentPresentationData.with { $0.theme }
        super.init(frame: .zero)
        
        self.setupViews()
        self.applyTheme()
        self.setupListeners()
        self.updateContent(animated: false)
    }
    
    required init?(coder: NSCoder) {
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
    
    private func setupViews() {
        self.backgroundColor = .clear
        self.layer.zPosition = 1000.0
        
        self.containerView.clipsToBounds = true
        self.containerView.layer.cornerRadius = 27.0
        self.containerView.layer.cornerCurve = .continuous
        self.containerView.layer.borderWidth = 0.5
        self.addSubview(self.containerView)
        
        self.containerView.addSubview(self.blurView)
        self.containerView.addSubview(self.tintOverlayView)
        
        // Tap gesture to open player
        let tap = UITapGestureRecognizer(target: self, action: #selector(self.widgetTapped))
        self.addGestureRecognizer(tap)
        
        // Swipe down to dismiss
        let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(self.handleSwipeDown))
        swipeDown.direction = .down
        self.addGestureRecognizer(swipeDown)
        
        // Swipe left for next track
        let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(self.handleSwipeLeft))
        swipeLeft.direction = .left
        self.addGestureRecognizer(swipeLeft)
        
        // Swipe right for previous track
        let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(self.handleSwipeRight))
        swipeRight.direction = .right
        self.addGestureRecognizer(swipeRight)
        
        // Artwork
        self.artworkImageView.contentMode = .scaleAspectFill
        self.artworkImageView.clipsToBounds = true
        self.artworkImageView.layer.cornerRadius = 12.0
        self.artworkImageView.layer.cornerCurve = .continuous
        self.artworkImageView.layer.borderWidth = 0.5
        self.containerView.addSubview(self.artworkImageView)
        
        // Labels
        self.textContainerView.isUserInteractionEnabled = false
        self.titleLabel.font = UIFont.systemFont(ofSize: 13.5, weight: .semibold)
        self.titleLabel.lineBreakMode = .byTruncatingTail
        self.textContainerView.addSubview(self.titleLabel)
        
        self.artistLabel.font = UIFont.systemFont(ofSize: 11.5, weight: .regular)
        self.artistLabel.lineBreakMode = .byTruncatingTail
        self.textContainerView.addSubview(self.artistLabel)
        
        self.containerView.addSubview(self.textContainerView)
        
        // Play / Pause Button with circular background
        self.playPauseContainer.layer.cornerRadius = 17.0
        self.playPauseContainer.layer.cornerCurve = .continuous
        self.playPauseContainer.clipsToBounds = true
        self.containerView.addSubview(self.playPauseContainer)
        
        let playConfig = UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)
        self.playPauseButton.setImage(UIImage(systemName: "play.fill", withConfiguration: playConfig), for: .normal)
        self.playPauseButton.addTarget(self, action: #selector(self.playPausePressed), for: .touchUpInside)
        self.playPauseContainer.addSubview(self.playPauseButton)
        
        // Next Button
        let nextConfig = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        self.nextButton.setImage(UIImage(systemName: "forward.fill", withConfiguration: nextConfig), for: .normal)
        self.nextButton.addTarget(self, action: #selector(self.nextPressed), for: .touchUpInside)
        self.containerView.addSubview(self.nextButton)
        
        // Close Button
        let closeConfig = UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)
        self.closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: closeConfig), for: .normal)
        self.closeButton.layer.cornerRadius = 14.0
        self.closeButton.layer.cornerCurve = .continuous
        self.closeButton.clipsToBounds = true
        self.closeButton.addTarget(self, action: #selector(self.closePressed), for: .touchUpInside)
        self.containerView.addSubview(self.closeButton)
        
        // Progress View
        self.progressView.layer.cornerRadius = 1.0
        self.progressView.clipsToBounds = true
        self.containerView.addSubview(self.progressView)
    }
    
    private func applyTheme() {
        let isDark = self.theme.overallDarkAppearance
        
        self.blurView.effect = UIBlurEffect(style: isDark ? .systemUltraThinMaterialDark : .systemUltraThinMaterialLight)
        
        if isDark {
            self.tintOverlayView.backgroundColor = UIColor(white: 0.05, alpha: 0.20)
            self.containerView.layer.borderColor = UIColor(white: 1.0, alpha: 0.14).cgColor
            self.containerView.layer.borderWidth = 0.5
            self.layer.shadowColor = UIColor.black.cgColor
            self.layer.shadowOpacity = 0.25
            self.layer.shadowRadius = 18
            self.layer.shadowOffset = CGSize(width: 0, height: 6)
            
            self.titleLabel.textColor = .white
            self.artistLabel.textColor = UIColor.white.withAlphaComponent(0.65)
            
            self.playPauseContainer.backgroundColor = UIColor(white: 1.0, alpha: 0.14)
            self.playPauseButton.tintColor = .white
            self.nextButton.tintColor = UIColor.white.withAlphaComponent(0.85)
            self.closeButton.backgroundColor = UIColor(white: 1.0, alpha: 0.08)
            self.closeButton.tintColor = UIColor.white.withAlphaComponent(0.65)
            
            self.artworkImageView.backgroundColor = UIColor(white: 0.15, alpha: 1.0)
            self.artworkImageView.layer.borderColor = UIColor(white: 1.0, alpha: 0.12).cgColor
            
            self.progressView.trackTintColor = UIColor(white: 1.0, alpha: 0.08)
            self.progressView.progressTintColor = UIColor.white.withAlphaComponent(0.85)
        } else {
            self.tintOverlayView.backgroundColor = UIColor(white: 1.0, alpha: 0.15)
            self.containerView.layer.borderColor = UIColor(white: 0.0, alpha: 0.08).cgColor
            self.containerView.layer.borderWidth = 0.5
            self.layer.shadowColor = UIColor.black.cgColor
            self.layer.shadowOpacity = 0.10
            self.layer.shadowRadius = 16
            self.layer.shadowOffset = CGSize(width: 0, height: 4)
            
            let darkText = UIColor(red: 0.08, green: 0.08, blue: 0.11, alpha: 1.0)
            self.titleLabel.textColor = darkText
            self.artistLabel.textColor = UIColor(red: 0.44, green: 0.46, blue: 0.50, alpha: 1.0)
            
            self.playPauseContainer.backgroundColor = UIColor(white: 0.0, alpha: 0.06)
            self.playPauseButton.tintColor = darkText
            self.nextButton.tintColor = UIColor(red: 0.30, green: 0.32, blue: 0.36, alpha: 1.0)
            self.closeButton.backgroundColor = UIColor(white: 0.0, alpha: 0.05)
            self.closeButton.tintColor = UIColor(red: 0.45, green: 0.47, blue: 0.52, alpha: 1.0)
            
            self.artworkImageView.backgroundColor = UIColor(white: 0.90, alpha: 1.0)
            self.artworkImageView.layer.borderColor = UIColor(white: 0.0, alpha: 0.06).cgColor
            
            self.progressView.trackTintColor = UIColor(white: 0.0, alpha: 0.06)
            self.progressView.progressTintColor = self.theme.list.itemAccentColor
        }
    }
    
    private func setupListeners() {
        self.stateToken = SGDoxMusicManager.shared.addStateListener { [weak self] in
            DispatchQueue.main.async {
                self?.updateContent(animated: true)
            }
        }
        
        self.timeToken = SGDoxMusicManager.shared.addTimeListener { [weak self] current, duration in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let d = duration > 0 ? duration : 30.0
                self.progressView.setProgress(Float(current / d), animated: false)
            }
        }
    }
    
    public func updateTheme(_ theme: PresentationTheme) {
        self.theme = theme
        self.applyTheme()
    }
    
    public func setHiddenForSubscreens(_ hidden: Bool) {
        guard self.isHiddenForSubscreens != hidden else { return }
        self.isHiddenForSubscreens = hidden
        self.updateVisibility(animated: true)
    }
    
    public func updateLayout(size: CGSize, insets: UIEdgeInsets, transition: ContainedViewLayoutTransition) {
        let widgetHeight: CGFloat = 54.0
        let horizontalMargin: CGFloat = 16.0
        let widgetWidth = min(size.width - horizontalMargin * 2.0, 420.0)
        let x = floor((size.width - widgetWidth) * 0.5)
        
        // Find actual tab bar in view hierarchy if possible
        var tabBarTop: CGFloat?
        if let superview = self.superview {
            func findTabBar(in view: UIView) -> UIView? {
                for sub in view.subviews {
                    if sub !== self && !sub.isHidden && sub.alpha > 0.05 {
                        let name = String(reflecting: type(of: sub))
                        let simpleName = String(describing: type(of: sub))
                        if (name.contains("TabBar") || simpleName.contains("TabBar") || name.contains("tabBar") || simpleName.contains("tabBar") || name.contains("GlassBackground") || name.contains("GlassControlPanel")) && sub.frame.height > 20.0 {
                            let converted = view.convert(sub.frame, to: superview)
                            if converted.minY > size.height * 0.4 && converted.height < 140.0 {
                                return sub
                            }
                        }
                        if let child = findTabBar(in: sub) {
                            return child
                        }
                    }
                }
                return nil
            }
            if let tb = findTabBar(in: superview) {
                let converted = tb.superview?.convert(tb.frame, to: superview) ?? tb.frame
                if converted.minY > size.height * 0.4 {
                    tabBarTop = converted.minY
                }
            }
        }
        
        let spacing: CGFloat = 10.0
        let y: CGFloat
        if let tbTop = tabBarTop, tbTop > size.height * 0.4 {
            y = tbTop - widgetHeight - spacing
        } else {
            let windowBottom = self.window?.safeAreaInsets.bottom ?? 0.0
            let bottomInset = max(insets.bottom, windowBottom)
            let actualBottom = bottomInset > 0.0 ? bottomInset : 34.0
            let tabIslandHeight: CGFloat = 64.0
            y = size.height - actualBottom - tabIslandHeight - widgetHeight - spacing
        }
        
        let targetFrame = CGRect(x: x, y: y, width: widgetWidth, height: widgetHeight)
        
        if transition.isAnimated {
            transition.updateFrame(view: self, frame: targetFrame)
        } else {
            self.frame = targetFrame
        }
        
        self.containerView.frame = self.bounds
        self.containerView.layer.cornerRadius = widgetHeight * 0.5
        self.blurView.frame = self.bounds
        self.tintOverlayView.frame = self.bounds
        
        // Artwork
        let artSide: CGFloat = 38.0
        self.artworkImageView.frame = CGRect(x: 8.0, y: (widgetHeight - artSide) * 0.5, width: artSide, height: artSide)
        self.artworkImageView.layer.cornerRadius = 11.0
        
        // Right Controls: [playPause] [next] [close]
        let closeSize: CGFloat = 26.0
        let nextSize: CGFloat = 30.0
        let playSize: CGFloat = 34.0
        
        let closeX = widgetWidth - closeSize - 10.0
        let nextX = closeX - nextSize - 6.0
        let playX = nextX - playSize - 4.0
        
        self.closeButton.frame = CGRect(x: closeX, y: (widgetHeight - closeSize) * 0.5, width: closeSize, height: closeSize)
        self.closeButton.layer.cornerRadius = closeSize * 0.5
        
        self.nextButton.frame = CGRect(x: nextX, y: (widgetHeight - nextSize) * 0.5, width: nextSize, height: nextSize)
        
        self.playPauseContainer.frame = CGRect(x: playX, y: (widgetHeight - playSize) * 0.5, width: playSize, height: playSize)
        self.playPauseContainer.layer.cornerRadius = playSize * 0.5
        self.playPauseButton.frame = self.playPauseContainer.bounds
        
        // Text Container
        let textX = self.artworkImageView.frame.maxX + 10.0
        let textWidth = max(0, playX - textX - 8.0)
        let textHeight: CGFloat = 34.0
        self.textContainerView.frame = CGRect(x: textX, y: (widgetHeight - textHeight) * 0.5, width: textWidth, height: textHeight)
        self.titleLabel.frame = CGRect(x: 0, y: 0, width: textWidth, height: 18)
        self.artistLabel.frame = CGRect(x: 0, y: 17, width: textWidth, height: 16)
        
        // Progress Bar
        self.progressView.frame = CGRect(x: 20.0, y: widgetHeight - 3.0, width: widgetWidth - 40.0, height: 1.5)
        self.progressView.layer.cornerRadius = 0.75
    }
    
    private func updateContent(animated: Bool) {
        let manager = SGDoxMusicManager.shared
        guard let track = manager.currentTrack else {
            self.currentTrackId = nil
            self.updateVisibility(animated: animated)
            return
        }
        
        if self.currentTrackId != track.id {
            self.currentTrackId = track.id
            self.titleLabel.text = track.title
            self.artistLabel.text = track.artist
            
            self.artworkImageView.image = SGDoxImageLoader.shared.placeholderArtwork()
            SGDoxImageLoader.shared.loadArtwork(for: track, targetSize: CGSize(width: 80, height: 80)) { [weak self] image in
                if self?.currentTrackId == track.id, let image = image {
                    self?.artworkImageView.image = image
                }
            }
        }
        
        let iconName = manager.isPlaying ? "pause.fill" : "play.fill"
        let playConfig = UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)
        self.playPauseButton.setImage(UIImage(systemName: iconName, withConfiguration: playConfig), for: .normal)
        
        self.updateVisibility(animated: animated)
    }
    
    private func updateVisibility(animated: Bool) {
        let shouldShow = SGDoxMusicManager.shared.currentTrack != nil && !self.isHiddenForSubscreens
        
        if !shouldShow {
            if animated && !self.isHidden {
                UIView.animate(withDuration: 0.25, animations: {
                    self.alpha = 0.0
                    self.transform = CGAffineTransform(translationX: 0, y: 25)
                }) { [weak self] _ in
                    self?.isHidden = true
                }
            } else {
                self.isHidden = true
                self.alpha = 0.0
            }
        } else {
            if self.isHidden {
                self.isHidden = false
                self.alpha = 0.0
                self.transform = CGAffineTransform(translationX: 0, y: 25)
            }
            if animated {
                UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0.4, options: [.allowUserInteraction], animations: {
                    self.alpha = 1.0
                    self.transform = .identity
                })
            } else {
                self.alpha = 1.0
                self.transform = .identity
            }
        }
    }
    
    // MARK: - Actions
    
    @objc private func widgetTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        self.openPlayer?()
    }
    
    @objc private func handleSwipeDown() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        SGDoxMusicManager.shared.stop()
    }
    
    @objc private func handleSwipeLeft() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        self.animateTrackTransition(direction: -1) {
            SGDoxMusicManager.shared.next()
        }
    }
    
    @objc private func handleSwipeRight() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        self.animateTrackTransition(direction: 1) {
            SGDoxMusicManager.shared.previous()
        }
    }
    
    private func animateTrackTransition(direction: CGFloat, completion: @escaping () -> Void) {
        UIView.animate(withDuration: 0.12, delay: 0, options: [.curveEaseOut], animations: {
            self.artworkImageView.transform = CGAffineTransform(translationX: direction * -18, y: 0)
            self.textContainerView.transform = CGAffineTransform(translationX: direction * -18, y: 0)
            self.artworkImageView.alpha = 0.45
            self.textContainerView.alpha = 0.45
        }) { _ in
            completion()
            self.artworkImageView.transform = CGAffineTransform(translationX: direction * 18, y: 0)
            self.textContainerView.transform = CGAffineTransform(translationX: direction * 18, y: 0)
            UIView.animate(withDuration: 0.22, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.5, options: [.curveEaseOut], animations: {
                self.artworkImageView.transform = .identity
                self.textContainerView.transform = .identity
                self.artworkImageView.alpha = 1.0
                self.textContainerView.alpha = 1.0
            })
        }
    }
    
    @objc private func playPausePressed() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let isNowPlaying = !SGDoxMusicManager.shared.isPlaying
        let iconName = isNowPlaying ? "pause.fill" : "play.fill"
        let playConfig = UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)
        self.playPauseButton.setImage(UIImage(systemName: iconName, withConfiguration: playConfig), for: .normal)
        
        UIView.animate(withDuration: 0.1, animations: {
            self.playPauseButton.transform = CGAffineTransform(scaleX: 0.86, y: 0.86)
        }) { _ in
            UIView.animate(withDuration: 0.12) {
                self.playPauseButton.transform = .identity
            }
        }
        SGDoxMusicManager.shared.togglePlay()
    }
    
    @objc private func nextPressed() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        UIView.animate(withDuration: 0.1, animations: {
            self.nextButton.transform = CGAffineTransform(scaleX: 0.86, y: 0.86)
        }) { _ in
            UIView.animate(withDuration: 0.12) {
                self.nextButton.transform = .identity
            }
        }
        SGDoxMusicManager.shared.next()
    }
    
    @objc private func closePressed() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        UIView.animate(withDuration: 0.1, animations: {
            self.closeButton.transform = CGAffineTransform(scaleX: 0.86, y: 0.86)
        }) { _ in
            UIView.animate(withDuration: 0.12) {
                self.closeButton.transform = .identity
            }
        }
        SGDoxMusicManager.shared.dismissPlayer()
    }
}
