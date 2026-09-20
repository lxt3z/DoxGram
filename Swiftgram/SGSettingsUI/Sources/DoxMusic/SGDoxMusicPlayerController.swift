import Foundation
import UIKit
import Display
import TelegramCore
import AccountContext
import TelegramPresentationData
import UndoUI
import AppBundle

public final class SGDoxMusicPlayerController: ViewController, UIGestureRecognizerDelegate {
    private let context: AccountContext
    private var presentationData: PresentationData
    
    private let backgroundBlurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
    private let backgroundImageView = UIImageView()
    private let ambientGradientLayer = CAGradientLayer()
    private let dismissButton = UIButton(type: .system)
    private let sourceLabel = UILabel()
    
    private let artworkContainerView = UIView()
    private let artworkImageView = UIImageView()
    
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    
    private let progressSlider = UISlider()
    private let currentTimeLabel = UILabel()
    private let remainingTimeLabel = UILabel()
    
    private let favoriteButton = UIButton(type: .system)
    private let shuffleButton = UIButton(type: .system)
    private let previousButton = UIButton(type: .system)
    private let playPauseButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let repeatButton = UIButton(type: .system)
    
    private let autoplayButton = UIButton(type: .system)
    private let waveButton = UIButton(type: .system)
    private let pinToProfileButton = UIButton(type: .system)
    private let queueButton = UIButton(type: .system)
    
    private var isDraggingSlider = false
    private var displayedTrackId: String?
    
