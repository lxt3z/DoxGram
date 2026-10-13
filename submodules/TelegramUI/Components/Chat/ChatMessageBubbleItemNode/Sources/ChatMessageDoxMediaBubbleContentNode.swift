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
import SGSimpleSettings

public final class ChatMessageDoxMediaBubbleContentNode: ChatMessageBubbleContentNode {
    private static var artworkCache: [String: UIImage] = [:]
    
    private let cardBackgroundNode: ASDisplayNode
    private let headerNode: TextNode
    private let moreDotsNode: TextNode
    private let artworkContainerNode: ASDisplayNode
    private let artworkImageNode: ASImageNode
    private let artworkOverlayNode: ASImageNode
    private let titleNode: TextNode
    private let subtitleNode: TextNode
    private let playButtonNode: HighlightTrackingButtonNode
    private let playIconNode: ASImageNode
    private let playLabelNode: TextNode
    private let dateAndStatusNode: ChatMessageDateAndStatusNode
    
    private var currentTrackId: String?
    private var isMusic: Bool = true
    private var rawTag: String = ""
    private var currentTitle: String = ""
    private var currentArtist: String = ""
    
    required public init() {
        self.cardBackgroundNode = ASDisplayNode()
        self.cardBackgroundNode.clipsToBounds = true
        self.cardBackgroundNode.cornerRadius = 16.0
        
        self.headerNode = TextNode()
        self.headerNode.isUserInteractionEnabled = false
        self.headerNode.displaysAsynchronously = false
        
        self.moreDotsNode = TextNode()
        self.moreDotsNode.isUserInteractionEnabled = false
        self.moreDotsNode.displaysAsynchronously = false
        
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
        self.artworkOverlayNode.backgroundColor = UIColor(white: 0.0, alpha: 0.42)
        
        self.titleNode = TextNode()
        self.titleNode.isUserInteractionEnabled = false
        self.titleNode.displaysAsynchronously = false
        
        self.subtitleNode = TextNode()
        self.subtitleNode.isUserInteractionEnabled = false
        self.subtitleNode.displaysAsynchronously = false
        
        self.playButtonNode = HighlightTrackingButtonNode()
        self.playButtonNode.clipsToBounds = true
        self.playButtonNode.cornerRadius = 14.0
        
        self.playIconNode = ASImageNode()
        self.playIconNode.contentMode = .center
        self.playIconNode.displaysAsynchronously = false
        self.playIconNode.isUserInteractionEnabled = false
        
        self.playLabelNode = TextNode()
        self.playLabelNode.isUserInteractionEnabled = false
        self.playLabelNode.displaysAsynchronously = false
        
        self.dateAndStatusNode = ChatMessageDateAndStatusNode()
        
        super.init()
        
        self.addSubnode(self.cardBackgroundNode)
        self.cardBackgroundNode.addSubnode(self.headerNode)
        self.cardBackgroundNode.addSubnode(self.moreDotsNode)
        self.cardBackgroundNode.addSubnode(self.artworkContainerNode)
        self.artworkContainerNode.addSubnode(self.artworkImageNode)
        self.artworkContainerNode.addSubnode(self.artworkOverlayNode)
        self.cardBackgroundNode.addSubnode(self.titleNode)
        self.cardBackgroundNode.addSubnode(self.subtitleNode)
        self.cardBackgroundNode.addSubnode(self.playButtonNode)
        self.playButtonNode.addSubnode(self.playIconNode)
        self.playButtonNode.addSubnode(self.playLabelNode)
        self.addSubnode(self.dateAndStatusNode)
        
        self.playButtonNode.addTarget(self, action: #selector(self.playButtonPressed), forControlEvents: .touchUpInside)
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override public func didLoad() {
        super.didLoad()
        
        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(self.cardPressed))
        self.cardBackgroundNode.view.addGestureRecognizer(tapRecognizer)
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.playbackStateChanged), name: NSNotification.Name("SGDoxMusicPlaybackStateChanged"), object: nil)
    }
    
    @objc private func playbackStateChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.updatePlaybackState(animated: true)
        }
    }
    
    private func updatePlaybackState(animated: Bool) {
        guard self.isMusic else { return }
        let currentPlayingId = SGSimpleSettings.shared.currentPlayingTrackId
        let isPlaying = SGSimpleSettings.shared.isMusicPlaying && (self.currentTrackId == nil || currentPlayingId == self.currentTrackId)
        
        let iconName = isPlaying ? "pause.fill" : "play.fill"
        let iconConfig = UIImage.SymbolConfiguration(pointSize: 10, weight: .bold)
        let iconImage = UIImage(systemName: iconName, withConfiguration: iconConfig)?.withTintColor(.white, renderingMode: .alwaysOriginal)
        self.playIconNode.image = iconImage
        self.artworkOverlayNode.isHidden = !isPlaying
        
        let labelText = isPlaying ? "Pause" : "Play"
        self.playLabelNode.attributedText = NSAttributedString(
            string: labelText,
            font: Font.semibold(12.5),
            textColor: .white
        )
        
        if animated {
            UIView.animate(withDuration: 0.12, animations: {
                self.playButtonNode.view.transform = CGAffineTransform(scaleX: 1.08, y: 1.08)
            }) { _ in
                UIView.animate(withDuration: 0.12) {
                    self.playButtonNode.view.transform = .identity
                }
            }
        }
    }
    
    @objc private func playButtonPressed() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        guard let _ = self.item else { return }
        
        if self.isMusic {
            NotificationCenter.default.post(
                name: NSNotification.Name("SGDoxMusicTogglePlayRequest"),
                object: nil,
                userInfo: [
                    "trackId": self.currentTrackId ?? "",
                    "rawTag": self.rawTag,
                    "title": self.currentTitle,
                    "artist": self.currentArtist
                ]
            )
            self.updatePlaybackState(animated: true)
        } else {
            self.cardPressed()
        }
    }
    
    @objc private func cardPressed() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        guard let item = self.item, !self.rawTag.isEmpty else { return }
        item.controllerInteraction.openUrl(ChatControllerInteraction.OpenUrl(url: self.rawTag, concealed: false, message: item.message))
    }
    
    override public func tapActionAtPoint(_ point: CGPoint, gesture: TapLongTapOrDoubleTapGesture, isEstimating: Bool) -> ChatMessageBubbleContentTapAction {
        let playButtonFrame = self.cardBackgroundNode.frame.origin.x + self.playButtonNode.frame.minX
        let buttonRect = CGRect(
            origin: CGPoint(x: playButtonFrame - 6.0, y: self.cardBackgroundNode.frame.origin.y + self.playButtonNode.frame.minY - 6.0),
            size: CGSize(width: self.playButtonNode.frame.width + 12.0, height: self.playButtonNode.frame.height + 12.0)
        )
        
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
        let makeHeaderLayout = TextNode.asyncLayout(self.headerNode)
        let makeMoreDotsLayout = TextNode.asyncLayout(self.moreDotsNode)
        let makeTitleLayout = TextNode.asyncLayout(self.titleNode)
        let makeSubtitleLayout = TextNode.asyncLayout(self.subtitleNode)
        let makePlayLabelLayout = TextNode.asyncLayout(self.playLabelNode)
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
                let isAppleMusicLink = text.contains("music.apple.com")
                
                var headerText = " Music"
                var titleText = "Музыкальный трек"
                var subtitleText = "Apple Music"
                var parsedTrackId: String?
                var resolvedTag = ""
                var parsedArtworkUrl: String?
                var extractedCountry: String?
                
                if isMusicTag {
                    if let range = text.range(of: "#doxlisten:") ?? text.range(of: "doxlisten:") {
                        let remainder = String(text[range.upperBound...])
                        let components = remainder.components(separatedBy: ":")
                        if components.count >= 4 {
                            parsedTrackId = components[0]
                            titleText = components[2]
                            subtitleText = components[3].isEmpty ? "DoxMusic" : components[3]
                        }
                        if components.count >= 5, !components[4].isEmpty,
                           let data = Data(base64Encoded: components[4]),
                           let decodedArt = String(data: data, encoding: .utf8), !decodedArt.isEmpty {
                            parsedArtworkUrl = decodedArt
                        }
                        let fullTagPart = String(text[range.lowerBound...])
                        resolvedTag = fullTagPart.components(separatedBy: "\n").first ?? text
                    }
                    headerText = " Music"
                } else if isAppleMusicLink {
                    resolvedTag = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    headerText = " Music"
                    
                    // 1. Check if Telegram already parsed the webpage
                    for media in item.message.media {
                        if let webpage = media as? TelegramMediaWebpage, case let .Loaded(content) = webpage.content {
                            if let t = content.title, !t.isEmpty {
                                titleText = t
                            }
                            if let a = content.author, !a.isEmpty {
                                subtitleText = a
                            } else if let txt = content.text, !txt.isEmpty {
                                let parts = txt.components(separatedBy: " - ")
                                subtitleText = parts.first ?? txt
                            }
                            if let url = content.url.isEmpty ? nil : content.url {
                                resolvedTag = url
                            }
                        }
                    }
                    
                    // 2. Parse song ID & country from URL
                    if let url = URL(string: resolvedTag) {
                        let pathComponents = url.pathComponents.filter({ $0 != "/" })
                        if let first = pathComponents.first, first.count == 2 {
                            extractedCountry = first
                        }
                        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                           let queryItems = components.queryItems {
                            parsedTrackId = queryItems.first(where: { $0.name == "i" })?.value
                        }
                        if parsedTrackId == nil {
                            for comp in pathComponents.reversed() {
                                if CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: comp)) {
                                    parsedTrackId = comp
                                    break
                                }
                            }
                        }
                        if titleText == "Музыкальный трек" && pathComponents.count >= 3 {
                            let slug = pathComponents[2].replacingOccurrences(of: "-", with: " ").capitalized
                            titleText = slug
                        }
                    }
                } else if isWallpaperTag {
                    var quality = "720p"
                    if let range = text.range(of: "#doxwall:") ?? text.range(of: "doxwall:") {
                        let remainder = String(text[range.upperBound...])
                        let components = remainder.components(separatedBy: ":")
                        if let q = components.last?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty {
                            quality = q
                        }
                        let fullTagPart = String(text[range.lowerBound...])
                        resolvedTag = fullTagPart.components(separatedBy: "\n").first ?? text
                    }
                    headerText = "✨ Live Wallpaper"
                    titleText = "Живые видео-обои"
                    subtitleText = "Качество: \(quality)"
                }
                
                let isMusicNode = isMusicTag || isAppleMusicLink
                
                let maxCardWidth = min(constrainedSize.width - layoutConstants.text.bubbleInsets.left - layoutConstants.text.bubbleInsets.right, 310.0)
                let textWidth = max(0.0, maxCardWidth - 92.0 - 14.0)
                
                let (headerLayout, headerApply) = makeHeaderLayout(TextNodeLayoutArguments(
                    attributedString: NSAttributedString(
                        string: headerText,
                        font: Font.bold(12.5),
                        textColor: UIColor(white: 0.95, alpha: 1.0)
                    ),
                    backgroundColor: nil,
                    maximumNumberOfLines: 1,
                    truncationType: .end,
                    constrainedSize: CGSize(width: 140.0, height: .greatestFiniteMagnitude),
                    alignment: .natural,
                    cutout: nil,
                    insets: UIEdgeInsets()
                ))
                
                let (moreDotsLayout, moreDotsApply) = makeMoreDotsLayout(TextNodeLayoutArguments(
                    attributedString: NSAttributedString(
                        string: "•••",
                        font: Font.bold(11.0),
                        textColor: UIColor(white: 0.55, alpha: 1.0)
                    ),
                    backgroundColor: nil,
                    maximumNumberOfLines: 1,
                    truncationType: .none,
                    constrainedSize: CGSize(width: 30.0, height: .greatestFiniteMagnitude),
                    alignment: .natural,
                    cutout: nil,
                    insets: UIEdgeInsets()
                ))
                
                let (titleLayout, titleApply) = makeTitleLayout(TextNodeLayoutArguments(
                    attributedString: NSAttributedString(
                        string: titleText,
                        font: Font.bold(14.5),
                        textColor: UIColor.white
                    ),
                    backgroundColor: nil,
                    maximumNumberOfLines: 1,
                    truncationType: .end,
                    constrainedSize: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                    alignment: .natural,
                    cutout: nil,
                    insets: UIEdgeInsets()
                ))
                
                let (subtitleLayout, subtitleApply) = makeSubtitleLayout(TextNodeLayoutArguments(
                    attributedString: NSAttributedString(
                        string: subtitleText,
                        font: Font.regular(12.5),
                        textColor: UIColor(white: 0.65, alpha: 1.0)
                    ),
                    backgroundColor: nil,
                    maximumNumberOfLines: 1,
                    truncationType: .end,
                    constrainedSize: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                    alignment: .natural,
                    cutout: nil,
                    insets: UIEdgeInsets()
                ))
                
                let currentPlayingId = SGSimpleSettings.shared.currentPlayingTrackId
                let isCurrentlyPlaying = SGSimpleSettings.shared.isMusicPlaying && (parsedTrackId == nil || currentPlayingId == parsedTrackId)
                let playTextString = isCurrentlyPlaying ? "Pause" : "Play"
                
                let (playLabelLayout, playLabelApply) = makePlayLabelLayout(TextNodeLayoutArguments(
                    attributedString: NSAttributedString(
                        string: playTextString,
                        font: Font.semibold(12.5),
                        textColor: UIColor.white
                    ),
                    backgroundColor: nil,
                    maximumNumberOfLines: 1,
                    truncationType: .none,
                    constrainedSize: CGSize(width: 50.0, height: .greatestFiniteMagnitude),
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
                    let dateText = stringForMessageTimestampStatus(
                        context: item.context,
                        message: EngineMessage(item.message),
                        dateTimeFormat: item.presentationData.dateTimeFormat,
                        nameDisplayOrder: item.presentationData.nameDisplayOrder,
                        strings: item.presentationData.strings,
                        associatedData: item.associatedData
                    )
                    
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
                
                let cardHeight: CGFloat = 112.0
                let statusSizeAndApply = statusSuggestedWidthAndContinue?.1(maxCardWidth)
                let statusHeight: CGFloat = statusSizeAndApply?.0.height ?? 16.0
                let totalHeight = cardHeight + statusHeight + 4.0
                
                return (maxCardWidth, { boundingWidth in
                    let layoutSize = CGSize(width: boundingWidth, height: totalHeight)
                    
                    return (layoutSize, { [weak self] animation, _, _ in
                        guard let strongSelf = self else { return }
                        strongSelf.item = item
                        strongSelf.currentTrackId = parsedTrackId
                        strongSelf.isMusic = isMusicNode
                        strongSelf.rawTag = resolvedTag
                        strongSelf.currentTitle = titleText
                        strongSelf.currentArtist = subtitleText
                        
                        let cardRect = CGRect(x: 4.0, y: 4.0, width: boundingWidth - 8.0, height: cardHeight)
                        strongSelf.cardBackgroundNode.frame = cardRect
                        
                        // Apple Music dark sleek background
                        strongSelf.cardBackgroundNode.backgroundColor = UIColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 0.96)
                        strongSelf.cardBackgroundNode.layer.borderWidth = 0.5
                        strongSelf.cardBackgroundNode.layer.borderColor = UIColor(white: 1.0, alpha: 0.08).cgColor
                        
                        // Header
                        let _ = headerApply()
                        strongSelf.headerNode.frame = CGRect(x: 14.0, y: 10.0, width: headerLayout.size.width, height: headerLayout.size.height)
                        
                        let _ = moreDotsApply()
                        strongSelf.moreDotsNode.frame = CGRect(x: cardRect.width - 32.0, y: 8.0, width: moreDotsLayout.size.width, height: moreDotsLayout.size.height)
                        
                        // Artwork container
                        let artSide: CGFloat = 68.0
                        let artFrame = CGRect(x: 14.0, y: 32.0, width: artSide, height: artSide)
                        strongSelf.artworkContainerNode.frame = artFrame
                        strongSelf.artworkImageNode.frame = strongSelf.artworkContainerNode.bounds
                        strongSelf.artworkOverlayNode.frame = strongSelf.artworkContainerNode.bounds
                        
                        let waveCfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
                        strongSelf.artworkOverlayNode.image = UIImage(systemName: "waveform", withConfiguration: waveCfg)?.withTintColor(.white, renderingMode: .alwaysOriginal)
                        
                        // Default placeholder artwork
                        if isMusicNode {
                            let noteCfg = UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)
                            strongSelf.artworkImageNode.contentMode = .center
                            strongSelf.artworkImageNode.image = UIImage(systemName: "music.note", withConfiguration: noteCfg)?.withTintColor(UIColor(white: 0.8, alpha: 1.0), renderingMode: .alwaysOriginal)
                            strongSelf.artworkImageNode.backgroundColor = UIColor(white: 0.22, alpha: 1.0)
                            
                            strongSelf.fetchArtworkIfNeeded(
                                title: titleText,
                                artist: subtitleText,
                                explicitArtworkUrl: parsedArtworkUrl,
                                songId: parsedTrackId,
                                country: extractedCountry
                            )
                        } else {
                            let wpConfig = UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)
                            strongSelf.artworkImageNode.contentMode = .center
                            strongSelf.artworkImageNode.image = UIImage(systemName: "sparkles.tv.fill", withConfiguration: wpConfig)?.withTintColor(messageTheme.accentTextColor, renderingMode: .alwaysOriginal)
                            strongSelf.artworkImageNode.backgroundColor = messageTheme.accentTextColor.withAlphaComponent(0.16)
                        }
                        
                        // Title & Subtitle
                        let _ = titleApply()
                        let _ = subtitleApply()
                        let textX: CGFloat = 92.0
                        strongSelf.titleNode.frame = CGRect(x: textX, y: 32.0, width: textWidth, height: titleLayout.size.height)
                        strongSelf.subtitleNode.frame = CGRect(x: textX, y: 52.0, width: textWidth, height: subtitleLayout.size.height)
                        
                        // Play button (Apple Music signature magenta pill)
                        let btnWidth: CGFloat = 84.0
                        let btnHeight: CGFloat = 28.0
                        strongSelf.playButtonNode.frame = CGRect(x: textX, y: 72.0, width: btnWidth, height: btnHeight)
                        strongSelf.playButtonNode.backgroundColor = UIColor(red: 250.0/255.0, green: 45.0/255.0, blue: 85.0/255.0, alpha: 1.0)
                        
                        let _ = playLabelApply()
                        strongSelf.playIconNode.frame = CGRect(x: 10.0, y: 7.0, width: 14.0, height: 14.0)
                        strongSelf.playLabelNode.frame = CGRect(x: 27.0, y: 6.0, width: playLabelLayout.size.width, height: playLabelLayout.size.height)
                        
                        if isMusicNode {
                            strongSelf.updatePlaybackState(animated: false)
                        } else {
                            let actConfig = UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)
                            strongSelf.playIconNode.image = UIImage(systemName: "arrow.down.circle.fill", withConfiguration: actConfig)?.withTintColor(.white, renderingMode: .alwaysOriginal)
                            strongSelf.playLabelNode.attributedText = NSAttributedString(
                                string: "Обои",
                                font: Font.semibold(12.5),
                                textColor: .white
                            )
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
    
    private func fetchArtworkIfNeeded(title: String, artist: String, explicitArtworkUrl: String?, songId: String?, country: String?) {
        // 1. Explicit artwork URL from tag
        if let explicit = explicitArtworkUrl, !explicit.isEmpty, let url = URL(string: explicit) {
            let cacheKey = explicit
            if let cached = Self.artworkCache[cacheKey] {
                self.artworkImageNode.contentMode = .scaleAspectFill
                self.artworkImageNode.image = cached
                return
            }
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data = data, let img = UIImage(data: data) else { return }
                DispatchQueue.main.async {
                    Self.artworkCache[cacheKey] = img
                    self?.artworkImageNode.contentMode = .scaleAspectFill
                    self?.artworkImageNode.image = img
                }
            }.resume()
            return
        }
        
        let cleanT = self.cleanString(title)
        let cleanA = self.cleanString(artist)
        let cacheKey = "\(cleanT)_\(cleanA)"
        if let cached = Self.artworkCache[cacheKey] {
            self.artworkImageNode.contentMode = .scaleAspectFill
            self.artworkImageNode.image = cached
            return
        }
        
        // 2. iTunes ID lookup if songId is available
        if let songId = songId, !songId.isEmpty {
            let lookupCountry = country ?? "us"
            let lookupUrlStr = "https://itunes.apple.com/lookup?id=\(songId)&country=\(lookupCountry)"
            if let lookupUrl = URL(string: lookupUrlStr) {
                URLSession.shared.dataTask(with: lookupUrl) { [weak self] data, _, _ in
                    if let data = data,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let results = json["results"] as? [[String: Any]],
                       let first = results.first,
                       let artUrlString = (first["artworkUrl100"] as? String)?.replacingOccurrences(of: "100x100bb", with: "600x600bb"),
                       let artUrl = URL(string: artUrlString) {
                        URLSession.shared.dataTask(with: artUrl) { [weak self] imgData, _, _ in
                            guard let imgData = imgData, let img = UIImage(data: imgData) else { return }
                            DispatchQueue.main.async {
                                Self.artworkCache[cacheKey] = img
                                self?.artworkImageNode.contentMode = .scaleAspectFill
                                self?.artworkImageNode.image = img
                            }
                        }.resume()
                        return
                    }
                    // Fallback search
                    self?.searchArtworkFallback(title: cleanT, artist: cleanA, cacheKey: cacheKey)
                }.resume()
                return
            }
        }
        
        // 3. Strict search fallback
        self.searchArtworkFallback(title: cleanT, artist: cleanA, cacheKey: cacheKey)
    }
    
    private func searchArtworkFallback(title: String, artist: String, cacheKey: String) {
        let normTitle = self.normalizeForMatch(title)
        let normArtist = self.normalizeForMatch(artist)
        guard !normTitle.isEmpty else { return }
        
        let queryTerm = "\(normTitle) \(normArtist)".trimmingCharacters(in: .whitespacesAndNewlines)
        guard let encoded = queryTerm.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&entity=song&limit=15") else { return }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self = self, let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]] else {
                return
            }
            
            var matchedArtUrl: String? = nil
            for item in results {
                let itemArtist = self.normalizeForMatch(item["artistName"] as? String ?? "")
                let itemTrack = self.normalizeForMatch(item["trackName"] as? String ?? "")
                
                let titleMatch = itemTrack.contains(normTitle) || normTitle.contains(itemTrack)
                let artistMatch = normArtist.isEmpty || itemArtist.contains(normArtist) || normArtist.contains(itemArtist)
                
                if titleMatch && artistMatch {
                    matchedArtUrl = (item["artworkUrl100"] as? String)?.replacingOccurrences(of: "100x100bb", with: "600x600bb")
                    break
                }
            }
            
            if matchedArtUrl == nil && !normArtist.isEmpty {
                let artistWords = normArtist.components(separatedBy: " ").filter({ $0.count >= 3 })
                for item in results {
                    let itemArtist = self.normalizeForMatch(item["artistName"] as? String ?? "")
                    let itemTrack = self.normalizeForMatch(item["trackName"] as? String ?? "")
                    let titleMatch = itemTrack.contains(normTitle) || normTitle.contains(itemTrack)
                    let anyWordMatch = artistWords.contains(where: { itemArtist.contains($0) })
                    if titleMatch && anyWordMatch {
                        matchedArtUrl = (item["artworkUrl100"] as? String)?.replacingOccurrences(of: "100x100bb", with: "600x600bb")
                        break
                    }
                }
            }
            
            // Only update artwork if an actual match was confirmed
            if let artUrlString = matchedArtUrl, let artUrl = URL(string: artUrlString) {
                URLSession.shared.dataTask(with: artUrl) { [weak self] imgData, _, _ in
                    guard let imgData = imgData, let img = UIImage(data: imgData) else { return }
                    DispatchQueue.main.async {
                        Self.artworkCache[cacheKey] = img
                        self?.artworkImageNode.contentMode = .scaleAspectFill
                        self?.artworkImageNode.image = img
                    }
                }.resume()
            }
        }.resume()
    }
    
    private func cleanString(_ str: String) -> String {
        return str.replacingOccurrences(of: "«", with: "")
            .replacingOccurrences(of: "»", with: "")
            .replacingOccurrences(of: "DoxMusic", with: "")
            .replacingOccurrences(of: "•", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func normalizeForMatch(_ str: String) -> String {
        return str.lowercased()
            .replacingOccurrences(of: "(feat.", with: "")
            .replacingOccurrences(of: "(ft.", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: "★", with: "")
            .replacingOccurrences(of: "•", with: "")
            .replacingOccurrences(of: "—", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
