import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import ChatMessageDateAndStatusNode
import ChatMessageBubbleContentNode
import ChatMessageItemCommon
import ChatControllerInteraction
import SGSettingsUI
import SGSimpleSettings

public final class ChatMessageDoxMediaBubbleContentNode: ChatMessageBubbleContentNode {
    private let cardBackgroundNode: ASDisplayNode
    private let artworkContainerNode: ASDisplayNode
    private let artworkImageNode: ASImageNode
    private let artworkOverlayNode: ASImageNode
    private let badgeNode: TextNode
    private let titleNode: TextNode
    private let subtitleNode: TextNode
    private let playButtonNode: HighlightTrackingButtonNode
    private let playIconNode: ASImageNode
    private let dateAndStatusNode: ChatMessageDateAndStatusNode
    
    private var stateListenerToken: UUID?
    private var currentTrackId: String?
    private var currentSession: SGDoxListenTogetherSessionInfo?
    private var isMusic: Bool = true
    private var rawTag: String = ""
    
    required public init() {
        self.cardBackgroundNode = ASDisplayNode()
        self.cardBackgroundNode.clipsToBounds = true
        self.cardBackgroundNode.cornerRadius = 14.0
        
        self.artworkContainerNode = ASDisplayNode()
        self.artworkContainerNode.clipsToBounds = true
        self.artworkContainerNode.cornerRadius = 10.0
        
        self.artworkImageNode = ASImageNode()
        self.artworkImageNode.contentMode = .scaleAspectFill
        self.artworkImageNode.displaysAsynchronously = false
        
        self.artworkOverlayNode = ASImageNode()
        self.artworkOverlayNode.contentMode = .center
        self.artworkOverlayNode.displaysAsynchronously = false
        self.artworkOverlayNode.isHidden = true
        
        self.badgeNode = TextNode()
        self.badgeNode.isUserInteractionEnabled = false
        self.badgeNode.displaysAsynchronously = false
        
        self.titleNode = TextNode()
        self.titleNode.isUserInteractionEnabled = false
        self.titleNode.displaysAsynchronously = false
        
        self.subtitleNode = TextNode()
        self.subtitleNode.isUserInteractionEnabled = false
        self.subtitleNode.displaysAsynchronously = false
        
        self.playButtonNode = HighlightTrackingButtonNode()
        self.playButtonNode.clipsToBounds = true
        self.playButtonNode.cornerRadius = 19.0
        
        self.playIconNode = ASImageNode()
        self.playIconNode.contentMode = .center
        self.playIconNode.displaysAsynchronously = false
        self.playIconNode.isUserInteractionEnabled = false
        
        self.dateAndStatusNode = ChatMessageDateAndStatusNode()
        
        super.init()
        
        self.addSubnode(self.cardBackgroundNode)
        self.cardBackgroundNode.addSubnode(self.artworkContainerNode)
        self.artworkContainerNode.addSubnode(self.artworkImageNode)
        self.artworkContainerNode.addSubnode(self.artworkOverlayNode)
        self.cardBackgroundNode.addSubnode(self.badgeNode)
        self.cardBackgroundNode.addSubnode(self.titleNode)
        self.cardBackgroundNode.addSubnode(self.subtitleNode)
        self.cardBackgroundNode.addSubnode(self.playButtonNode)
        self.playButtonNode.addSubnode(self.playIconNode)
        self.addSubnode(self.dateAndStatusNode)
        
        self.playButtonNode.addTarget(self, action: #selector(self.playButtonPressed), forControlEvents: .touchUpInside)
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        if let token = self.stateListenerToken {
            SGDoxMusicManager.shared.removeStateListener(token)
            self.stateListenerToken = nil
        }
        NotificationCenter.default.removeObserver(self)
    }
    
    override public func didLoad() {
        super.didLoad()
        
        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(self.cardPressed))
        self.cardBackgroundNode.view.addGestureRecognizer(tapRecognizer)
        
        self.stateListenerToken = SGDoxMusicManager.shared.addStateListener { [weak self] in
            DispatchQueue.main.async {
                self?.updatePlaybackState(animated: true)
            }
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.sessionChangedNotification), name: NSNotification.Name("SGDoxListenTogetherSessionChanged"), object: nil)
    }
    
    @objc private func sessionChangedNotification() {
        DispatchQueue.main.async { [weak self] in
            self?.updatePlaybackState(animated: true)
        }
    }
    
    private func updatePlaybackState(animated: Bool) {
        guard self.isMusic, let trackId = self.currentTrackId else { return }
        let manager = SGDoxMusicManager.shared
        let isPlaying = (manager.currentTrack?.id == trackId) && manager.isPlaying
        
        let iconName = isPlaying ? "pause.fill" : "play.fill"
        let iconConfig = UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)
        let iconImage = UIImage(systemName: iconName, withConfiguration: iconConfig)?.withTintColor(.white, renderingMode: .alwaysOriginal)
        self.playIconNode.image = iconImage
        self.artworkOverlayNode.isHidden = !isPlaying
        
        if animated {
            UIView.animate(withDuration: 0.12, animations: {
                self.playButtonNode.view.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
            }) { _ in
                UIView.animate(withDuration: 0.12) {
                    self.playButtonNode.view.transform = .identity
                }
            }
        }
    }
    
    @objc private func playButtonPressed() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        guard let item = self.item else { return }
        
        if self.isMusic {
            let manager = SGDoxMusicManager.shared
            if let trackId = self.currentTrackId, manager.currentTrack?.id == trackId {
                manager.togglePlay()
                self.updatePlaybackState(animated: true)
            } else if let session = self.currentSession {
                let _ = SGDoxListenTogetherManager.shared.handleIncomingSync(text: self.rawTag, peerId: item.message.id.peerId, senderName: item.message.author?.debugDisplayTitle, forceJoin: true)
                self.updatePlaybackState(animated: true)
            }
        } else {
            self.cardPressed()
        }
    }
    
    @objc private func cardPressed() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        guard let item = self.item, !self.rawTag.isEmpty else { return }
        item.controllerInteraction.openUrl(ChatControllerInteraction.OpenUrl(url: self.rawTag, concealed: false, progress: nil, message: EngineMessage(item.message)))
    }
    
    override public func tapActionAtPoint(_ point: CGPoint, gesture: TapLongTapOrDoubleTapGesture, isEstimating: Bool) -> ChatMessageBubbleContentTapAction {
        let playButtonFrame = self.cardBackgroundNode.frame.origin.x + self.playButtonNode.frame.minX
        let buttonRect = CGRect(origin: CGPoint(x: playButtonFrame - 6.0, y: self.cardBackgroundNode.frame.origin.y + self.playButtonNode.frame.minY - 6.0), size: CGSize(width: self.playButtonNode.frame.width + 12.0, height: self.playButtonNode.frame.height + 12.0))
        
        if buttonRect.contains(point) {
            return ChatMessageBubbleContentTapAction(content: .custom({ [weak self] in
                self?.playButtonPressed()
            }))
        }
        if self.cardBackgroundNode.frame.contains(point) {
            return ChatMessageBubbleContentTapAction(content: .custom({ [weak self] in
                self?.cardPressed()
            }))
        }
        return ChatMessageBubbleContentTapAction(content: .none)
    }
    
    override public func asyncLayoutContent() -> (_ item: ChatMessageBubbleContentItem, _ layoutConstants: ChatMessageItemLayoutConstants, _ preparePosition: ChatMessageBubblePreparePosition, _ messageSelection: Bool?, _ constrainedSize: CGSize, _ avatarInset: CGFloat) -> (ChatMessageBubbleContentProperties, CGSize?, CGFloat, (CGSize, ChatMessageBubbleContentPosition) -> (CGFloat, (CGFloat) -> (CGSize, (ListViewItemUpdateAnimation, Bool, ListViewItemApply?) -> Void))) {
        let makeBadgeLayout = TextNode.asyncLayout(self.badgeNode)
        let makeTitleLayout = TextNode.asyncLayout(self.titleNode)
        let makeSubtitleLayout = TextNode.asyncLayout(self.subtitleNode)
        let statusLayout = self.dateAndStatusNode.asyncLayout()
        
        return { item, layoutConstants, _, _, constrainedSize, _ in
            let contentProperties = ChatMessageBubbleContentProperties(
                hidesSimpleAuthorHeader: false,
                headerSpacing: 0.0,
                hidesBackground: .never,
                forceFullCorners: false,
                forceAlignment: .none
            )
            
            return (contentProperties, nil, CGFloat.greatestFiniteMagnitude, { constrainedSize, position in
                let incoming = item.message.effectivelyIncoming(item.context.account.peerId)
                let messageTheme = incoming ? item.presentationData.theme.theme.chat.message.incoming : item.presentationData.theme.theme.chat.message.outgoing
                
                let text = item.message.text
                let isMusicTag = text.contains("doxlisten:")
                let isWallpaperTag = text.contains("doxwall:")
                
                var badgeText = "🎧 СОВМЕСТНЫЙ ЭФИР"
                var titleText = "Музыкальный трек"
                var subtitleText = "DoxMusic • Нажмите для синхронизации"
                var parsedTrackId: String?
                var parsedArtworkUrl: String?
                var parsedSession: SGDoxListenTogetherSessionInfo?
                var resolvedTag = ""
                
                if isMusicTag {
                    let peerId = item.message.id.peerId
                    let senderName = item.message.author?.debugDisplayTitle
                    if let session = SGDoxListenTogetherManager.shared.parseSyncTag(text: text, peerId: peerId, senderName: senderName) {
                        parsedSession = session
                        parsedTrackId = session.trackId
                        parsedArtworkUrl = session.artworkUrl
                        titleText = session.title
                        subtitleText = session.artist.isEmpty ? "DoxMusic" : session.artist
                    }
                    if let range = text.range(of: "#doxlisten:") ?? text.range(of: "doxlisten:") {
                        let remainder = String(text[range.lowerBound...])
                        resolvedTag = remainder.components(separatedBy: "\n").first ?? text
                    }
                    badgeText = "🎧 СОВМЕСТНЫЙ ЭФИР"
                } else if isWallpaperTag {
                    if let wp = SGDoxAnimatedWallpaperManager.shared.parseSyncTag(from: text) {
                        titleText = "Живые видео-обои"
                        subtitleText = "Качество: \(wp.quality) • Нажмите для установки"
                    } else {
                        titleText = "Живые обои"
                        subtitleText = "Нажмите для установки"
                    }
                    if let range = text.range(of: "#doxwall:") ?? text.range(of: "doxwall:") {
                        let remainder = String(text[range.lowerBound...])
                        resolvedTag = remainder.components(separatedBy: "\n").first ?? text
                    }
                    badgeText = "🎬 ЖИВЫЕ ОБОИ"
                }
                
                let badgeFont = Font.bold(10.5)
                let titleFont = Font.semibold(14.5)
                let subtitleFont = Font.regular(12.5)
                
                let maxCardWidth = min(constrainedSize.width - layoutConstants.text.bubbleInsets.left - layoutConstants.text.bubbleInsets.right, 274.0)
                let textWidth = max(0.0, maxCardWidth - 78.0 - 52.0)
                
                let (badgeLayout, badgeApply) = makeBadgeLayout(TextNodeLayoutArguments(
                    attributedString: NSAttributedString(string: badgeText, font: badgeFont, textColor: messageTheme.accentTextColor),
                    backgroundColor: nil,
                    maximumNumberOfLines: 1,
                    truncationType: .end,
                    constrainedSize: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                    alignment: .natural,
                    cutout: nil,
                    insets: UIEdgeInsets()
                ))
                
                let (titleLayout, titleApply) = makeTitleLayout(TextNodeLayoutArguments(
                    attributedString: NSAttributedString(string: titleText, font: titleFont, textColor: messageTheme.primaryTextColor),
                    backgroundColor: nil,
                    maximumNumberOfLines: 1,
                    truncationType: .end,
                    constrainedSize: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                    alignment: .natural,
                    cutout: nil,
                    insets: UIEdgeInsets()
                ))
                
                let (subtitleLayout, subtitleApply) = makeSubtitleLayout(TextNodeLayoutArguments(
                    attributedString: NSAttributedString(string: subtitleText, font: subtitleFont, textColor: messageTheme.secondaryTextColor),
                    backgroundColor: nil,
                    maximumNumberOfLines: 1,
                    truncationType: .end,
                    constrainedSize: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                    alignment: .natural,
                    cutout: nil,
                    insets: UIEdgeInsets()
                ))
                
                let statusType: ChatMessageDateAndStatusType?
                switch position {
                case .linear(_, .None), .linear(_, .Neighbour(true, _, _)):
                    if incoming {
                        statusType = .BubbleIncoming
                    } else {
                        if item.message.flags.contains(.Failed) {
                            statusType = .BubbleOutgoing(.Failed)
                        } else if (item.message.flags.isSending && !item.message.isSentOrAcknowledged) || item.attributes.updatingMedia != nil {
                            statusType = .BubbleOutgoing(.Sending)
                        } else {
                            statusType = .BubbleOutgoing(.Sent(read: item.read))
                        }
                    }
                default:
                    statusType = nil
                }
                
                var statusSuggestedWidthAndContinue: (CGFloat, (CGFloat) -> (CGSize, (ListViewItemUpdateAnimation) -> Void))?
                if let statusType = statusType {
                    let dateText = stringForMessageTimestampStatus(context: item.context, message: EngineMessage(item.message), dateTimeFormat: item.presentationData.dateTimeFormat, nameDisplayOrder: item.presentationData.nameDisplayOrder, strings: item.presentationData.strings, associatedData: item.associatedData)
                    
                    statusSuggestedWidthAndContinue = statusLayout(ChatMessageDateAndStatusNode.Arguments(
                        context: item.context,
                        presentationData: item.presentationData,
                        edited: false,
                        impressionCount: nil,
                        dateText: dateText,
                        type: statusType,
                        layoutInput: .trailingContent(contentWidth: 1000.0, reactionSettings: nil),
                        constrainedSize: CGSize(width: constrainedSize.width, height: .greatestFiniteMagnitude),
                        availableReactions: item.associatedData.availableReactions,
                        savedMessageTags: item.associatedData.savedMessageTags,
                        reactions: [],
                        reactionPeers: [],
                        displayAllReactionPeers: false,
                        areReactionsTags: false,
                        areStarReactionsEnabled: false,
                        messageEffect: nil,
                        replyCount: 0,
                        starsCount: nil,
                        isPinned: false,
                        hasAutoremove: false,
                        canViewReactionList: false,
                        animationCache: item.controllerInteraction.presentationContext.animationCache,
                        animationRenderer: item.controllerInteraction.presentationContext.animationRenderer
                    ))
                }
                
                let cardHeight: CGFloat = 78.0
                let statusSizeAndApply = statusSuggestedWidthAndContinue?.1(maxCardWidth)
                let statusHeight: CGFloat = statusSizeAndApply?.0.height ?? 16.0
                let totalHeight = cardHeight + statusHeight + 4.0
                
                return (maxCardWidth, { boundingWidth in
                    let layoutSize = CGSize(width: boundingWidth, height: totalHeight)
                    
                    return (layoutSize, { [weak self] animation, _, _ in
                        guard let strongSelf = self else { return }
                        strongSelf.item = item
                        strongSelf.currentTrackId = parsedTrackId
                        strongSelf.currentSession = parsedSession
                        strongSelf.isMusic = isMusicTag
                        strongSelf.rawTag = resolvedTag
                        
                        let cardRect = CGRect(x: 4.0, y: 4.0, width: boundingWidth - 8.0, height: cardHeight)
                        strongSelf.cardBackgroundNode.frame = cardRect
                        strongSelf.cardBackgroundNode.backgroundColor = messageTheme.secondaryTextColor.withAlphaComponent(0.08)
                        strongSelf.cardBackgroundNode.layer.borderWidth = 0.5
                        strongSelf.cardBackgroundNode.layer.borderColor = messageTheme.primaryTextColor.withAlphaComponent(0.12).cgColor
                        
                        // Artwork container
                        let artSide: CGFloat = 62.0
                        let artFrame = CGRect(x: 8.0, y: 8.0, width: artSide, height: artSide)
                        strongSelf.artworkContainerNode.frame = artFrame
                        strongSelf.artworkImageNode.frame = strongSelf.artworkContainerNode.bounds
                        strongSelf.artworkOverlayNode.frame = strongSelf.artworkContainerNode.bounds
                        strongSelf.artworkOverlayNode.backgroundColor = UIColor(white: 0.0, alpha: 0.45)
                        
                        let waveCfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
                        strongSelf.artworkOverlayNode.image = UIImage(systemName: "waveform", withConfiguration: waveCfg)?.withTintColor(.white, renderingMode: .alwaysOriginal)
                        
                        // Artwork content
                        if isMusicTag {
                            strongSelf.artworkImageNode.image = SGDoxImageLoader.shared.placeholderArtwork()
                            if let artUrl = parsedArtworkUrl, !artUrl.isEmpty {
                                SGDoxImageLoader.shared.loadImage(urlString: artUrl) { [weak strongSelf] img in
                                    if let img = img {
                                        strongSelf?.artworkImageNode.image = img
                                    }
                                }
                            } else {
                                let dummy = SGDoxMusicTrack(id: parsedTrackId ?? "sync", title: titleText, artist: subtitleText, duration: 0, service: .appleMusic, artworkUrl: "", previewUrl: nil)
                                SGDoxImageLoader.shared.loadArtwork(for: dummy, targetSize: CGSize(width: 120, height: 120)) { [weak strongSelf] img in
                                    if let img = img {
                                        strongSelf?.artworkImageNode.image = img
                                    }
                                }
                            }
                        } else {
                            let wpConfig = UIImage.SymbolConfiguration(pointSize: 26, weight: .medium)
                            strongSelf.artworkImageNode.image = UIImage(systemName: "sparkles.tv.fill", withConfiguration: wpConfig)?.withTintColor(messageTheme.accentTextColor, renderingMode: .alwaysOriginal)
                            strongSelf.artworkImageNode.backgroundColor = messageTheme.accentTextColor.withAlphaComponent(0.14)
                        }
                        
                        // Text nodes
                        let _ = badgeApply()
                        let _ = titleApply()
                        let _ = subtitleApply()
                        
                        strongSelf.badgeNode.frame = CGRect(x: 78.0, y: 10.0, width: textWidth, height: badgeLayout.size.height)
                        strongSelf.titleNode.frame = CGRect(x: 78.0, y: 26.0, width: textWidth, height: titleLayout.size.height)
                        strongSelf.subtitleNode.frame = CGRect(x: 78.0, y: 46.0, width: textWidth, height: subtitleLayout.size.height)
                        
                        // Button
                        let btnSide: CGFloat = 38.0
                        let btnX = cardRect.width - btnSide - 10.0
                        let btnY = floor((cardHeight - btnSide) * 0.5)
                        strongSelf.playButtonNode.frame = CGRect(x: btnX, y: btnY, width: btnSide, height: btnSide)
                        strongSelf.playButtonNode.backgroundColor = messageTheme.accentTextColor
                        strongSelf.playIconNode.frame = strongSelf.playButtonNode.bounds
                        
                        if isMusicTag {
                            strongSelf.updatePlaybackState(animated: false)
                        } else {
                            let actConfig = UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)
                            strongSelf.playIconNode.image = UIImage(systemName: "arrow.down.circle.fill", withConfiguration: actConfig)?.withTintColor(.white, renderingMode: .alwaysOriginal)
                            strongSelf.artworkOverlayNode.isHidden = true
                        }
                        
                        // Status & Date Node
                        if let statusSizeAndApply = statusSizeAndApply {
                            let statusOrigin = CGPoint(
                                x: boundingWidth - layoutConstants.text.bubbleInsets.right - statusSizeAndApply.0.width,
                                y: totalHeight - statusHeight - 2.0
                            )
                            strongSelf.dateAndStatusNode.frame = CGRect(origin: statusOrigin, size: statusSizeAndApply.0)
                            statusSizeAndApply.1(animation)
                        }
                    })
                })
            })
        }
    }
}
