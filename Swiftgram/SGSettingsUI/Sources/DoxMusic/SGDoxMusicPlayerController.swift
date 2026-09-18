import Foundation
import UIKit
import Display
import TelegramCore
import AccountContext
import TelegramPresentationData
import UndoUI
import AppBundle

public final class SGDoxMusicPlayerController: ViewController {
    private let context: AccountContext
    private var presentationData: PresentationData
    
    private let backgroundBlurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
    private let backgroundImageView = UIImageView()
    private let dismissButton = UIButton(type: .system)
    private let sourceLabel = UILabel()
    
    private let artworkContainerView = UIView()
    private let artworkImageView = UIImageView()
    private let vinylDiskView = UIView()
    
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    
    private let progressSlider = UISlider()
    private let currentTimeLabel = UILabel()
    private let remainingTimeLabel = UILabel()
    
    private let shuffleButton = UIButton(type: .system)
    private let previousButton = UIButton(type: .system)
    private let playPauseButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let repeatButton = UIButton(type: .system)
    
    private let waveButton = UIButton(type: .system)
    private let pinToProfileButton = UIButton(type: .system)
    
    private var isDraggingSlider = false
    
    public init(context: AccountContext) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: nil)
        self.modalPresentationStyle = .overFullScreen
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
    }
    
    private func setupViews() {
        self.backgroundImageView.frame = self.view.bounds
        self.backgroundImageView.contentMode = .scaleAspectFill
        self.backgroundImageView.clipsToBounds = true
        self.view.addSubview(self.backgroundImageView)
        
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
        
        // Artwork & Vinyl
        self.artworkContainerView.layer.shadowColor = UIColor.black.cgColor
        self.artworkContainerView.layer.shadowOpacity = 0.5
        self.artworkContainerView.layer.shadowRadius = 24
        self.artworkContainerView.layer.shadowOffset = CGSize(width: 0, height: 12)
        self.view.addSubview(self.artworkContainerView)
        
        self.vinylDiskView.backgroundColor = UIColor(white: 0.08, alpha: 1.0)
        self.vinylDiskView.layer.cornerRadius = 120
        self.vinylDiskView.layer.borderWidth = 4
        self.vinylDiskView.layer.borderColor = UIColor(white: 0.15, alpha: 1.0).cgColor
        self.artworkContainerView.addSubview(self.vinylDiskView)
        
        self.artworkImageView.contentMode = .scaleAspectFill
        self.artworkImageView.clipsToBounds = true
        self.artworkImageView.layer.cornerRadius = 20
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
        
        // Scrubber
        self.progressSlider.tintColor = .white
        self.progressSlider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.2)
        self.progressSlider.addTarget(self, action: #selector(self.sliderValueChanged), for: .valueChanged)
        self.progressSlider.addTarget(self, action: #selector(self.sliderTouchEnded), for: [.touchUpInside, .touchUpOutside])
        self.view.addSubview(self.progressSlider)
        
        self.currentTimeLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        self.currentTimeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        self.currentTimeLabel.text = "0:00"
        self.view.addSubview(self.currentTimeLabel)
        
        self.remainingTimeLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        self.remainingTimeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        self.remainingTimeLabel.text = "-0:00"
        self.remainingTimeLabel.textAlignment = .right
        self.view.addSubview(self.remainingTimeLabel)
        
        // Playback Buttons
        self.setupControlButtons()
        
        // Bottom Action Bar: Wave & Pin to Profile
        self.setupActionButtons()
    }
    
    private func setupControlButtons() {
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        
        self.shuffleButton.setImage(UIImage(systemName: "shuffle", withConfiguration: config), for: .normal)
        self.shuffleButton.tintColor = UIColor.white.withAlphaComponent(0.6)
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
        self.view.addSubview(self.repeatButton)
    }
    
    private func setupActionButtons() {
        // Wave button
        self.waveButton.setTitle(" Моя волна", for: .normal)
        self.waveButton.setImage(UIImage(systemName: "dot.radiowaves.left.and.right"), for: .normal)
        self.waveButton.tintColor = .white
        self.waveButton.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        self.waveButton.backgroundColor = UIColor(white: 1.0, alpha: 0.15)
        self.waveButton.layer.cornerRadius = 20
        self.waveButton.addTarget(self, action: #selector(self.wavePressed), for: .touchUpInside)
        self.view.addSubview(self.waveButton)
        
        // Pin to Profile button
        self.pinToProfileButton.setTitle(" В профиль", for: .normal)
        self.pinToProfileButton.setImage(UIImage(systemName: "pin.fill"), for: .normal)
        self.pinToProfileButton.tintColor = .white
        self.pinToProfileButton.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        self.pinToProfileButton.backgroundColor = UIColor(red: 0.0, green: 0.55, blue: 1.0, alpha: 0.8)
        self.pinToProfileButton.layer.cornerRadius = 20
        self.pinToProfileButton.addTarget(self, action: #selector(self.pinToProfilePressed), for: .touchUpInside)
        self.view.addSubview(self.pinToProfileButton)
    }
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = self.view.bounds
        let safeArea = self.view.safeAreaInsets
        
        self.backgroundImageView.frame = bounds
        self.backgroundBlurView.frame = bounds
        
        let headerY = safeArea.top + 8
        self.dismissButton.frame = CGRect(x: 16, y: headerY, width: 44, height: 44)
        self.sourceLabel.frame = CGRect(x: 60, y: headerY + 12, width: bounds.width - 120, height: 20)
        
        let artworkSide = min(bounds.width - 64, bounds.height * 0.38)
        let artworkY = headerY + 54
        self.artworkContainerView.frame = CGRect(x: (bounds.width - artworkSide) * 0.5, y: artworkY, width: artworkSide, height: artworkSide)
        self.artworkImageView.frame = CGRect(x: 0, y: 0, width: artworkSide, height: artworkSide)
        self.vinylDiskView.frame = CGRect(x: artworkSide * 0.15, y: -20, width: artworkSide * 0.7, height: artworkSide * 0.7)
        self.vinylDiskView.layer.cornerRadius = (artworkSide * 0.7) * 0.5
        
        let titleY = artworkY + artworkSide + 32
        self.titleLabel.frame = CGRect(x: 32, y: titleY, width: bounds.width - 64, height: 28)
        self.artistLabel.frame = CGRect(x: 32, y: titleY + 30, width: bounds.width - 64, height: 22)
        
        let sliderY = titleY + 68
        self.progressSlider.frame = CGRect(x: 32, y: sliderY, width: bounds.width - 64, height: 30)
        self.currentTimeLabel.frame = CGRect(x: 32, y: sliderY + 28, width: 60, height: 16)
        self.remainingTimeLabel.frame = CGRect(x: bounds.width - 92, y: sliderY + 28, width: 60, height: 16)
        
        let controlsY = sliderY + 64
        let controlSpacing = (bounds.width - 64 - 70 - 180) / 4.0
        
        self.shuffleButton.frame = CGRect(x: 32, y: controlsY + 13, width: 44, height: 44)
        self.previousButton.frame = CGRect(x: 32 + 44 + controlSpacing, y: controlsY + 13, width: 44, height: 44)
        self.playPauseButton.frame = CGRect(x: (bounds.width - 70) * 0.5, y: controlsY, width: 70, height: 70)
        self.nextButton.frame = CGRect(x: bounds.width - 32 - 44 - controlSpacing - 44, y: controlsY + 13, width: 44, height: 44)
        self.repeatButton.frame = CGRect(x: bounds.width - 32 - 44, y: controlsY + 13, width: 44, height: 44)
        
        let actionsY = controlsY + 92
        let actionWidth = (bounds.width - 64 - 16) * 0.5
        self.waveButton.frame = CGRect(x: 32, y: actionsY, width: actionWidth, height: 44)
        self.pinToProfileButton.frame = CGRect(x: 32 + actionWidth + 16, y: actionsY, width: actionWidth, height: 44)
    }
    
    private func updateContent() {
        let manager = SGDoxMusicManager.shared
        guard let track = manager.currentTrack else {
            self.titleLabel.text = "Ничего не играет"
            self.artistLabel.text = "Выберите трек"
            self.sourceLabel.text = "DoxMusic"
            return
        }
        
        self.titleLabel.text = track.title
        self.artistLabel.text = track.artist
        self.sourceLabel.text = "Играет из \(track.source.rawValue)"
        
        if let artworkUrl = track.artworkUrl {
            SGDoxImageLoader.shared.loadImage(urlString: artworkUrl, targetSize: CGSize(width: 320, height: 320)) { [weak self] image in
                self?.artworkImageView.image = image
                self?.backgroundImageView.image = image
            }
        } else {
            self.artworkImageView.image = UIImage(bundleImageName: "Media Editor/SmallAudio")
            self.backgroundImageView.image = nil
        }
        
        let playConfig = UIImage.SymbolConfiguration(pointSize: 34, weight: .bold)
        let iconName = manager.isPlaying ? "pause.fill" : "play.fill"
        self.playPauseButton.setImage(UIImage(systemName: iconName, withConfiguration: playConfig), for: .normal)
        
        if !self.isDraggingSlider {
            let duration = manager.duration > 0 ? manager.duration : 30.0
            self.progressSlider.value = Float(manager.currentTime / duration)
            self.currentTimeLabel.text = self.formatTime(manager.currentTime)
            self.remainingTimeLabel.text = "-\(self.formatTime(max(0, duration - manager.currentTime)))"
        }
        
        // Wave active state indicator
        if manager.isWaveEnabled {
            self.waveButton.backgroundColor = UIColor(red: 0.95, green: 0.25, blue: 0.5, alpha: 0.85)
        } else {
            self.waveButton.backgroundColor = UIColor(white: 1.0, alpha: 0.15)
        }
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
    
    @objc private func playPausePressed() {
        SGDoxMusicManager.shared.togglePlay()
    }
    
    @objc private func nextPressed() {
        SGDoxMusicManager.shared.next()
    }
    
    @objc private func previousPressed() {
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
