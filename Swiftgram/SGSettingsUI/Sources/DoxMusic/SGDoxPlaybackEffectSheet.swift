import Foundation
import UIKit
import Display

private final class SGDoxEffectRowButton: UIButton {
    var onTap: (() -> Void)?
    var isCurrentSelected: Bool = false
    var selectedBgColor: UIColor = .clear
    
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
        self.transform = .identity
        self.backgroundColor = self.isCurrentSelected ? self.selectedBgColor : .clear
        self.onTap?()
    }
    
    @objc private func touchDown() {
        UIView.animate(withDuration: 0.10) {
            self.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
            self.backgroundColor = self.isCurrentSelected ? self.selectedBgColor : UIColor(white: 1.0, alpha: 0.08)
        }
    }
    
    @objc private func touchUp() {
        UIView.animate(withDuration: 0.20, delay: 0, usingSpringWithDamping: 0.60, initialSpringVelocity: 0.6, options: [.allowUserInteraction], animations: {
            self.transform = .identity
            self.backgroundColor = self.isCurrentSelected ? self.selectedBgColor : .clear
        })
    }
}

public final class SGDoxPlaybackEffectSheet: UIView, UIGestureRecognizerDelegate {
    private let dimmingView = UIView()
    private let cardShadowContainer = UIView()
    private let cardContainer = UIView()
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialDark))
    private let cardTintOverlay = UIView()
    private let sheenGradient = CAGradientLayer()
    
    private let headerView = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let closeButton = UIButton(type: .custom)
    
    private let contentStack = UIStackView()
    private var isDismissing = false
    private var panGesture: UIPanGestureRecognizer?
    private var onSelected: (() -> Void)?
    
    public static func show(in parentView: UIView, onSelected: (() -> Void)? = nil) {
        let sheet = SGDoxPlaybackEffectSheet(frame: parentView.bounds)
        sheet.onSelected = onSelected
        parentView.addSubview(sheet)
        sheet.presentAnimated()
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        self.dimmingView.frame = frame
        self.dimmingView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.dimmingView.backgroundColor = UIColor(white: 0.0, alpha: 0.45)
        self.dimmingView.alpha = 0.0
        self.dimmingView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.backgroundTapped)))
        self.addSubview(self.dimmingView)
        
        self.cardShadowContainer.backgroundColor = .clear
        self.cardShadowContainer.layer.shadowColor = UIColor.black.cgColor
        self.cardShadowContainer.layer.shadowOpacity = 0.50
        self.cardShadowContainer.layer.shadowRadius = 32.0
        self.cardShadowContainer.layer.shadowOffset = CGSize(width: 0, height: 16)
        self.addSubview(self.cardShadowContainer)
        
        self.cardContainer.backgroundColor = .clear
        self.cardContainer.layer.cornerRadius = 26.0
        self.cardContainer.layer.cornerCurve = .continuous
        self.cardContainer.layer.borderWidth = 0.5
        self.cardContainer.layer.borderColor = UIColor(white: 1.0, alpha: 0.25).cgColor
        self.cardContainer.clipsToBounds = true
        self.cardShadowContainer.addSubview(self.cardContainer)
        
        self.blurView.clipsToBounds = true
        self.cardContainer.addSubview(self.blurView)
        
        self.cardTintOverlay.backgroundColor = UIColor(red: 0.08, green: 0.10, blue: 0.16, alpha: 0.35)
        self.cardContainer.addSubview(self.cardTintOverlay)
        
        self.sheenGradient.colors = [
            UIColor(white: 1.0, alpha: 0.25).cgColor,
            UIColor(white: 1.0, alpha: 0.03).cgColor,
            UIColor.clear.cgColor
        ]
        self.sheenGradient.locations = [0.0, 0.30, 1.0]
        self.sheenGradient.startPoint = CGPoint(x: 0.5, y: 0.0)
        self.sheenGradient.endPoint = CGPoint(x: 0.5, y: 1.0)
        self.cardContainer.layer.addSublayer(self.sheenGradient)
        
        // Header
        self.cardContainer.addSubview(self.headerView)
        
        self.titleLabel.text = "Скорость и эффекты"
        self.titleLabel.font = UIFont.systemFont(ofSize: 18.0, weight: .bold)
        self.titleLabel.textColor = .white
        self.headerView.addSubview(self.titleLabel)
        
        self.subtitleLabel.text = "Slowed + Reverb, Nightcore и темп"
        self.subtitleLabel.font = UIFont.systemFont(ofSize: 12.5, weight: .regular)
        self.subtitleLabel.textColor = UIColor(white: 1.0, alpha: 0.60)
        self.headerView.addSubview(self.subtitleLabel)
        
        let xConfig = UIImage.SymbolConfiguration(pointSize: 11.5, weight: .bold)
        self.closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: xConfig), for: .normal)
        self.closeButton.tintColor = UIColor(white: 1.0, alpha: 0.85)
        self.closeButton.backgroundColor = UIColor(white: 1.0, alpha: 0.12)
        self.closeButton.layer.cornerRadius = 14.0
        self.closeButton.layer.borderWidth = 0.5
        self.closeButton.layer.borderColor = UIColor(white: 1.0, alpha: 0.20).cgColor
        self.closeButton.clipsToBounds = true
        self.closeButton.addTarget(self, action: #selector(self.backgroundTapped), for: .touchUpInside)
        self.headerView.addSubview(self.closeButton)
        
        // Content Stack
        self.contentStack.axis = .vertical
        self.contentStack.spacing = 2.0
        self.contentStack.alignment = .fill
        self.contentStack.distribution = .fill
        self.cardContainer.addSubview(self.contentStack)
        
        self.populateEffectRows()
        
        let pan = UIPanGestureRecognizer(target: self, action: #selector(self.handlePan(_:)))
        pan.delegate = self
        self.cardShadowContainer.addGestureRecognizer(pan)
        self.panGesture = pan
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func populateEffectRows() {
        let currentEffect = SGDoxMusicManager.shared.playbackEffect
        
        for effect in SGDoxPlaybackEffect.allCases {
            let row = self.createEffectRow(effect: effect, isSelected: effect == currentEffect)
            self.contentStack.addArrangedSubview(row)
        }
    }
    
    private func createEffectRow(effect: SGDoxPlaybackEffect, isSelected: Bool) -> UIView {
        let button = SGDoxEffectRowButton(frame: .zero)
        button.isCurrentSelected = isSelected
        button.selectedBgColor = effect.badgeBackgroundColor
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 54.0).isActive = true
        button.layer.cornerRadius = 14.0
        button.layer.cornerCurve = .continuous
        button.clipsToBounds = true
        
        if isSelected {
            button.backgroundColor = effect.badgeBackgroundColor
            button.layer.borderWidth = 0.5
            button.layer.borderColor = effect.badgeColor.withAlphaComponent(0.40).cgColor
        } else {
            button.backgroundColor = .clear
        }
        
        let iconBadge = UIView()
        iconBadge.backgroundColor = isSelected ? effect.badgeColor.withAlphaComponent(0.25) : UIColor(white: 1.0, alpha: 0.10)
        iconBadge.layer.cornerRadius = 15.0
        iconBadge.layer.cornerCurve = .continuous
        iconBadge.clipsToBounds = true
        iconBadge.translatesAutoresizingMaskIntoConstraints = false
        iconBadge.isUserInteractionEnabled = false
        button.addSubview(iconBadge)
        
        let iconView = UIImageView()
        iconView.contentMode = .scaleAspectFit
        let iconCfg = UIImage.SymbolConfiguration(pointSize: 14.5, weight: .semibold)
        iconView.image = UIImage(systemName: effect.icon, withConfiguration: iconCfg)
        iconView.tintColor = isSelected ? effect.badgeColor : .white
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconBadge.addSubview(iconView)
        
        let titleLabel = UILabel()
        titleLabel.text = effect.title
        titleLabel.textColor = isSelected ? effect.badgeColor : .white
        titleLabel.font = UIFont.systemFont(ofSize: 15.0, weight: isSelected ? .bold : .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(titleLabel)
        
        let subLabel = UILabel()
        subLabel.text = effect.subtitle
        subLabel.textColor = isSelected ? effect.badgeColor.withAlphaComponent(0.80) : UIColor(white: 1.0, alpha: 0.50)
        subLabel.font = UIFont.systemFont(ofSize: 12.0, weight: .regular)
        subLabel.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(subLabel)
        
        let checkmarkView = UIImageView()
        checkmarkView.contentMode = .scaleAspectFit
        let checkCfg = UIImage.SymbolConfiguration(pointSize: 17.0, weight: .bold)
        checkmarkView.image = UIImage(systemName: "checkmark.circle.fill", withConfiguration: checkCfg)
        checkmarkView.tintColor = effect.badgeColor
        checkmarkView.isHidden = !isSelected
        checkmarkView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(checkmarkView)
        
        NSLayoutConstraint.activate([
            iconBadge.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 12),
            iconBadge.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            iconBadge.widthAnchor.constraint(equalToConstant: 30),
            iconBadge.heightAnchor.constraint(equalToConstant: 30),
            
            iconView.centerXAnchor.constraint(equalTo: iconBadge.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBadge.centerYAnchor),
            
            titleLabel.leadingAnchor.constraint(equalTo: iconBadge.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: checkmarkView.leadingAnchor, constant: -8),
            titleLabel.topAnchor.constraint(equalTo: button.topAnchor, constant: 8),
            
            subLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            
            checkmarkView.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -14),
            checkmarkView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            checkmarkView.widthAnchor.constraint(equalToConstant: 22),
            checkmarkView.heightAnchor.constraint(equalToConstant: 22)
        ])
        
        button.onTap = { [weak self] in
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            SGDoxMusicManager.shared.playbackEffect = effect
            self?.onSelected?()
            self?.dismissAnimated()
        }
        
        return button
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        self.dimmingView.frame = self.bounds
        
        let cardW = min(self.bounds.width - 32.0, 360.0)
        let headerH: CGFloat = 52.0
        let rowsCount = CGFloat(SGDoxPlaybackEffect.allCases.count)
        let stackH = rowsCount * 56.0
        let bottomPad: CGFloat = 16.0
        let cardH = headerH + stackH + bottomPad
        
        let cardX = (self.bounds.width - cardW) * 0.5
        let cardY = max(40.0, (self.bounds.height - cardH) * 0.5)
        
        self.cardShadowContainer.frame = CGRect(x: cardX, y: cardY, width: cardW, height: cardH)
        self.cardContainer.frame = self.cardShadowContainer.bounds
        self.blurView.frame = self.cardContainer.bounds
        self.cardTintOverlay.frame = self.cardContainer.bounds
        self.sheenGradient.frame = CGRect(x: 0, y: 0, width: cardW, height: 110.0)
        
        self.headerView.frame = CGRect(x: 16.0, y: 14.0, width: cardW - 32.0, height: headerH)
        self.closeButton.frame = CGRect(x: self.headerView.bounds.width - 28.0, y: 0, width: 28.0, height: 28.0)
        self.titleLabel.frame = CGRect(x: 0, y: 0, width: self.headerView.bounds.width - 36.0, height: 22.0)
        self.subtitleLabel.frame = CGRect(x: 0, y: 24.0, width: self.headerView.bounds.width - 36.0, height: 16.0)
        
        self.contentStack.frame = CGRect(x: 10.0, y: headerH + 16.0, width: cardW - 20.0, height: stackH)
    }
    
    public func presentAnimated() {
        self.layoutIfNeeded()
        self.cardShadowContainer.transform = CGAffineTransform(scaleX: 0.88, y: 0.88).concatenating(CGAffineTransform(translationX: 0, y: 24))
        self.cardShadowContainer.alpha = 0.0
        
        UIView.animate(withDuration: 0.32, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0.6, options: [.allowUserInteraction], animations: {
            self.dimmingView.alpha = 1.0
            self.cardShadowContainer.alpha = 1.0
            self.cardShadowContainer.transform = .identity
        })
    }
    
    @objc private func backgroundTapped() {
        self.dismissAnimated()
    }
    
    public func dismissAnimated(completion: (() -> Void)? = nil) {
        guard !self.isDismissing else { return }
        self.isDismissing = true
        
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseIn], animations: {
            self.dimmingView.alpha = 0.0
            self.cardShadowContainer.alpha = 0.0
            self.cardShadowContainer.transform = CGAffineTransform(scaleX: 0.90, y: 0.90)
        }) { _ in
            self.removeFromSuperview()
            completion?()
        }
    }
    
    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: self)
        let velocity = recognizer.velocity(in: self)
        
        switch recognizer.state {
        case .changed:
            if translation.y > 0 {
                self.cardShadowContainer.transform = CGAffineTransform(translationX: 0, y: translation.y)
                let progress = min(1.0, translation.y / 200.0)
                self.dimmingView.alpha = 1.0 - (progress * 0.6)
            }
        case .ended, .cancelled:
            if translation.y > 80.0 || velocity.y > 500.0 {
                self.dismissAnimated()
            } else {
                UIView.animate(withDuration: 0.28, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0.5, options: [.curveEaseOut], animations: {
                    self.cardShadowContainer.transform = .identity
                    self.dimmingView.alpha = 1.0
                })
            }
        default:
            break
        }
    }
}
