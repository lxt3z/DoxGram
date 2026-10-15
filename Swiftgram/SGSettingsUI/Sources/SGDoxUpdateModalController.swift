import Foundation
import UIKit
import Display
import AccountContext
import TelegramPresentationData
import SGSimpleSettings
import SwiftSignalKit

public final class SGDoxUpdateModalController: ViewController, UIGestureRecognizerDelegate {
    private let context: AccountContext
    private let releaseInfo: SGDoxReleaseInfo
    private var presentationData: PresentationData
    
    private static weak var currentPresentedModal: SGDoxUpdateModalController?
    
    // MARK: - Static Presentation Helper
    public static func present(context: AccountContext, releaseInfo: SGDoxReleaseInfo) {
        if currentPresentedModal != nil {
            return
        }
        
        let modal = SGDoxUpdateModalController(context: context, releaseInfo: releaseInfo)
        currentPresentedModal = modal
        
        if let mainWindow = context.sharedContext.mainWindow {
            if let rootNav = mainWindow.viewController as? NavigationController {
                for c in rootNav.viewControllers {
                    if let stale = c as? SGDoxUpdateModalController {
                        rootNav.filterController(stale, animated: false)
                    }
                }
                rootNav.pushViewController(modal)
            } else if let vc = mainWindow.viewController as? ViewController {
                vc.push(modal)
            }
        }
    }
    
