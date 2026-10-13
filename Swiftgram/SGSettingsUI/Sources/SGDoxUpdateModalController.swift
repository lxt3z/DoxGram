import Foundation
import UIKit
import Display
import AccountContext
import TelegramPresentationData
import SGSimpleSettings

public final class SGDoxUpdateModalController: ViewController {
    private let context: AccountContext
    private let releaseInfo: SGDoxReleaseInfo
    private var presentationData: PresentationData
    
    // MARK: - UI Elements
    private let dimmingView = UIView()
    private let cardContainer = UIView()
    private let blurView = UIVisualEffectView()
    private let sheenGradient = CAGradientLayer()
    
    private let closeButton = UIButton(type: .system)
    
    // Header tag / version
    private let versionBadgeContainer = UIView()
    private let versionBadgeIcon = UIImageView()
    private let versionBadgeLabel = UILabel()
    
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    
    // Changelog container
    private let changelogScroll = UIScrollView()
    private let changelogTextLabel = UILabel()
    
    // Buttons
    private let downloadButton = UIButton(type: .system)
    private let downloadGradientLayer = CAGradientLayer()
    private let laterButton = UIButton(type: .system)
    
    private var hasAnimatedIn = false
    
    public init(context: AccountContext, releaseInfo: SGDoxReleaseInfo) {
        self.context = context
        self.releaseInfo = releaseInfo
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
    
    public override func loadDisplayNode() {
        super.loadDisplayNode()
        self.displayNode.backgroundColor = .clear
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .clear
        
        self.setupViews()
        
        // Pan gesture to dismiss
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(self.handlePanGesture(_:)))
        self.cardContainer.addGestureRecognizer(panGesture)
        
        // Initial state offscreen
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
    
    private func setupViews() {
        let isRu = self.presentationData.strings.baseLanguageCode.hasPrefix("ru")
        
        // Dimming backdrop
        self.dimmingView.backgroundColor = UIColor(white: 0.0, alpha: 0.60)
        let tapDim = UITapGestureRecognizer(target: self, action: #selector(self.laterPressed))
        self.dimmingView.addGestureRecognizer(tapDim)
        self.view.addSubview(self.dimmingView)
        
        // Liquid Glass Card
        self.cardContainer.layer.cornerRadius = 30.0
        self.cardContainer.layer.cornerCurve = .continuous
        self.cardContainer.layer.borderWidth = 0.75
        self.cardContainer.layer.borderColor = UIColor(white: 1.0, alpha: 0.22).cgColor
        self.cardContainer.clipsToBounds = true
        self.cardContainer.backgroundColor = UIColor(red: 0.10, green: 0.11, blue: 0.16, alpha: 0.86)
        
        self.blurView.effect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        self.cardContainer.addSubview(self.blurView)
        
        // Specular Sheen Layer
        self.sheenGradient.colors = [
            UIColor(white: 1.0, alpha: 0.32).cgColor,
            UIColor(white: 1.0, alpha: 0.06).cgColor,
            UIColor.clear.cgColor
        ]
        self.sheenGradient.locations = [0.0, 0.32, 1.0]
        self.sheenGradient.startPoint = CGPoint(x: 0.5, y: 0.0)
        self.sheenGradient.endPoint = CGPoint(x: 0.5, y: 1.0)
        self.cardContainer.layer.addSublayer(self.sheenGradient)
        
        // Close Button
        let xConfig = UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        self.closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: xConfig), for: .normal)
        self.closeButton.tintColor = UIColor(white: 1.0, alpha: 0.80)
        self.closeButton.backgroundColor = UIColor(white: 1.0, alpha: 0.12)
        self.closeButton.layer.cornerRadius = 15.0
        self.closeButton.clipsToBounds = true
        self.closeButton.addTarget(self, action: #selector(self.laterPressed), for: .touchUpInside)
        self.cardContainer.addSubview(self.closeButton)
        
        // Version Pill Badge: [ 🚀 DoxGram vX.Y.Z ]
        self.versionBadgeContainer.backgroundColor = UIColor(white: 1.0, alpha: 0.12)
        self.versionBadgeContainer.layer.cornerRadius = 13.0
        self.versionBadgeContainer.layer.cornerCurve = .continuous
        self.versionBadgeContainer.layer.borderWidth = 0.5
        self.versionBadgeContainer.layer.borderColor = UIColor(white: 1.0, alpha: 0.20).cgColor
        self.versionBadgeContainer.clipsToBounds = true
        self.cardContainer.addSubview(self.versionBadgeContainer)
        
        let sparkConfig = UIImage.SymbolConfiguration(pointSize: 12.0, weight: .bold)
        self.versionBadgeIcon.image = UIImage(systemName: "arrow.up.circle.fill", withConfiguration: sparkConfig)
        self.versionBadgeIcon.tintColor = UIColor(red: 0.35, green: 0.78, blue: 1.0, alpha: 1.0)
        self.versionBadgeIcon.contentMode = .scaleAspectFit
        self.versionBadgeContainer.addSubview(self.versionBadgeIcon)
        
        self.versionBadgeLabel.text = self.releaseInfo.tagName
        self.versionBadgeLabel.font = UIFont.systemFont(ofSize: 12.0, weight: .semibold)
        self.versionBadgeLabel.textColor = .white
        self.versionBadgeContainer.addSubview(self.versionBadgeLabel)
        
        // Title Label
        self.titleLabel.text = isRu ? "Доступно обновление" : "Update Available"
        self.titleLabel.font = UIFont.systemFont(ofSize: 20.0, weight: .bold)
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
        
        // Changelog Scroll & Label
        self.changelogScroll.backgroundColor = UIColor(white: 0.0, alpha: 0.22)
        self.changelogScroll.layer.cornerRadius = 16.0
        self.changelogScroll.layer.cornerCurve = .continuous
        self.changelogScroll.layer.borderWidth = 0.5
        self.changelogScroll.layer.borderColor = UIColor(white: 1.0, alpha: 0.10).cgColor
        self.changelogScroll.clipsToBounds = true
        self.changelogScroll.indicatorStyle = .white
        self.changelogScroll.alwaysBounceVertical = true
        self.cardContainer.addSubview(self.changelogScroll)
        
        let cleanedBody = self.cleanMarkdown(self.releaseInfo.body)
        self.changelogTextLabel.text = cleanedBody.isEmpty ? (isRu ? "Улучшения стабильности и новые функции." : "Bug fixes and performance improvements.") : cleanedBody
        self.changelogTextLabel.font = UIFont.systemFont(ofSize: 13.5, weight: .regular)
        self.changelogTextLabel.textColor = UIColor(white: 1.0, alpha: 0.88)
        self.changelogTextLabel.numberOfLines = 0
        self.changelogTextLabel.lineBreakMode = .byWordWrapping
        self.changelogScroll.addSubview(self.changelogTextLabel)
        
        // Download Button
        self.downloadButton.layer.cornerRadius = 23.0
        self.downloadButton.layer.cornerCurve = .continuous
        self.downloadButton.clipsToBounds = true
        
        self.downloadGradientLayer.colors = [
            UIColor(red: 0.20, green: 0.55, blue: 0.98, alpha: 1.0).cgColor,
            UIColor(red: 0.12, green: 0.38, blue: 0.92, alpha: 1.0).cgColor
        ]
        self.downloadGradientLayer.startPoint = CGPoint(x: 0.0, y: 0.5)
        self.downloadGradientLayer.endPoint = CGPoint(x: 1.0, y: 0.5)
        self.downloadButton.layer.insertSublayer(self.downloadGradientLayer, at: 0)
        
        let dlIconConfig = UIImage.SymbolConfiguration(pointSize: 14.5, weight: .bold)
        self.downloadButton.setImage(UIImage(systemName: "arrow.down.circle.fill", withConfiguration: dlIconConfig), for: .normal)
        self.downloadButton.setTitle(isRu ? "  Скачать обновление" : "  Download Update", for: .normal)
        self.downloadButton.setTitleColor(.white, for: .normal)
        self.downloadButton.titleLabel?.font = UIFont.systemFont(ofSize: 15.5, weight: .bold)
        self.downloadButton.tintColor = .white
        self.downloadButton.addTarget(self, action: #selector(self.downloadPressed), for: .touchUpInside)
        self.cardContainer.addSubview(self.downloadButton)
        
        // Later / Skip Button
        self.laterButton.setTitle(isRu ? "Напомнить позже" : "Remind Me Later", for: .normal)
        self.laterButton.setTitleColor(UIColor(white: 1.0, alpha: 0.60), for: .normal)
        self.laterButton.titleLabel?.font = UIFont.systemFont(ofSize: 14.0, weight: .medium)
        self.laterButton.addTarget(self, action: #selector(self.laterPressed), for: .touchUpInside)
        self.cardContainer.addSubview(self.laterButton)
        
        self.view.addSubview(self.cardContainer)
    }
    
    private func cleanMarkdown(_ text: String) -> String {
        var result = text
        // Clean simple bold/italic markers
        result = result.replacingOccurrences(of: "### ", with: "• ")
        result = result.replacingOccurrences(of: "## ", with: "• ")
        result = result.replacingOccurrences(of: "# ", with: "• ")
        result = result.replacingOccurrences(of: "**", with: "")
        result = result.replacingOccurrences(of: "__", with: "")
        result = result.replacingOccurrences(of: "`", with: "")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    public override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let bounds = CGRect(origin: .zero, size: layout.size)
        self.dimmingView.frame = bounds
        
        let cardWidth = min(bounds.width - 40.0, 350.0)
        let cardHeight: CGFloat = min(bounds.height - 100.0, 480.0)
        let cardX = (bounds.width - cardWidth) * 0.5
        let cardY = (bounds.height - cardHeight) * 0.5
        
        self.cardContainer.frame = CGRect(x: cardX, y: cardY, width: cardWidth, height: cardHeight)
        self.blurView.frame = self.cardContainer.bounds
        self.sheenGradient.frame = CGRect(x: 0, y: 0, width: cardWidth, height: 140.0)
        
        self.closeButton.frame = CGRect(x: cardWidth - 42.0, y: 12.0, width: 30.0, height: 30.0)
        
        // Badge
        let badgeTextSize = self.versionBadgeLabel.sizeThatFits(CGSize(width: cardWidth - 100.0, height: 26.0))
        let badgeWidth = min(cardWidth - 80.0, max(85.0, ceil(badgeTextSize.width) + 38.0))
        self.versionBadgeContainer.frame = CGRect(x: (cardWidth - badgeWidth) * 0.5, y: 22.0, width: badgeWidth, height: 26.0)
        self.versionBadgeIcon.frame = CGRect(x: 8.0, y: 5.0, width: 16.0, height: 16.0)
        self.versionBadgeLabel.frame = CGRect(x: 28.0, y: 0, width: badgeWidth - 36.0, height: 26.0)
        
        // Title & Subtitle
        self.titleLabel.frame = CGRect(x: 20.0, y: 56.0, width: cardWidth - 40.0, height: 24.0)
        self.subtitleLabel.frame = CGRect(x: 20.0, y: 82.0, width: cardWidth - 40.0, height: 18.0)
        
        // Buttons at bottom
        let laterHeight: CGFloat = 32.0
        let dlHeight: CGFloat = 46.0
        let bottomMargin: CGFloat = 16.0
        
        self.laterButton.frame = CGRect(x: 24.0, y: cardHeight - bottomMargin - laterHeight, width: cardWidth - 48.0, height: laterHeight)
        self.downloadButton.frame = CGRect(x: 24.0, y: self.laterButton.frame.minY - dlHeight - 8.0, width: cardWidth - 48.0, height: dlHeight)
        self.downloadGradientLayer.frame = self.downloadButton.bounds
        
        // Scroll view fills remaining space
        let scrollY: CGFloat = 110.0
        let scrollHeight = max(80.0, self.downloadButton.frame.minY - scrollY - 14.0)
        self.changelogScroll.frame = CGRect(x: 20.0, y: scrollY, width: cardWidth - 40.0, height: scrollHeight)
        
        // Text inside scroll
        let textPadding: CGFloat = 14.0
        let textWidth = self.changelogScroll.bounds.width - (textPadding * 2)
        let calcSize = self.changelogTextLabel.sizeThatFits(CGSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude))
        self.changelogTextLabel.frame = CGRect(x: textPadding, y: textPadding, width: textWidth, height: calcSize.height)
        self.changelogScroll.contentSize = CGSize(width: self.changelogScroll.bounds.width, height: calcSize.height + (textPadding * 2))
    }
    
    @objc private func downloadPressed() {
        SGSimpleSettings.shared.doxLastDismissedVersion = self.releaseInfo.tagName
        if let targetUrl = self.releaseInfo.downloadUrl ?? URL(string: self.releaseInfo.htmlUrl) {
            UIApplication.shared.open(targetUrl, options: [:], completionHandler: nil)
        }
        self.dismissAnimated()
    }
    
    @objc private func laterPressed() {
        SGSimpleSettings.shared.doxLastDismissedVersion = self.releaseInfo.tagName
        self.dismissAnimated()
    }
    
    private func dismissAnimated() {
        let screenHeight = UIScreen.main.bounds.height
        UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseIn], animations: {
            self.dimmingView.alpha = 0.0
            self.cardContainer.transform = CGAffineTransform(translationX: 0, y: screenHeight > 0 ? screenHeight : 800)
        }) { [weak self] _ in
            self?.dismiss()
        }
    }
    
    @objc private func handlePanGesture(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: self.view)
        let velocity = recognizer.velocity(in: self.view)
        
        switch recognizer.state {
        case .changed:
            if translation.y > 0 {
                self.cardContainer.transform = CGAffineTransform(translationX: 0, y: translation.y)
                let progress = min(1.0, max(0.0, translation.y / 300.0))
                self.dimmingView.alpha = 1.0 - (progress * 0.6)
            }
        case .ended, .cancelled:
            if translation.y > 120.0 || velocity.y > 700.0 {
                self.laterPressed()
            } else {
                UIView.animate(withDuration: 0.32, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.5, options: [.curveEaseOut], animations: {
                    self.cardContainer.transform = .identity
                    self.dimmingView.alpha = 1.0
                }, completion: nil)
            }
        default:
            break
        }
    }
}
