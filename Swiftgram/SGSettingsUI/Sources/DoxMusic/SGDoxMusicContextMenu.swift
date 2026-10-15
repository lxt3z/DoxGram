import Foundation
import UIKit
import Display

public struct SGDoxMusicMenuItem {
    public let iconName: String
    public let title: String
    public let subtitle: String?
    public let isDestructive: Bool
    public let action: () -> Void
    
    public init(iconName: String, title: String, subtitle: String? = nil, isDestructive: Bool = false, action: @escaping () -> Void) {
        self.iconName = iconName
        self.title = title
        self.subtitle = subtitle
        self.isDestructive = isDestructive
        self.action = action
    }
}

private final class SGDoxMenuButton: UIButton {
    var onTap: (() -> Void)?
    var enablesHighlight: Bool = true
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.addTarget(self, action: #selector(self.pressed), for: .touchUpInside)
        self.addTarget(self, action: #selector(self.touchDown), for: [.touchDown, .touchDragEnter])
        self.addTarget(self, action: #selector(self.touchUp), for: [.touchDragExit, .touchCancel, .touchUpInside, .touchUpOutside])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func pressed() {
        self.backgroundColor = .clear
        self.onTap?()
    }
    
    @objc private func touchDown() {
        if self.enablesHighlight {
            self.backgroundColor = UIColor(white: 1.0, alpha: 0.12)
        }
    }
    
    @objc private func touchUp() {
        self.backgroundColor = .clear
    }
}

private final class SGDoxMenuTopButton: UIButton {
    var onTap: (() -> Void)?
    private let iconImageView = UIImageView()
    private let label = UILabel()
    
    init(icon: UIImage?, title: String, tintColor: UIColor = .white) {
        super.init(frame: .zero)
        self.iconImageView.image = icon
        self.iconImageView.tintColor = tintColor
        self.iconImageView.contentMode = .scaleAspectFit
        self.addSubview(self.iconImageView)
        
        self.label.text = title
        self.label.textColor = tintColor
        self.label.font = UIFont.systemFont(ofSize: 12.0, weight: .semibold)
        self.label.textAlignment = .center
        self.addSubview(self.label)
        
        self.addTarget(self, action: #selector(self.pressed), for: .touchUpInside)
        self.addTarget(self, action: #selector(self.touchDown), for: [.touchDown, .touchDragEnter])
        self.addTarget(self, action: #selector(self.touchUp), for: [.touchDragExit, .touchCancel, .touchUpInside, .touchUpOutside])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func update(icon: UIImage?, title: String, tintColor: UIColor) {
        self.iconImageView.image = icon
        self.iconImageView.tintColor = tintColor
        self.label.text = title
        self.label.textColor = tintColor
    }
    
    @objc private func pressed() {
        self.backgroundColor = .clear
        self.onTap?()
    }
    
    @objc private func touchDown() {
        self.backgroundColor = UIColor(white: 1.0, alpha: 0.12)
    }
    
    @objc private func touchUp() {
        self.backgroundColor = .clear
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        let iconSize: CGFloat = 22.0
        let iconY = max(4.0, (self.bounds.height - (iconSize + 4.0 + 15.0)) * 0.5)
        self.iconImageView.frame = CGRect(x: (self.bounds.width - iconSize) * 0.5, y: iconY, width: iconSize, height: iconSize)
        self.label.frame = CGRect(x: 2.0, y: self.iconImageView.frame.maxY + 3.0, width: self.bounds.width - 4.0, height: 16.0)
    }
}

public final class SGDoxMusicContextMenu: UIView {
    private let dimmingView = UIView()
    private let cardView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialDark))
    private let cardTintOverlay = UIView()
    private let contentStack = UIStackView()
    
    // Top capsule buttons (Favorite | Share)
    private let topCapsuleView = UIView()
    private let favoriteButton = SGDoxMenuTopButton(icon: nil, title: "")
    private let shareButton = SGDoxMenuTopButton(icon: nil, title: "")
    private let capsuleDivider = UIView()
    
    public static func show(
        in parentView: UIView,
        sourceButton: UIButton,
        isFavorite: Bool,
        onToggleFavorite: @escaping () -> Void,
        onShare: @escaping () -> Void,
        items: [SGDoxMusicMenuItem]
    ) {
        let menu = SGDoxMusicContextMenu(frame: parentView.bounds)
        parentView.addSubview(menu)
        menu.present(from: sourceButton, isFavorite: isFavorite, onToggleFavorite: onToggleFavorite, onShare: onShare, items: items)
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        self.dimmingView.frame = frame
        self.dimmingView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.dimmingView.backgroundColor = UIColor(white: 0.0, alpha: 0.40)
        self.dimmingView.alpha = 0.0
        self.dimmingView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.backgroundTapped)))
        self.addSubview(self.dimmingView)
        
        self.cardView.clipsToBounds = true
        self.cardView.layer.cornerRadius = 24.0
        self.cardView.layer.cornerCurve = .continuous
        self.cardView.layer.borderWidth = 0.5
        self.cardView.layer.borderColor = UIColor(white: 1.0, alpha: 0.22).cgColor
        self.cardView.layer.shadowColor = UIColor.black.cgColor
        self.cardView.layer.shadowOpacity = 0.50
        self.cardView.layer.shadowRadius = 30.0
        self.cardView.layer.shadowOffset = CGSize(width: 0, height: 14)
        self.addSubview(self.cardView)
        
        self.cardTintOverlay.backgroundColor = UIColor(red: 0.10, green: 0.12, blue: 0.18, alpha: 0.35)
        self.cardView.contentView.addSubview(self.cardTintOverlay)
        
        self.contentStack.axis = .vertical
        self.contentStack.spacing = 0
        self.contentStack.alignment = .fill
        self.contentStack.distribution = .fill
        self.cardView.contentView.addSubview(self.contentStack)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func present(
        from sourceButton: UIButton,
        isFavorite: Bool,
        onToggleFavorite: @escaping () -> Void,
        onShare: @escaping () -> Void,
        items: [SGDoxMusicMenuItem]
    ) {
        // Setup top capsule
        self.topCapsuleView.backgroundColor = UIColor(white: 1.0, alpha: 0.10)
        self.topCapsuleView.layer.cornerRadius = 16.0
        self.topCapsuleView.layer.cornerCurve = .continuous
        self.topCapsuleView.clipsToBounds = true
        self.topCapsuleView.translatesAutoresizingMaskIntoConstraints = false
        self.topCapsuleView.heightAnchor.constraint(equalToConstant: 62.0).isActive = true
        
        let starConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        let starImg = UIImage(systemName: isFavorite ? "star.fill" : "star", withConfiguration: starConfig)
        let starColor = isFavorite ? UIColor(red: 1.0, green: 0.28, blue: 0.38, alpha: 1.0) : .white
        self.favoriteButton.update(icon: starImg, title: isFavorite ? "В избранном" : "Избранное", tintColor: starColor)
        self.favoriteButton.onTap = { [weak self] in
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            self?.dismissAnimated(completion: onToggleFavorite)
        }
        
        let shareConfig = UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold)
        let shareImg = UIImage(systemName: "square.and.arrow.up", withConfiguration: shareConfig)
        self.shareButton.update(icon: shareImg, title: "Поделиться", tintColor: .white)
        self.shareButton.onTap = { [weak self] in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            self?.dismissAnimated(completion: onShare)
        }
        
        self.capsuleDivider.backgroundColor = UIColor(white: 1.0, alpha: 0.14)
        
        self.topCapsuleView.addSubview(self.favoriteButton)
        self.topCapsuleView.addSubview(self.shareButton)
        self.topCapsuleView.addSubview(self.capsuleDivider)
        
        let capsuleContainer = UIView()
        capsuleContainer.layoutMargins = UIEdgeInsets(top: 10, left: 12, bottom: 8, right: 12)
        capsuleContainer.addSubview(self.topCapsuleView)
        
        self.topCapsuleView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            self.topCapsuleView.topAnchor.constraint(equalTo: capsuleContainer.layoutMarginsGuide.topAnchor),
            self.topCapsuleView.bottomAnchor.constraint(equalTo: capsuleContainer.layoutMarginsGuide.bottomAnchor),
            self.topCapsuleView.leadingAnchor.constraint(equalTo: capsuleContainer.layoutMarginsGuide.leadingAnchor),
            self.topCapsuleView.trailingAnchor.constraint(equalTo: capsuleContainer.layoutMarginsGuide.trailingAnchor),
            self.topCapsuleView.heightAnchor.constraint(equalToConstant: 62.0)
        ])
        
        self.contentStack.addArrangedSubview(capsuleContainer)
        
        // Horizontal divider under capsule
        let sep = UIView()
        sep.backgroundColor = UIColor(white: 1.0, alpha: 0.12)
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        self.contentStack.addArrangedSubview(sep)
        
        // Add items
        for (idx, item) in items.enumerated() {
            let row = self.createRow(for: item)
            self.contentStack.addArrangedSubview(row)
            
            if idx < items.count - 1 {
                let rowDividerContainer = UIView()
                rowDividerContainer.translatesAutoresizingMaskIntoConstraints = false
                rowDividerContainer.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
                
                let rowDivider = UIView()
                rowDivider.backgroundColor = UIColor(white: 1.0, alpha: 0.08)
                rowDivider.translatesAutoresizingMaskIntoConstraints = false
                rowDividerContainer.addSubview(rowDivider)
                
                NSLayoutConstraint.activate([
                    rowDivider.leadingAnchor.constraint(equalTo: rowDividerContainer.leadingAnchor, constant: 52),
                    rowDivider.trailingAnchor.constraint(equalTo: rowDividerContainer.trailingAnchor),
                    rowDivider.topAnchor.constraint(equalTo: rowDividerContainer.topAnchor),
                    rowDivider.bottomAnchor.constraint(equalTo: rowDividerContainer.bottomAnchor)
                ])
                
                self.contentStack.addArrangedSubview(rowDividerContainer)
            }
        }
        
        // Layout card
        let cardWidth: CGFloat = min(300.0, self.bounds.width - 40.0)
        self.contentStack.frame = CGRect(x: 0, y: 0, width: cardWidth, height: 1000)
        let neededSize = self.contentStack.systemLayoutSizeFitting(
            CGSize(width: cardWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        
        let cardHeight = neededSize.height
        self.contentStack.frame = CGRect(origin: .zero, size: CGSize(width: cardWidth, height: cardHeight))
        self.cardTintOverlay.frame = CGRect(origin: .zero, size: CGSize(width: cardWidth, height: cardHeight))
        
        // Position card near source button
        let buttonFrame = sourceButton.convert(sourceButton.bounds, to: self)
        var cardX = buttonFrame.maxX - cardWidth
        if cardX < 20.0 { cardX = 20.0 }
        if cardX + cardWidth > self.bounds.width - 20.0 {
            cardX = self.bounds.width - cardWidth - 20.0
        }
        
        var cardY = buttonFrame.maxY + 8.0
        if cardY + cardHeight > self.bounds.height - 30.0 {
            cardY = max(50.0, buttonFrame.minY - cardHeight - 8.0)
        }
        
        self.cardView.frame = CGRect(x: cardX, y: cardY, width: cardWidth, height: cardHeight)
        
        // Layout top capsule buttons
        let capW = cardWidth - 24.0
        let halfW = floor((capW - 1.0) * 0.5)
        self.favoriteButton.frame = CGRect(x: 0, y: 0, width: halfW, height: 62.0)
        self.capsuleDivider.frame = CGRect(x: halfW, y: 10, width: 0.5, height: 42.0)
        self.shareButton.frame = CGRect(x: halfW + 0.5, y: 0, width: capW - halfW - 0.5, height: 62.0)
        
        // Presentation animation
        self.cardView.alpha = 0.0
        self.cardView.transform = CGAffineTransform(scaleX: 0.88, y: 0.88).concatenating(CGAffineTransform(translationX: (buttonFrame.midX - self.cardView.center.x) * 0.2, y: -16))
        
        UIView.animate(withDuration: 0.32, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0.6, options: [.allowUserInteraction], animations: {
            self.dimmingView.alpha = 1.0
            self.cardView.alpha = 1.0
            self.cardView.transform = .identity
        })
    }
    
    private func createRow(for item: SGDoxMusicMenuItem) -> UIView {
        let button = SGDoxMenuButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        let rowHeight: CGFloat = (item.subtitle != nil) ? 50.0 : 44.0
        button.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
        
        let tintColor: UIColor = item.isDestructive ? UIColor(red: 1.0, green: 0.28, blue: 0.38, alpha: 1.0) : .white
        
        let iconView = UIImageView()
        iconView.contentMode = .scaleAspectFit
        let iconConfig = UIImage.SymbolConfiguration(pointSize: 16.0, weight: .medium)
        iconView.image = UIImage(systemName: item.iconName, withConfiguration: iconConfig)
        iconView.tintColor = tintColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(iconView)
        
        let titleLabel = UILabel()
        titleLabel.text = item.title
        titleLabel.textColor = tintColor
        titleLabel.font = UIFont.systemFont(ofSize: 14.5, weight: .medium)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(titleLabel)
        
        if let sub = item.subtitle {
            let subLabel = UILabel()
            subLabel.text = sub
            subLabel.textColor = UIColor(white: 1.0, alpha: 0.50)
            subLabel.font = UIFont.systemFont(ofSize: 11.5, weight: .regular)
            subLabel.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(subLabel)
            
            NSLayoutConstraint.activate([
                iconView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 16),
                iconView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: 22),
                iconView.heightAnchor.constraint(equalToConstant: 22),
                
                titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 14),
                titleLabel.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -16),
                titleLabel.topAnchor.constraint(equalTo: button.topAnchor, constant: 7),
                
                subLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
                subLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
                subLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1)
            ])
        } else {
            NSLayoutConstraint.activate([
                iconView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 16),
                iconView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: 22),
                iconView.heightAnchor.constraint(equalToConstant: 22),
                
                titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 14),
                titleLabel.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -16),
                titleLabel.centerYAnchor.constraint(equalTo: button.centerYAnchor)
            ])
        }
        
        button.enablesHighlight = true
        button.onTap = { [weak self] in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            self?.dismissAnimated(completion: item.action)
        }
        
        return button
    }
    
    @objc private func backgroundTapped() {
        self.dismissAnimated(completion: nil)
    }
    
    public func dismissAnimated(completion: (() -> Void)?) {
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseIn], animations: {
            self.dimmingView.alpha = 0.0
            self.cardView.alpha = 0.0
            self.cardView.transform = CGAffineTransform(scaleX: 0.90, y: 0.90)
        }) { _ in
            self.removeFromSuperview()
            completion?()
        }
    }
}