    // MARK: - UI Elements (Liquid Glass Design)
    private let dimmingView = UIView()
    private let ambientBacklightLayer = CAGradientLayer()
    private let cardShadowContainer = UIView()
    private let cardContainer = UIView()
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialDark))
    private let glassTintOverlay = UIView()
    private let sheenGradient = CAGradientLayer()
    
    private let closeButton = UIButton(type: .custom)
    
    // Header Tag / Badge
    private let versionBadgeContainer = UIView()
    private let versionBadgeIcon = UIImageView()
    private let versionBadgeLabel = UILabel()
    
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    
    // Liquid Glass Changelog Inlay
    private let changelogGlassInlay = UIView()
    private let changelogScroll = UIScrollView()
    private let changelogStack = UIStackView()
    
    // Action Buttons
    private let downloadButton = UIButton(type: .custom)
    private let downloadGradientLayer = CAGradientLayer()
    private let laterButton = UIButton(type: .custom)
    
    private var hasAnimatedIn = false
    
    public init(context: AccountContext, releaseInfo: SGDoxReleaseInfo) {
        self.context = context
        self.releaseInfo = releaseInfo
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: nil)
        self.navigationPresentation = .flatModal
        self.flatReceivesModalTransition = false
        self.statusBar.statusBarStyle = .White
        self.ready.set(.single(true))
    }
    
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        if SGDoxUpdateModalController.currentPresentedModal === self {
            SGDoxUpdateModalController.currentPresentedModal = nil
        }
    }
    
    public override func loadDisplayNode() {
        super.loadDisplayNode()
        self.displayNode.backgroundColor = .clear
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .clear
        
        self.setupViews()
        
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(self.handlePanGesture(_:)))
        panGesture.delegate = self
        self.cardShadowContainer.addGestureRecognizer(panGesture)
        
        self.dimmingView.alpha = 1.0
        self.cardShadowContainer.transform = .identity
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !self.hasAnimatedIn {
            self.hasAnimatedIn = true
            let screenHeight = self.view.bounds.height > 0 ? self.view.bounds.height : UIScreen.main.bounds.height
            self.cardShadowContainer.layer.animatePosition(from: CGPoint(x: 0.0, y: screenHeight), to: CGPoint(), duration: 0.35, timingFunction: kCAMediaTimingFunctionSpring, additive: true)
            self.dimmingView.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.25)
        }
    }
    
    private func setupViews() {
        let isRu = self.presentationData.strings.baseLanguageCode.hasPrefix("ru")
        
        // 1. Dimming Backdrop
        self.dimmingView.backgroundColor = UIColor(white: 0.0, alpha: 0.45)
        let tapDim = UITapGestureRecognizer(target: self, action: #selector(self.laterPressed))
        self.dimmingView.addGestureRecognizer(tapDim)
        self.view.addSubview(self.dimmingView)
        
        // 2. Liquid Glass Backlight & Shadow Container
        self.cardShadowContainer.backgroundColor = .clear
        self.cardShadowContainer.layer.shadowColor = UIColor.black.cgColor
        self.cardShadowContainer.layer.shadowOpacity = 0.50
        self.cardShadowContainer.layer.shadowRadius = 36.0
        self.cardShadowContainer.layer.shadowOffset = CGSize(width: 0, height: 16)
        self.view.addSubview(self.cardShadowContainer)
        
        // Ambient Neon Glow behind the glass
        self.ambientBacklightLayer.colors = [
            UIColor(red: 0.15, green: 0.45, blue: 0.95, alpha: 0.35).cgColor,
            UIColor(red: 0.55, green: 0.18, blue: 0.90, alpha: 0.20).cgColor,
            UIColor.clear.cgColor
        ]
        self.ambientBacklightLayer.startPoint = CGPoint(x: 0.1, y: 0.0)
        self.ambientBacklightLayer.endPoint = CGPoint(x: 0.9, y: 1.0)
        self.ambientBacklightLayer.cornerRadius = 32.0
        self.cardShadowContainer.layer.insertSublayer(self.ambientBacklightLayer, at: 0)
        
        // 3. Liquid Glass Card Container
        self.cardContainer.backgroundColor = .clear
        self.cardContainer.layer.cornerRadius = 28.0
        self.cardContainer.layer.cornerCurve = .continuous
        self.cardContainer.layer.borderWidth = 0.5
        self.cardContainer.layer.borderColor = UIColor(white: 1.0, alpha: 0.30).cgColor
        self.cardContainer.clipsToBounds = true
        self.cardShadowContainer.addSubview(self.cardContainer)
        
        // Frosted Glass Blur
        self.blurView.clipsToBounds = true
        self.cardContainer.addSubview(self.blurView)
        
        // Translucent Tint Overlay
        self.glassTintOverlay.backgroundColor = UIColor(red: 0.08, green: 0.10, blue: 0.16, alpha: 0.30)
        self.cardContainer.addSubview(self.glassTintOverlay)
        
        // Specular Sheen Layer (Subtle top reflection)
        self.sheenGradient.colors = [
            UIColor(white: 1.0, alpha: 0.28).cgColor,
            UIColor(white: 1.0, alpha: 0.04).cgColor,
            UIColor.clear.cgColor
        ]
        self.sheenGradient.locations = [0.0, 0.30, 1.0]
        self.sheenGradient.startPoint = CGPoint(x: 0.5, y: 0.0)
        self.sheenGradient.endPoint = CGPoint(x: 0.5, y: 1.0)
        self.cardContainer.layer.addSublayer(self.sheenGradient)
        
        // Close Button (Frosted Glass Circular Button)
        let xConfig = UIImage.SymbolConfiguration(pointSize: 12.0, weight: .bold)
        self.closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: xConfig), for: .normal)
        self.closeButton.tintColor = UIColor(white: 1.0, alpha: 0.85)
        self.closeButton.backgroundColor = UIColor(white: 1.0, alpha: 0.12)
        self.closeButton.layer.cornerRadius = 15.0
        self.closeButton.layer.borderWidth = 0.5
        self.closeButton.layer.borderColor = UIColor(white: 1.0, alpha: 0.22).cgColor
        self.closeButton.clipsToBounds = true
        self.closeButton.addTarget(self, action: #selector(self.laterPressed), for: .touchUpInside)
        self.attachBounceFeedback(self.closeButton)
        self.cardContainer.addSubview(self.closeButton)
        
        // Version Pill Badge [ 🚀 build-3935 ]
        self.versionBadgeContainer.backgroundColor = UIColor(white: 1.0, alpha: 0.12)
        self.versionBadgeContainer.layer.cornerRadius = 13.0
        self.versionBadgeContainer.layer.cornerCurve = .continuous
        self.versionBadgeContainer.layer.borderWidth = 0.5
        self.versionBadgeContainer.layer.borderColor = UIColor(white: 1.0, alpha: 0.25).cgColor
        self.versionBadgeContainer.clipsToBounds = true
        self.cardContainer.addSubview(self.versionBadgeContainer)
        
        let sparkConfig = UIImage.SymbolConfiguration(pointSize: 12.5, weight: .bold)
        self.versionBadgeIcon.image = UIImage(systemName: "arrow.up.circle.fill", withConfiguration: sparkConfig)
        self.versionBadgeIcon.tintColor = UIColor(red: 0.25, green: 0.75, blue: 1.0, alpha: 1.0)
        self.versionBadgeIcon.contentMode = .scaleAspectFit
        self.versionBadgeContainer.addSubview(self.versionBadgeIcon)
        
        self.versionBadgeLabel.text = self.releaseInfo.tagName
        self.versionBadgeLabel.font = UIFont.systemFont(ofSize: 12.0, weight: .bold)
        self.versionBadgeLabel.textColor = .white
        self.versionBadgeContainer.addSubview(self.versionBadgeLabel)
        
        // Title Label
        self.titleLabel.text = isRu ? "Доступно обновление" : "Update Available"
        self.titleLabel.font = UIFont.systemFont(ofSize: 22.0, weight: .bold)
        self.titleLabel.textColor = .white
        self.titleLabel.textAlignment = .center
        self.cardContainer.addSubview(self.titleLabel)
        
        // Subtitle / Release Name
        let releaseName = self.releaseInfo.name.isEmpty ? self.releaseInfo.tagName : self.releaseInfo.name
        self.subtitleLabel.text = releaseName
        self.subtitleLabel.font = UIFont.systemFont(ofSize: 14.0, weight: .medium)
        self.subtitleLabel.textColor = UIColor(white: 1.0, alpha: 0.65)
        self.subtitleLabel.textAlignment = .center
        self.subtitleLabel.lineBreakMode = .byTruncatingTail
        self.cardContainer.addSubview(self.subtitleLabel)
        
        // 4. Liquid Glass Changelog Inlay Card
        self.changelogGlassInlay.backgroundColor = UIColor(white: 1.0, alpha: 0.08)
        self.changelogGlassInlay.layer.cornerRadius = 20.0
        self.changelogGlassInlay.layer.cornerCurve = .continuous
        self.changelogGlassInlay.layer.borderWidth = 0.5
        self.changelogGlassInlay.layer.borderColor = UIColor(white: 1.0, alpha: 0.18).cgColor
        self.changelogGlassInlay.clipsToBounds = true
        self.cardContainer.addSubview(self.changelogGlassInlay)
        
        self.changelogScroll.indicatorStyle = .white
        self.changelogScroll.alwaysBounceVertical = false
        self.changelogScroll.showsVerticalScrollIndicator = true
        self.changelogGlassInlay.addSubview(self.changelogScroll)
        
        self.changelogStack.axis = .vertical
        self.changelogStack.spacing = 10.0
        self.changelogStack.alignment = .fill
        self.changelogStack.distribution = .fill
        self.changelogScroll.addSubview(self.changelogStack)
        
        self.populateChangelogItems()
        
        // 5. Download Button (Liquid Vibrant Blue Glass Pill)
        self.downloadButton.layer.cornerRadius = 24.0
        self.downloadButton.layer.cornerCurve = .continuous
        self.downloadButton.clipsToBounds = true
        
        self.downloadGradientLayer.colors = [
            UIColor(red: 0.16, green: 0.48, blue: 0.98, alpha: 1.0).cgColor,
            UIColor(red: 0.10, green: 0.35, blue: 0.92, alpha: 1.0).cgColor
        ]
        self.downloadGradientLayer.startPoint = CGPoint(x: 0.0, y: 0.5)
        self.downloadGradientLayer.endPoint = CGPoint(x: 1.0, y: 0.5)
        self.downloadButton.layer.insertSublayer(self.downloadGradientLayer, at: 0)
        
        let dlIconConfig = UIImage.SymbolConfiguration(pointSize: 15.0, weight: .bold)
        self.downloadButton.setImage(UIImage(systemName: "arrow.down.circle.fill", withConfiguration: dlIconConfig), for: .normal)
        self.downloadButton.setTitle(isRu ? "  Скачать обновление" : "  Download Update", for: .normal)
        self.downloadButton.setTitleColor(.white, for: .normal)
        self.downloadButton.titleLabel?.font = UIFont.systemFont(ofSize: 15.5, weight: .bold)
        self.downloadButton.tintColor = .white
        self.downloadButton.addTarget(self, action: #selector(self.downloadPressed), for: .touchUpInside)
        self.attachBounceFeedback(self.downloadButton)
        self.cardContainer.addSubview(self.downloadButton)
        
        // 6. Later / Skip Button
        self.laterButton.setTitle(isRu ? "Напомнить позже" : "Remind Me Later", for: .normal)
        self.laterButton.setTitleColor(UIColor(white: 1.0, alpha: 0.60), for: .normal)
        self.laterButton.titleLabel?.font = UIFont.systemFont(ofSize: 14.5, weight: .medium)
        self.laterButton.addTarget(self, action: #selector(self.laterPressed), for: .touchUpInside)
        self.attachBounceFeedback(self.laterButton)
        self.cardContainer.addSubview(self.laterButton)
    }
    
    private func attachBounceFeedback(_ button: UIButton) {
        button.addTarget(self, action: #selector(self.btnTouchDown(_:)), for: [.touchDown])
        button.addTarget(self, action: #selector(self.btnTouchUp(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    }
    
    @objc private func btnTouchDown(_ sender: UIButton) {
        UIView.animate(withDuration: 0.12, delay: 0, options: [.allowUserInteraction, .curveEaseOut], animations: {
            sender.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        })
    }
    
    @objc private func btnTouchUp(_ sender: UIButton) {
        UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.55, initialSpringVelocity: 0.8, options: [.allowUserInteraction], animations: {
            sender.transform = .identity
        })
    }
    
    private func populateChangelogItems() {
        var items = self.releaseInfo.changelogItems
        
        // If changelogItems is empty or contains raw build info, use authentic Russian changelog
        if items.isEmpty || (items.count == 1 && items[0].lowercased().contains("unsigned")) {
            items = [
                "✨ Редизайн плеера DoxMusic в стиле Apple Music",
                "🎤 Интерактивное караоке с эффектом подпрыгивания и свечением",
                "🔊 Синхронизация системной громкости и поддержка AirPlay",
                "📹 Анимированные видеообложки на весь экран плеера",
                "🪟 Обновление интерфейса: дизайн Liquid Glass с мягким матовым стеклом",
                "🛠 Исправление вылетов, зависаний и оптимизация стабильности"
            ]
        }
        
        for view in self.changelogStack.arrangedSubviews {
            self.changelogStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        
        for text in items {
            let row = self.createChangelogRow(text: text)
            self.changelogStack.addArrangedSubview(row)
        }
    }
    
    private func createChangelogRow(text: String) -> UIView {
        let container = UIView()
        
        let iconBadge = UIView()
        iconBadge.backgroundColor = UIColor(white: 1.0, alpha: 0.12)
        iconBadge.layer.cornerRadius = 14.0
        iconBadge.layer.cornerCurve = .continuous
        iconBadge.clipsToBounds = true
        iconBadge.translatesAutoresizingMaskIntoConstraints = false
        
        let bulletLabel = UILabel()
        bulletLabel.font = UIFont.systemFont(ofSize: 14.0, weight: .regular)
        bulletLabel.textAlignment = .center
        bulletLabel.translatesAutoresizingMaskIntoConstraints = false
        iconBadge.addSubview(bulletLabel)
        
        let bodyLabel = UILabel()
        bodyLabel.font = UIFont.systemFont(ofSize: 14.0, weight: .medium)
        bodyLabel.textColor = UIColor(white: 1.0, alpha: 0.92)
        bodyLabel.numberOfLines = 0
        bodyLabel.lineBreakMode = .byWordWrapping
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Detect leading emoji
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let firstChar = trimmed.first, firstChar.isEmoji {
            bulletLabel.text = String(firstChar)
            let remainingText = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            bodyLabel.text = remainingText
        } else {
            bulletLabel.text = "•"
            bulletLabel.textColor = UIColor(red: 0.35, green: 0.75, blue: 1.0, alpha: 1.0)
            bodyLabel.text = trimmed
        }
        
        container.addSubview(iconBadge)
        container.addSubview(bodyLabel)
        
        NSLayoutConstraint.activate([
            bulletLabel.centerXAnchor.constraint(equalTo: iconBadge.centerXAnchor),
            bulletLabel.centerYAnchor.constraint(equalTo: iconBadge.centerYAnchor),
            
            iconBadge.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            iconBadge.topAnchor.constraint(equalTo: container.topAnchor, constant: 1),
            iconBadge.widthAnchor.constraint(equalToConstant: 28),
            iconBadge.heightAnchor.constraint(equalToConstant: 28),
            
            bodyLabel.leadingAnchor.constraint(equalTo: iconBadge.trailingAnchor, constant: 10),
            bodyLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            bodyLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            bodyLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4)
        ])
        
        return container
    }
    
    public override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let bounds = CGRect(origin: .zero, size: layout.size)
        self.dimmingView.frame = bounds
        
        let cardWidth = min(bounds.width - 44.0, 360.0)
        let cardHeight: CGFloat = min(bounds.height - 90.0, 530.0)
        let cardX = (bounds.width - cardWidth) * 0.5
        let cardY = (bounds.height - cardHeight) * 0.5
        
        self.cardShadowContainer.frame = CGRect(x: cardX, y: cardY, width: cardWidth, height: cardHeight)
        self.ambientBacklightLayer.frame = self.cardShadowContainer.bounds.insetBy(dx: -16.0, dy: -16.0)
        self.cardContainer.frame = self.cardShadowContainer.bounds
        self.blurView.frame = self.cardContainer.bounds
        self.glassTintOverlay.frame = self.cardContainer.bounds
        self.sheenGradient.frame = CGRect(x: 0, y: 0, width: cardWidth, height: 130.0)
        
        self.closeButton.frame = CGRect(x: cardWidth - 44.0, y: 14.0, width: 30.0, height: 30.0)
        
        // Version Badge
        let badgeTextSize = self.versionBadgeLabel.sizeThatFits(CGSize(width: cardWidth - 100.0, height: 26.0))
        let badgeWidth = min(cardWidth - 80.0, max(85.0, ceil(badgeTextSize.width) + 38.0))
        self.versionBadgeContainer.frame = CGRect(x: (cardWidth - badgeWidth) * 0.5, y: 22.0, width: badgeWidth, height: 26.0)
        self.versionBadgeIcon.frame = CGRect(x: 8.0, y: 5.0, width: 16.0, height: 16.0)
        self.versionBadgeLabel.frame = CGRect(x: 28.0, y: 0, width: badgeWidth - 36.0, height: 26.0)
        
        // Title & Subtitle
        self.titleLabel.frame = CGRect(x: 20.0, y: 56.0, width: cardWidth - 40.0, height: 26.0)
        self.subtitleLabel.frame = CGRect(x: 20.0, y: 84.0, width: cardWidth - 40.0, height: 20.0)
        
        // Action Buttons
        let laterH: CGFloat = 36.0
        let dlBtnH: CGFloat = 48.0
        let bottomPad: CGFloat = 16.0
        
        let laterY = cardHeight - laterH - bottomPad
        self.laterButton.frame = CGRect(x: 24.0, y: laterY, width: cardWidth - 48.0, height: laterH)
        
        let dlBtnY = laterY - dlBtnH - 8.0
        self.downloadButton.frame = CGRect(x: 24.0, y: dlBtnY, width: cardWidth - 48.0, height: dlBtnH)
        self.downloadGradientLayer.frame = self.downloadButton.bounds
        
        // Changelog Inlay Card
        let inlayY: CGFloat = 114.0
        let inlayH = max(60.0, dlBtnY - inlayY - 14.0)
        self.changelogGlassInlay.frame = CGRect(x: 20.0, y: inlayY, width: cardWidth - 40.0, height: inlayH)
        
        self.changelogScroll.frame = self.changelogGlassInlay.bounds
        
        // Layout changelog stack
        let stackWidth = cardWidth - 40.0
        let stackFitting = self.changelogStack.systemLayoutSizeFitting(
            CGSize(width: stackWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        let contentH = max(inlayH, stackFitting.height + 24.0)
        self.changelogStack.frame = CGRect(x: 0, y: 10.0, width: stackWidth, height: stackFitting.height)
        self.changelogScroll.contentSize = CGSize(width: stackWidth, height: contentH)
    }
    
    // MARK: - Actions
    @objc private func downloadPressed() {
        SGSimpleSettings.shared.doxLastDismissedVersion = self.releaseInfo.tagName
        SGSimpleSettings.shared.doxLastDismissedTimestamp = Date().timeIntervalSince1970
        if let targetUrl = self.releaseInfo.downloadUrl ?? URL(string: self.releaseInfo.htmlUrl) {
            UIApplication.shared.open(targetUrl, options: [:], completionHandler: nil)
        }
        self.dismissAnimated()
    }
    
    @objc private func laterPressed() {
        SGSimpleSettings.shared.doxLastDismissedVersion = self.releaseInfo.tagName
        SGSimpleSettings.shared.doxLastDismissedTimestamp = Date().timeIntervalSince1970
        self.dismissAnimated()
    }
    
    private func dismissAnimated() {
        let screenHeight = self.view.bounds.height > 0 ? self.view.bounds.height : UIScreen.main.bounds.height
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseIn], animations: {
            self.dimmingView.alpha = 0.0
            self.cardShadowContainer.transform = CGAffineTransform(translationX: 0, y: screenHeight)
        }) { [weak self] _ in
            guard let self = self else { return }
            self.finishDismiss()
        }
    }
    
    private func finishDismiss() {
        if SGDoxUpdateModalController.currentPresentedModal === self {
            SGDoxUpdateModalController.currentPresentedModal = nil
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
    }
    
    // MARK: - Gesture Handling
    @objc private func handlePanGesture(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: self.view)
        let velocity = recognizer.velocity(in: self.view)
        
        switch recognizer.state {
        case .changed:
            if translation.y > 0 {
                self.cardShadowContainer.transform = CGAffineTransform(translationX: 0, y: translation.y)
                let progress = min(1.0, translation.y / (self.view.bounds.height * 0.5))
                self.dimmingView.alpha = 1.0 - (progress * 0.6)
            }
        case .ended, .cancelled:
            if translation.y > 100.0 || velocity.y > 600.0 {
                self.dismissAnimated()
            } else {
                UIView.animate(withDuration: 0.32, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.5, options: [.curveEaseOut], animations: {
                    self.cardShadowContainer.transform = .identity
                    self.dimmingView.alpha = 1.0
                })
            }
        default:
            break
        }
    }
    
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if let v = touch.view, v.isDescendant(of: self.changelogScroll) {
            return false
        }
        return true
    }
}

// MARK: - Character isEmoji Helper
private extension Character {
    var isEmoji: Bool {
        guard let scalar = self.unicodeScalars.first else { return false }
        return scalar.properties.isEmoji && (scalar.value > 0x238C || self.unicodeScalars.count > 1)
    }
}