    public init(context: AccountContext) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: nil)
        self.navigationPresentation = .modal
        self.statusBar.statusBarStyle = .White
        self.ready.set(.single(true))
    }
    
    public override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        self.view.setNeedsLayout()
    }
    
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .black
        
        self.setupViews()
        self.updateContent()
        
        SGDoxMusicManager.shared.addStateListener { [weak self] in
            self?.updateContent()
        }
        
        SGDoxMusicManager.shared.addTimeListener { [weak self] current, duration in
            guard let self = self, !self.isDraggingSlider else { return }
            let d = duration > 0 ? duration : 30.0
            self.progressSlider.value = Float(current / d)
            self.currentTimeLabel.text = self.formatTime(current)
            self.remainingTimeLabel.text = "-\(self.formatTime(max(0, d - current)))"
        }
        
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(self.handlePanGesture(_:)))
        panGesture.delegate = self
        self.view.addGestureRecognizer(panGesture)
    }
    
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var current = touch.view
        while let view = current {
            if view is UIControl {
                return false
            }
            current = view.superview
        }
        return true
    }
    
    @objc private func handlePanGesture(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: self.view)
        if recognizer.state == .changed {
            if translation.y > 0 {
                self.view.transform = CGAffineTransform(translationX: 0, y: translation.y)
            }
        } else if recognizer.state == .ended || recognizer.state == .cancelled {
            let velocity = recognizer.velocity(in: self.view)
            if translation.y > 140 || velocity.y > 700 {
                UIView.animate(withDuration: 0.2, animations: {
                    self.view.transform = CGAffineTransform(translationX: 0, y: self.view.bounds.height)
                }) { [weak self] _ in
                    self?.dismiss()
                }
            } else {
                UIView.animate(withDuration: 0.25) {
                    self.view.transform = .identity
                }
            }
        }
    }
    
    private func setupViews() {
        self.backgroundImageView.frame = self.view.bounds
        self.backgroundImageView.contentMode = .scaleAspectFill
        self.backgroundImageView.clipsToBounds = true
        self.view.addSubview(self.backgroundImageView)
        
        self.ambientGradientLayer.frame = self.view.bounds
        self.ambientGradientLayer.startPoint = CGPoint(x: 0.2, y: 0.0)
        self.ambientGradientLayer.endPoint = CGPoint(x: 0.8, y: 1.0)
        self.ambientGradientLayer.colors = [
            UIColor(red: 0.12, green: 0.14, blue: 0.22, alpha: 0.9).cgColor,
            UIColor(red: 0.05, green: 0.06, blue: 0.10, alpha: 0.95).cgColor
        ]
        self.view.layer.addSublayer(self.ambientGradientLayer)
        
        self.backgroundBlurView.frame = self.view.bounds
        self.view.addSubview(self.backgroundBlurView)
        
        // Header
        let chevronDownImage = UIImage(systemName: "chevron.down") ?? UIImage()
        self.dismissButton.setImage(chevronDownImage, for: .normal)
        self.dismissButton.tintColor = .white
        self.dismissButton.addTarget(self, action: #selector(self.dismissPressed), for: .touchUpInside)
        self.view.addSubview(self.dismissButton)
        
        self.sourceLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        self.sourceLabel.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        self.sourceLabel.textAlignment = .center
        self.view.addSubview(self.sourceLabel)
        
        // Artwork
        self.artworkContainerView.layer.shadowColor = UIColor.black.cgColor
        self.artworkContainerView.layer.shadowOpacity = 0.55
        self.artworkContainerView.layer.shadowRadius = 26
        self.artworkContainerView.layer.shadowOffset = CGSize(width: 0, height: 12)
        self.view.addSubview(self.artworkContainerView)
        
        self.artworkImageView.contentMode = .scaleAspectFill
        self.artworkImageView.clipsToBounds = true
        self.artworkImageView.layer.cornerRadius = 22
        self.artworkImageView.backgroundColor = UIColor(white: 0.2, alpha: 1.0)
        self.artworkContainerView.addSubview(self.artworkImageView)
        
        // Title & Artist
        self.titleLabel.textColor = .white
        self.titleLabel.font = UIFont.systemFont(ofSize: 22, weight: .bold)
        self.titleLabel.textAlignment = .left
        self.view.addSubview(self.titleLabel)
        
        self.artistLabel.textColor = UIColor.white.withAlphaComponent(0.75)
        self.artistLabel.font = UIFont.systemFont(ofSize: 17, weight: .medium)
        self.artistLabel.textAlignment = .left
        self.view.addSubview(self.artistLabel)
        
        let heartConfig = UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)
        self.favoriteButton.setImage(UIImage(systemName: "suit.heart", withConfiguration: heartConfig), for: .normal)
        self.favoriteButton.tintColor = .white
        self.favoriteButton.addTarget(self, action: #selector(self.favoritePressed), for: .touchUpInside)
        self.view.addSubview(self.favoriteButton)
        
        // Sleek Apple Music Scrubber Slider
        let minTrack = self.createTrackImage(color: .white, height: 3.5)
        let maxTrack = self.createTrackImage(color: UIColor.white.withAlphaComponent(0.22), height: 3.5)
        let normalThumb = self.createThumbImage(size: 11.0)
        let activeThumb = self.createThumbImage(size: 14.0)
        self.progressSlider.setMinimumTrackImage(minTrack, for: .normal)
        self.progressSlider.setMaximumTrackImage(maxTrack, for: .normal)
        self.progressSlider.setThumbImage(normalThumb, for: .normal)
        self.progressSlider.setThumbImage(activeThumb, for: .highlighted)
        self.progressSlider.addTarget(self, action: #selector(self.sliderValueChanged), for: .valueChanged)
        self.progressSlider.addTarget(self, action: #selector(self.sliderTouchEnded), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        self.view.addSubview(self.progressSlider)
        
        self.currentTimeLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        self.currentTimeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        self.currentTimeLabel.text = "0:00"
        self.view.addSubview(self.currentTimeLabel)
        
        self.remainingTimeLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        self.remainingTimeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        self.remainingTimeLabel.text = "-0:00"
        self.remainingTimeLabel.textAlignment = .right
        self.view.addSubview(self.remainingTimeLabel)
        
        // Playback Buttons
        self.setupControlButtons()
        
        // Bottom Action Bar: Wave, Autoplay, Queue, Pin to Profile
        self.setupActionButtons()
    }
    
    private func setupControlButtons() {
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        
        self.shuffleButton.setImage(UIImage(systemName: "shuffle", withConfiguration: config), for: .normal)
        self.shuffleButton.tintColor = UIColor.white.withAlphaComponent(0.6)
        self.shuffleButton.addTarget(self, action: #selector(self.shufflePressed), for: .touchUpInside)
        self.view.addSubview(self.shuffleButton)
        
        self.previousButton.setImage(UIImage(systemName: "backward.fill", withConfiguration: config), for: .normal)
        self.previousButton.tintColor = .white
        self.previousButton.addTarget(self, action: #selector(self.previousPressed), for: .touchUpInside)
        self.view.addSubview(self.previousButton)
        
        let playConfig = UIImage.SymbolConfiguration(pointSize: 34, weight: .bold)
        self.playPauseButton.setImage(UIImage(systemName: "play.fill", withConfiguration: playConfig), for: .normal)
        self.playPauseButton.tintColor = .black
        self.playPauseButton.backgroundColor = .white
        self.playPauseButton.layer.cornerRadius = 35
        self.playPauseButton.addTarget(self, action: #selector(self.playPausePressed), for: .touchUpInside)
        self.view.addSubview(self.playPauseButton)
        
        self.nextButton.setImage(UIImage(systemName: "forward.fill", withConfiguration: config), for: .normal)
        self.nextButton.tintColor = .white
        self.nextButton.addTarget(self, action: #selector(self.nextPressed), for: .touchUpInside)
        self.view.addSubview(self.nextButton)
        
        self.repeatButton.setImage(UIImage(systemName: "repeat", withConfiguration: config), for: .normal)
        self.repeatButton.tintColor = UIColor.white.withAlphaComponent(0.6)
        self.repeatButton.addTarget(self, action: #selector(self.repeatPressed), for: .touchUpInside)
        self.view.addSubview(self.repeatButton)
    }
    
    private func setupActionButtons() {
        // Autoplay button (Apple Music infinity button)
        let infinityConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        self.autoplayButton.setImage(UIImage(systemName: "infinity", withConfiguration: infinityConfig), for: .normal)
        self.autoplayButton.tintColor = .white
        self.autoplayButton.backgroundColor = UIColor(white: 1.0, alpha: 0.15)
        self.autoplayButton.layer.cornerRadius = 20
        self.autoplayButton.addTarget(self, action: #selector(self.autoplayPressed), for: .touchUpInside)
        self.view.addSubview(self.autoplayButton)
        
        // Wave button
        self.waveButton.setTitle(" Волна", for: .normal)
        self.waveButton.setImage(UIImage(systemName: "dot.radiowaves.left.and.right"), for: .normal)
        self.waveButton.tintColor = .white
        self.waveButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        self.waveButton.backgroundColor = UIColor(white: 1.0, alpha: 0.15)
        self.waveButton.layer.cornerRadius = 20
        self.waveButton.addTarget(self, action: #selector(self.wavePressed), for: .touchUpInside)
        self.view.addSubview(self.waveButton)
        
        // Pin to Profile button
        self.pinToProfileButton.setTitle(" В профиль", for: .normal)
        self.pinToProfileButton.setImage(UIImage(systemName: "pin.fill"), for: .normal)
        self.pinToProfileButton.tintColor = .white
        self.pinToProfileButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        self.pinToProfileButton.backgroundColor = UIColor(red: 0.0, green: 0.55, blue: 1.0, alpha: 0.8)
        self.pinToProfileButton.layer.cornerRadius = 20
        self.pinToProfileButton.addTarget(self, action: #selector(self.pinToProfilePressed), for: .touchUpInside)
        self.view.addSubview(self.pinToProfileButton)
        
        // Queue button
        let queueConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        self.queueButton.setImage(UIImage(systemName: "list.bullet", withConfiguration: queueConfig), for: .normal)
        self.queueButton.tintColor = .white
        self.queueButton.backgroundColor = UIColor(white: 1.0, alpha: 0.15)
        self.queueButton.layer.cornerRadius = 20
        self.queueButton.addTarget(self, action: #selector(self.queuePressed), for: .touchUpInside)
        self.view.addSubview(self.queueButton)
    }
    
    // MARK: - UI Helpers & Apple Music Animations
    
    private func createTrackImage(color: UIColor, height: CGFloat = 3.5) -> UIImage {
        let size = CGSize(width: height * 2, height: height)
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        defer { UIGraphicsEndImageContext() }
        color.setFill()
        let path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: height / 2.0)
        path.fill()
        return (UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()).resizableImage(withCapInsets: UIEdgeInsets(top: height/2, left: height/2, bottom: height/2, right: height/2))
    }
    
    private func createThumbImage(size: CGFloat = 11.0) -> UIImage {
        let canvas = CGSize(width: size + 8, height: size + 8)
        UIGraphicsBeginImageContextWithOptions(canvas, false, 0.0)
        defer { UIGraphicsEndImageContext() }
        guard let ctx = UIGraphicsGetCurrentContext() else { return UIImage() }
        ctx.setShadow(offset: CGSize(width: 0, height: 1.5), blur: 3.5, color: UIColor.black.withAlphaComponent(0.35).cgColor)
        UIColor.white.setFill()
        let path = UIBezierPath(ovalIn: CGRect(x: 4, y: 4, width: size, height: size))
        path.fill()
        return UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
    }
    
    private func updateAmbientColors(from image: UIImage?) {
        guard let image = image, let cgImage = image.cgImage else {
            let defaultColors = [
                UIColor(red: 0.12, green: 0.14, blue: 0.22, alpha: 0.9).cgColor,
                UIColor(red: 0.05, green: 0.06, blue: 0.10, alpha: 0.95).cgColor
            ]
            self.ambientGradientLayer.colors = defaultColors
            return
        }
        
        // Sample artwork colors
        let width = 8
        let height = 8
        var rawData = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        )
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        var totalR: CGFloat = 0, totalG: CGFloat = 0, totalB: CGFloat = 0
        var maxSat: CGFloat = -1
        var accentR: CGFloat = 0.3, accentG: CGFloat = 0.2, accentB: CGFloat = 0.45
        let count = CGFloat(width * height)
        
        for i in 0..<(width * height) {
            let r = CGFloat(rawData[i * 4]) / 255.0
            let g = CGFloat(rawData[i * 4 + 1]) / 255.0
            let b = CGFloat(rawData[i * 4 + 2]) / 255.0
            totalR += r
            totalG += g
            totalB += b
            
            let maxC = max(r, max(g, b))
            let minC = min(r, min(g, b))
            let sat = maxC > 0 ? (maxC - minC) / maxC : 0
            if sat > maxSat && maxC > 0.2 {
                maxSat = sat
                accentR = r
                accentG = g
                accentB = b
            }
        }
        
        let avgColor = UIColor(red: (totalR / count) * 0.75, green: (totalG / count) * 0.75, blue: (totalB / count) * 0.75, alpha: 0.95)
        let vibrantColor = UIColor(red: accentR * 0.85, green: accentG * 0.85, blue: accentB * 0.85, alpha: 0.9)
        let deepColor = UIColor(red: accentR * 0.25, green: accentG * 0.25, blue: accentB * 0.3, alpha: 0.98)
        
        let newColors = [vibrantColor.cgColor, avgColor.cgColor, deepColor.cgColor]
        
        let animation = CABasicAnimation(keyPath: "colors")
        animation.fromValue = self.ambientGradientLayer.colors
        animation.toValue = newColors
        animation.duration = 0.8
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        self.ambientGradientLayer.add(animation, forKey: "colorsChange")
        self.ambientGradientLayer.colors = newColors
    }
    
    private func updateArtworkScale(isPlaying: Bool, animated: Bool) {
        let block = {
            if isPlaying {
                self.artworkContainerView.transform = .identity
                self.artworkContainerView.layer.shadowOpacity = 0.55
                self.artworkContainerView.layer.shadowRadius = 26
            } else {
                self.artworkContainerView.transform = CGAffineTransform(scaleX: 0.86, y: 0.86)
                self.artworkContainerView.layer.shadowOpacity = 0.22
                self.artworkContainerView.layer.shadowRadius = 14
            }
        }
        
        if animated {
            UIView.animate(
                withDuration: 0.55,
                delay: 0,
                usingSpringWithDamping: 0.72,
                initialSpringVelocity: 0.4,
                options: [.allowUserInteraction, .beginFromCurrentState],
                animations: block
            )
        } else {
            block()
        }
    }
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = self.view.bounds
        let safeArea = self.view.safeAreaInsets
        
        self.backgroundImageView.frame = bounds
        self.ambientGradientLayer.frame = bounds
        self.backgroundBlurView.frame = bounds
        
        let headerY = safeArea.top + 8
        self.dismissButton.frame = CGRect(x: 16, y: headerY, width: 44, height: 44)
        self.sourceLabel.frame = CGRect(x: 60, y: headerY + 12, width: bounds.width - 120, height: 20)
        
        let artworkSide = min(bounds.width - 64, bounds.height * 0.38)
        let artworkY = headerY + 54
        self.artworkContainerView.frame = CGRect(x: (bounds.width - artworkSide) * 0.5, y: artworkY, width: artworkSide, height: artworkSide)
        self.artworkImageView.frame = CGRect(x: 0, y: 0, width: artworkSide, height: artworkSide)
        
        let titleY = artworkY + artworkSide + 28
        let favoriteSize: CGFloat = 40
        self.favoriteButton.frame = CGRect(x: bounds.width - 32 - favoriteSize, y: titleY + 4, width: favoriteSize, height: favoriteSize)
        
        let titleWidth = bounds.width - 64 - favoriteSize - 8
        self.titleLabel.frame = CGRect(x: 32, y: titleY, width: titleWidth, height: 28)
        self.artistLabel.frame = CGRect(x: 32, y: titleY + 30, width: titleWidth, height: 22)
        
        let sliderY = titleY + 66
        self.progressSlider.frame = CGRect(x: 32, y: sliderY, width: bounds.width - 64, height: 24)
        self.currentTimeLabel.frame = CGRect(x: 32, y: sliderY + 22, width: 60, height: 16)
        self.remainingTimeLabel.frame = CGRect(x: bounds.width - 92, y: sliderY + 22, width: 60, height: 16)
        
        let controlsY = sliderY + 56
        let controlSpacing = (bounds.width - 64 - 70 - 176) / 4.0
        
        self.shuffleButton.frame = CGRect(x: 32, y: controlsY + 13, width: 44, height: 44)
        self.previousButton.frame = CGRect(x: 32 + 44 + controlSpacing, y: controlsY + 13, width: 44, height: 44)
        self.playPauseButton.frame = CGRect(x: (bounds.width - 70) * 0.5, y: controlsY, width: 70, height: 70)
        self.nextButton.frame = CGRect(x: bounds.width - 32 - 44 - controlSpacing - 44, y: controlsY + 13, width: 44, height: 44)
        self.repeatButton.frame = CGRect(x: bounds.width - 32 - 44, y: controlsY + 13, width: 44, height: 44)
        
        let actionsY = controlsY + 86
        let sideBtnSize: CGFloat = 40
        let totalSpacing: CGFloat = 10 * 3
        let mainActionWidth = max(70, (bounds.width - 64 - (sideBtnSize * 2) - totalSpacing) * 0.5)
        
        self.autoplayButton.frame = CGRect(x: 32, y: actionsY + 2, width: sideBtnSize, height: sideBtnSize)
        self.waveButton.frame = CGRect(x: 32 + sideBtnSize + 10, y: actionsY, width: mainActionWidth, height: 44)
        self.pinToProfileButton.frame = CGRect(x: 32 + sideBtnSize + 10 + mainActionWidth + 10, y: actionsY, width: mainActionWidth, height: 44)
        self.queueButton.frame = CGRect(x: bounds.width - 32 - sideBtnSize, y: actionsY + 2, width: sideBtnSize, height: sideBtnSize)
    }
    
    private func updateContent() {
        let manager = SGDoxMusicManager.shared
        guard let track = manager.currentTrack else {
            self.titleLabel.text = "Ничего не играет"
            self.artistLabel.text = "Выберите трек"
            self.sourceLabel.text = "DoxMusic"
            self.displayedTrackId = nil
            self.updateArtworkScale(isPlaying: false, animated: false)
            return
        }
        
        let trackChanged = self.displayedTrackId != track.id
        if trackChanged {
            self.displayedTrackId = track.id
            self.titleLabel.text = track.title
            self.artistLabel.text = track.artist
            self.sourceLabel.text = "Играет из \(track.source.rawValue)"
            
            if let artworkUrl = track.artworkUrl {
                if let cached = SGDoxImageLoader.shared.cachedImage(for: artworkUrl) {
                    self.artworkImageView.image = cached
                    self.backgroundImageView.image = cached
                    self.updateAmbientColors(from: cached)
                } else {
                    self.artworkImageView.image = SGDoxImageLoader.shared.placeholderArtwork()
                    SGDoxImageLoader.shared.loadImage(urlString: artworkUrl, targetSize: CGSize(width: 320, height: 320)) { [weak self] image in
                        if self?.displayedTrackId == track.id, let image = image {
                            self?.artworkImageView.image = image
                            self?.backgroundImageView.image = image
                            self?.updateAmbientColors(from: image)
                        }
                    }
                }
            } else {
                self.artworkImageView.image = SGDoxImageLoader.shared.placeholderArtwork()
                self.backgroundImageView.image = nil
                self.updateAmbientColors(from: nil)
            }
        }
        
        // Favorite state
        let isFav = manager.isFavorite(track: track)
        let heartIcon = isFav ? "suit.heart.fill" : "suit.heart"
        let heartConfig = UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)
        self.favoriteButton.setImage(UIImage(systemName: heartIcon, withConfiguration: heartConfig), for: .normal)
        self.favoriteButton.tintColor = isFav ? UIColor(red: 0.98, green: 0.20, blue: 0.35, alpha: 1.0) : .white
        
        // Play/Pause icon & Apple Music artwork spring animation
        let playConfig = UIImage.SymbolConfiguration(pointSize: 34, weight: .bold)
        let iconName = manager.isPlaying ? "pause.fill" : "play.fill"
        self.playPauseButton.setImage(UIImage(systemName: iconName, withConfiguration: playConfig), for: .normal)
        self.updateArtworkScale(isPlaying: manager.isPlaying, animated: true)
        
        // Shuffle state
        self.shuffleButton.tintColor = manager.isShuffleEnabled ? UIColor(red: 0.98, green: 0.20, blue: 0.35, alpha: 1.0) : UIColor.white.withAlphaComponent(0.6)
        
        // Repeat state
        let repeatConfig = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        switch manager.repeatMode {
        case .off:
            self.repeatButton.setImage(UIImage(systemName: "repeat", withConfiguration: repeatConfig), for: .normal)
            self.repeatButton.tintColor = UIColor.white.withAlphaComponent(0.6)
        case .all:
            self.repeatButton.setImage(UIImage(systemName: "repeat", withConfiguration: repeatConfig), for: .normal)
            self.repeatButton.tintColor = UIColor(red: 0.98, green: 0.20, blue: 0.35, alpha: 1.0)
        case .one:
            self.repeatButton.setImage(UIImage(systemName: "repeat.1", withConfiguration: repeatConfig), for: .normal)
            self.repeatButton.tintColor = UIColor(red: 0.98, green: 0.20, blue: 0.35, alpha: 1.0)
        }
        
        // Wave state
        if manager.isWaveEnabled {
            self.waveButton.backgroundColor = UIColor(red: 0.95, green: 0.25, blue: 0.5, alpha: 0.85)
        } else {
            self.waveButton.backgroundColor = UIColor(white: 1.0, alpha: 0.15)
        }
        
        // Autoplay state
        self.autoplayButton.backgroundColor = manager.isAutoplayEnabled ? UIColor(red: 0.98, green: 0.20, blue: 0.35, alpha: 0.85) : UIColor(white: 1.0, alpha: 0.15)
        
        // Queue state
        self.queueButton.backgroundColor = !manager.queue.isEmpty ? UIColor(white: 1.0, alpha: 0.3) : UIColor(white: 1.0, alpha: 0.15)
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let s = Int(seconds)
        let mins = s / 60
        let secs = s % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    // MARK: - Actions
    
    @objc private func dismissPressed() {
        self.dismiss()
    }
    
    @objc private func favoritePressed() {
        guard let track = SGDoxMusicManager.shared.currentTrack else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        UIView.animate(withDuration: 0.15, animations: {
            self.favoriteButton.transform = CGAffineTransform(scaleX: 1.35, y: 1.35)
        }) { _ in
            UIView.animate(withDuration: 0.15) {
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
    }
    
    @objc private func queuePressed() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let queueController = SGDoxMusicQueueController(context: self.context)
        queueController.navigationPresentation = .modal
        self.push(queueController)
    }
    
    @objc private func playPausePressed() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        UIView.animate(withDuration: 0.1, animations: {
            self.playPauseButton.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        }) { _ in
            UIView.animate(withDuration: 0.15) {
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
            UIView.animate(withDuration: 0.15) {
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
            UIView.animate(withDuration: 0.15) {
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
    }
    
    @objc private func pinToProfilePressed() {
        guard let track = SGDoxMusicManager.shared.currentTrack else { return }
        
        SGDoxMusicManager.shared.pinCurrentTrackToProfile(context: self.context) { [weak self] success, errorText in
            guard let self = self else { return }
            let text = success ? "Музыка «\(track.title)» добавлена в профиль" : (errorText ?? "Не удалось установить трек в профиль")
            
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
}
