import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import Postbox
import TelegramPresentationData
import ChatMessageBubbleContentNode
import ChatMessageItemCommon
import SGSimpleSettings

public final class ChatMessageHiddenAdBubbleContentNode: ChatMessageBubbleContentNode {
    private let backgroundNode: NavigationBackgroundNode
    private let labelNode: TextNode
    private let buttonView: HighlightTrackingButton
    
    required public init() {
        self.backgroundNode = NavigationBackgroundNode(color: .clear)
        self.labelNode = TextNode()
        self.labelNode.isUserInteractionEnabled = false
        self.buttonView = HighlightTrackingButton()
        
        super.init()
        
        self.addSubnode(self.backgroundNode)
        self.addSubnode(self.labelNode)
        
        self.view.addSubview(self.buttonView)
        self.buttonView.addTarget(self, action: #selector(self.revealPressed), for: .touchUpInside)
        self.buttonView.highligthedChanged = { [weak self] highlighted in
            guard let strongSelf = self else { return }
            if highlighted {
                strongSelf.backgroundNode.layer.animateAlpha(from: 1.0, to: 0.65, duration: 0.1, removeOnCompletion: false)
                strongSelf.labelNode.layer.animateAlpha(from: 1.0, to: 0.65, duration: 0.1, removeOnCompletion: false)
            } else {
                strongSelf.backgroundNode.layer.animateAlpha(from: 0.65, to: 1.0, duration: 0.2, removeOnCompletion: false)
                strongSelf.labelNode.layer.animateAlpha(from: 0.65, to: 1.0, duration: 0.2, removeOnCompletion: false)
            }
        }
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func revealPressed() {
        guard let item = self.item else {
            return
        }
        SGAdFilterState.shared.reveal(item.message.id)
        if case let .group(messages) = item.content {
            for message in messages {
                SGAdFilterState.shared.reveal(message.0.id)
            }
        }
        let _ = item.controllerInteraction.requestMessageUpdate(item.message.id, false, nil)
    }
    
    override public func asyncLayoutContent() -> (_ item: ChatMessageBubbleContentItem, _ layoutConstants: ChatMessageItemLayoutConstants, _ preparePosition: ChatMessageBubblePreparePosition, _ messageSelection: Bool?, _ constrainedSize: CGSize, _ avatarInset: CGFloat) -> (ChatMessageBubbleContentProperties, CGSize?, CGFloat, (CGSize, ChatMessageBubbleContentPosition) -> (CGFloat, (CGFloat) -> (CGSize, (ListViewItemUpdateAnimation, Bool, ListViewItemApply?) -> Void))) {
        let labelLayout = TextNode.asyncLayout(self.labelNode)
        
        return { item, layoutConstants, _, _, constrainedSize, _ in
            let contentProperties = ChatMessageBubbleContentProperties(
                hidesSimpleAuthorHeader: true,
                headerSpacing: 0.0,
                hidesBackground: .always,
                forceFullCorners: false,
                forceAlignment: .center
            )
            
            return (contentProperties, nil, CGFloat.greatestFiniteMagnitude, { constrainedSize, position in
                let presentationData = item.presentationData
                let isRu = presentationData.strings.baseLanguageCode.lowercased().hasPrefix("ru")
                    || presentationData.strings.baseLanguageCode.lowercased().hasPrefix("uk")
                    || presentationData.strings.baseLanguageCode.lowercased().hasPrefix("be")
                
                let labelText = isRu ? "Скрыто одно рекламное сообщение" : "One ad message hidden"
                let showText = isRu ? "Показать" : "Show"
                
                let titleFont = Font.medium(min(18.0, floor(presentationData.fontSize.baseDisplaySize * 13.0 / 17.0)))
                let boldFont = Font.semibold(min(18.0, floor(presentationData.fontSize.baseDisplaySize * 13.0 / 17.0)))
                let textColor = bubbleVariableColor(variableColor: presentationData.theme.theme.chat.serviceMessage.dateTextColor, wallpaper: presentationData.theme.wallpaper)
                
                let attributedString = NSMutableAttributedString()
                attributedString.append(NSAttributedString(string: labelText, font: titleFont, textColor: textColor))
                attributedString.append(NSAttributedString(string: "  •  ", font: titleFont, textColor: textColor.withAlphaComponent(0.6)))
                attributedString.append(NSAttributedString(string: showText, font: boldFont, textColor: textColor))
                
                let horizontalPadding: CGFloat = 14.0
                let verticalPadding: CGFloat = 5.0
                let maxTextWidth = max(0.0, constrainedSize.width - horizontalPadding * 2.0)
                
                let (textSize, textApply) = labelLayout(TextNodeLayoutArguments(
                    attributedString: attributedString,
                    backgroundColor: nil,
                    maximumNumberOfLines: 1,
                    truncationType: .end,
                    constrainedSize: CGSize(width: maxTextWidth, height: CGFloat.greatestFiniteMagnitude),
                    alignment: .center,
                    cutout: nil,
                    insets: UIEdgeInsets()
                ))
                
                let pillHeight: CGFloat = max(28.0, textSize.size.height + verticalPadding * 2.0)
                let pillWidth: CGFloat = min(constrainedSize.width, textSize.size.width + horizontalPadding * 2.0)
                let boundingHeight: CGFloat = pillHeight + 8.0
                
                return (pillWidth, { boundingWidth in
                    let boundingSize = CGSize(width: boundingWidth, height: boundingHeight)
                    
                    return (boundingSize, { [weak self] animation, _, _ in
                        guard let strongSelf = self else { return }
                        strongSelf.item = item
                        
                        let _ = textApply()
                        
                        let pillOriginX = floor((boundingWidth - pillWidth) / 2.0)
                        let pillOriginY: CGFloat = 4.0
                        let pillFrame = CGRect(x: pillOriginX, y: pillOriginY, width: pillWidth, height: pillHeight)
                        
                        let fullTranslucency = true
                        strongSelf.backgroundNode.updateColor(
                            color: selectDateFillStaticColor(theme: presentationData.theme.theme, wallpaper: presentationData.theme.wallpaper),
                            enableBlur: fullTranslucency && dateFillNeedsBlur(theme: presentationData.theme.theme, wallpaper: presentationData.theme.wallpaper),
                            transition: .immediate
                        )
                        strongSelf.backgroundNode.frame = pillFrame
                        strongSelf.backgroundNode.update(size: pillFrame.size, cornerRadius: pillHeight / 2.0, transition: .immediate)
                        
                        let labelFrame = CGRect(
                            x: pillFrame.minX + floor((pillWidth - textSize.size.width) / 2.0),
                            y: pillFrame.minY + floor((pillHeight - textSize.size.height) / 2.0),
                            width: textSize.size.width,
                            height: textSize.size.height
                        )
                        strongSelf.labelNode.frame = labelFrame
                        strongSelf.buttonView.frame = pillFrame
                    })
                })
            })
        }
    }
    
    override public func tapActionAtPoint(_ point: CGPoint, gesture: TapLongTapOrDoubleTapGesture, isEstimating: Bool) -> ChatMessageBubbleContentTapAction {
        if self.bounds.contains(point) {
            return ChatMessageBubbleContentTapAction(content: .custom({ [weak self] in
                self?.revealPressed()
            }))
        }
        return ChatMessageBubbleContentTapAction(content: .none)
    }
    
    override public func animateInsertion(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.25)
    }
    
    override public func animateAdded(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.25)
    }
    
    override public func animateRemoved(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.25, removeOnCompletion: false)
    }
}
