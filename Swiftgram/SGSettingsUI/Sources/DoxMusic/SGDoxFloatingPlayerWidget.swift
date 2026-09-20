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
    
    private let blurView = UIVisualEffectView()
    private let glossLayer = CAGradientLayer()
    
    private let artworkImageView = UIImageView()
    private let textStackView = UIStackView()
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    
    private let controlsStackView = UIStackView()
    private let playPauseButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    
    private let progressView = UIProgressView(progressViewStyle: .default)
    
    private var isHiddenForSubscreens = false
    private var currentTrackId: String?
    
    public init(context: AccountContext) {
        self.context = context
        self.theme = context.sharedContext.currentPresentationData.with { $0.theme }
        super.init(frame: .zero)
        
        self.setupViews()
        self.setupListeners()
        self.updateContent(animated: false)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        self.backgroundColor = .clear
        
        // Shadow for floating elevation
        self.layer.shadowColor = UIColor.black.cgColor
        self.layer.shadowOpacity = 0.35
        self.layer.shadowRadius = 14
        self.layer.shadowOffset = CGSize(width: 0, height: 6)
        
        // Blur / Glass Effect
        let blurStyle: UIBlurEffect.Style = self.theme.overallDarkAppearance ? .systemMaterialDark : .systemMaterialLight
        self.blurView.effect = UIBlurEffect(style: blurStyle)
        self.blurView.clipsToBounds = true
        self.blurView.layer.cornerRadius = 27
        self.blurView.layer.borderWidth = 0.5
        self.blurView.layer.borderColor = UIColor.white.withAlphaComponent(0.2).cgColor
        self.addSubview(self.blurView)
        
        // Specular glass highlight gradient on top
        self.glossLayer.colors = [
            UIColor.white.withAlphaComponent(0.16).cgColor,
            UIColor.white.withAlphaComponent(0.02).cgColor,
            UIColor.clear.cgColor
        ]
        self.glossLayer.locations = [0.0, 0.5, 1.0]
        self.glossLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        self.glossLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        self.blurView.contentView.layer.addSublayer(self.glossLayer)
        
        // Tap gesture to open player
        let tap = UITapGestureRecognizer(target: self, action: #selector(self.widgetTapped))
        self.addGestureRecognizer(tap)
        
        // Swipe down to stop / dismiss
        let swipe = UISwipeGestureRecognizer(target: self, action: #selector(self.handleSwipeDown))
        swipe.direction = .down
        self.addGestureRecognizer(swipe)
        
        // Artwork
        self.artworkImageView.contentMode = .scaleAspectFill
        self.artworkImageView.clipsToBounds = true
        self.artworkImageView.layer.cornerRadius = 10
        self.artworkImageView.backgroundColor = UIColor(white: 0.2, alpha: 1.0)
        self.blurView.contentView.addSubview(self.artworkImageView)
        
        // Text Stack: Title & Artist
        self.textStackView.axis = .vertical
        self.textStackView.alignment = .leading
        self.textStackView.distribution = .fillProportionally
        self.textStackView.spacing = 1
        
        self.titleLabel.font = UIFont.systemFont(ofSize: 13.5, weight: .semibold)
        self.titleLabel.textColor = .white
        self.titleLabel.lineBreakMode = .byTruncatingTail
        self.textStackView.addArrangedSubview(self.titleLabel)
        
        self.artistLabel.font = UIFont.systemFont(ofSize: 11.5, weight: .regular)
        self.artistLabel.textColor = UIColor.white.withAlphaComponent(0.72)
        self.artistLabel.lineBreakMode = .byTruncatingTail
        self.textStackView.addArrangedSubview(self.artistLabel)
        
        self.blurView.contentView.addSubview(self.textStackView)
        
        // Play/Pause button
        let playConfig = UIImage.SymbolConfiguration(pointSize: 17, weight: .bold)
        self.playPauseButton.setImage(UIImage(systemName: "play.fill", withConfiguration: playConfig), for: .normal)
        self.playPauseButton.tintColor = .white
        self.playPauseButton.addTarget(self, action: #selector(self.playPausePressed), for: .touchUpInside)
        
        // Next button
        let nextConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        self.nextButton.setImage(UIImage(systemName: "forward.fill", withConfiguration: nextConfig), for: .normal)
        self.nextButton.tintColor = UIColor.white.withAlphaComponent(0.85)
        self.nextButton.addTarget(self, action: #selector(self.nextPressed), for: .touchUpInside)
        
        self.controlsStackView.axis = .horizontal
        self.controlsStackView.alignment = .center
        self.controlsStackView.distribution = .equalSpacing
        self.controlsStackView.spacing = 6
        self.controlsStackView.addArrangedSubview(self.playPauseButton)
        self.controlsStackView.addArrangedSubview(self.nextButton)
        self.blurView.contentView.addSubview(self.controlsStackView)
        
        // Bottom subtle progress line
        self.progressView.progressTintColor = UIColor(red: 0.12, green: 0.55, blue: 1.0, alpha: 0.9)
        self.progressView.trackTintColor = UIColor.white.withAlphaComponent(0.12)
        self.blurView.contentView.addSubview(self.progressView)
    }
    
    private func setupListeners() {
        SGDoxMusicManager.shared.addStateListener { [weak self] in
            DispatchQueue.main.async {
                self?.updateContent(animated: true)
            }
        }
        
        SGDoxMusicManager.shared.addTimeListener { [weak self] current, duration in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let d = duration > 0 ? duration : 30.0
                self.progressView.setProgress(Float(current / d), animated: true)
            }
        }
    }
    
    public func updateTheme(_ theme: PresentationTheme) {
        self.theme = theme
        let blurStyle: UIBlurEffect.Style = theme.overallDarkAppearance ? .systemMaterialDark : .systemMaterialLight
        self.blurView.effect = UIBlurEffect(style: blurStyle)
        self.progressView.progressTintColor = theme.list.itemAccentColor
    }
    
    public func setHiddenForSubscreens(_ hidden: Bool) {
        guard self.isHiddenForSubscreens != hidden else { return }
        self.isHiddenForSubscreens = hidden
        self.updateVisibility(animated: true)
    }
    
    public func updateLayout(size: CGSize, insets: UIEdgeInsets, transition: ContainedViewLayoutTransition) {
        let widgetHeight: CGFloat = 54.0
        let horizontalMargin: CGFloat = 14.0
        let widgetWidth = min(size.width - horizontalMargin * 2.0, 420.0)
        let x = (size.width - widgetWidth) * 0.5
        
        // Tab bar height in Telegram is typically 49pt + insets.bottom
        let bottomTabOffset = insets.bottom + 49.0 + 8.0
        let y = size.height - bottomTabOffset - widgetHeight
        
        let targetFrame = CGRect(x: x, y: y, width: widgetWidth, height: widgetHeight)
        
        if transition.isAnimated {
            transition.updateFrame(view: self, frame: targetFrame)
        } else {
            self.frame = targetFrame
        }
        
        self.blurView.frame = self.bounds
        self.glossLayer.frame = CGRect(x: 0, y: 0, width: self.bounds.width, height: 26)
        
        let artSide: CGFloat = 40.0
        self.artworkImageView.frame = CGRect(x: 7, y: (widgetHeight - artSide) * 0.5, width: artSide, height: artSide)
        
        let controlsWidth: CGFloat = 76.0
        let controlsX = widgetWidth - controlsWidth - 8.0
        self.controlsStackView.frame = CGRect(x: controlsX, y: (widgetHeight - 36.0) * 0.5, width: controlsWidth, height: 36.0)
        
        let textX = self.artworkImageView.frame.maxX + 10.0
        let textWidth = max(0, controlsX - textX - 8.0)
        self.textStackView.frame = CGRect(x: textX, y: (widgetHeight - 34.0) * 0.5, width: textWidth, height: 34.0)
        
        self.progressView.frame = CGRect(x: 16.0, y: widgetHeight - 2.5, width: widgetWidth - 32.0, height: 2.0)
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
            
            if let artworkUrl = track.artworkUrl {
                if let cached = SGDoxImageLoader.shared.cachedImage(for: artworkUrl) {
                    self.artworkImageView.image = cached
                } else {
                    self.artworkImageView.image = SGDoxImageLoader.shared.placeholderArtwork()
                    SGDoxImageLoader.shared.loadImage(urlString: artworkUrl, targetSize: CGSize(width: 80, height: 80)) { [weak self] image in
                        if self?.currentTrackId == track.id, let image = image {
                            self?.artworkImageView.image = image
                        }
                    }
                }
            } else {
                self.artworkImageView.image = SGDoxImageLoader.shared.placeholderArtwork()
            }
        }
        
        let iconName = manager.isPlaying ? "pause.fill" : "play.fill"
        let playConfig = UIImage.SymbolConfiguration(pointSize: 17, weight: .bold)
        self.playPauseButton.setImage(UIImage(systemName: iconName, withConfiguration: playConfig), for: .normal)
        
        self.updateVisibility(animated: animated)
    }
    
    private func updateVisibility(animated: Bool) {
        let shouldShow = SGDoxMusicManager.shared.currentTrack != nil && !self.isHiddenForSubscreens
        
        if !shouldShow {
            if animated && !self.isHidden {
                UIView.animate(withDuration: 0.25, animations: {
                    self.alpha = 0.0
                    self.transform = CGAffineTransform(translationX: 0, y: 30)
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
                self.transform = CGAffineTransform(translationX: 0, y: 30)
            }
            if animated {
                UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5, options: [.allowUserInteraction], animations: {
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
    
    @objc private func playPausePressed() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        UIView.animate(withDuration: 0.1, animations: {
            self.playPauseButton.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
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
            self.nextButton.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
        }) { _ in
            UIView.animate(withDuration: 0.12) {
                self.nextButton.transform = .identity
            }
        }
        SGDoxMusicManager.shared.next()
    }
}
