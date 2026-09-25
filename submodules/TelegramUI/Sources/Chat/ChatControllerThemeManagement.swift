import Foundation
import UIKit
import SwiftSignalKit
import Display
import AsyncDisplayKit
import TelegramCore
import SafariServices
import MobileCoreServices
import Intents
import LegacyComponents
import TelegramPresentationData
import TelegramUIPreferences
import DeviceAccess
import TextFormat
import TelegramBaseController
import AccountContext
import TelegramStringFormatting
import OverlayStatusController
import DeviceLocationManager
import UrlEscaping
import ContextUI
import AlertUI
import PresentationDataUtils
import UndoUI
import TelegramCallsUI
import TelegramNotices
import GameUI
import ScreenCaptureDetection
import GalleryUI
import OpenInExternalAppUI
import LegacyUI
import InstantPageUI
import LocationUI
import BotPaymentsUI
import DeleteChatPeerActionSheetItem
import HashtagSearchUI
import LegacyMediaPickerUI
import Emoji
import PeerAvatarGalleryUI
import PeerInfoUI
import RaiseToListen
import UrlHandling
import AvatarNode
import AppBundle
import LocalizedPeerData
import PhoneNumberFormat
import SettingsUI
import UrlWhitelist
import TelegramIntents
import TooltipUI
import StatisticsUI
import MediaResources
import GalleryData
import ChatInterfaceState
import InviteLinksUI
import Markdown
import TelegramPermissionsUI
import Speak
import TranslateUI
import UniversalMediaPlayer
import WallpaperBackgroundNode
import ChatListUI
import CalendarMessageScreen
import ReactionSelectionNode
import ReactionListContextMenuContent
import AttachmentUI
import AttachmentTextInputPanelNode
import MediaPickerUI
import ChatPresentationInterfaceState
import Pasteboard
import ChatSendMessageActionUI
import ChatTextLinkEditUI
import WebUI
import PremiumUI
import ImageTransparency
import StickerPackPreviewUI
import TextNodeWithEntities
import EntityKeyboard
import ChatTitleView
import EmojiStatusComponent
import ChatTimerScreen
import MediaPasteboardUI
import ChatListHeaderComponent
import ChatControllerInteraction
import FeaturedStickersScreen
import SGSimpleSettings
import ChatEntityKeyboardInputNode
import StorageUsageScreen
import AvatarEditorScreen
import ChatScheduleTimeController
import ICloudResources
import StoryContainerScreen
import MoreHeaderButton
import VolumeButtons
import ChatAvatarNavigationNode
import ChatContextQuery
import PeerReportScreen
import PeerSelectionController
import SaveToCameraRoll
import ChatMessageDateAndStatusNode
import ReplyAccessoryPanelNode
import TextSelectionNode
import ChatMessagePollBubbleContentNode
import ChatMessageItem
import ChatMessageItemImpl
import ChatMessageItemView
import ChatMessageItemCommon
import ChatMessageAnimatedStickerItemNode
import ChatMessageBubbleItemNode
import ChatNavigationButton
import WebsiteType
import PeerInfoScreen
import MediaEditorScreen
import WallpaperGalleryScreen
import WallpaperGridScreen
import VideoMessageCameraScreen
import TopMessageReactions
import AudioWaveform
import PeerNameColorScreen
import ChatEmptyNode
import ChatMediaInputStickerGridItem
import Photos
import ChatThemeScreen

extension ChatControllerImpl {
    public func presentThemeSelection() {
        guard self.themeScreen == nil else {
            return
        }
        let context = self.context
        let peerId = self.chatLocation.peerId
        
        self.updateChatPresentationInterfaceState(animated: true, interactive: true, { state in
            var updated = state
            updated = updated.updatedInputMode({ _ in
                return .none
            })
            updated = updated.updatedShowCommands(false)
            return updated
        })
        
        let animatedEmojiStickers = context.engine.stickers.loadedStickerPack(reference: .animatedEmoji, forceActualized: false)
        |> map { animatedEmoji -> [String: [StickerPackItem]] in
            var animatedEmojiStickers: [String: [StickerPackItem]] = [:]
            switch animatedEmoji {
                case let .result(_, items, _):
                    for item in items {
                        if let emoji = item.getStringRepresentationsOfIndexKeys().first {
                            animatedEmojiStickers[emoji.basicEmoji.0] = [item]
                            let strippedEmoji = emoji.basicEmoji.0.strippedEmoji
                            if animatedEmojiStickers[strippedEmoji] == nil {
                                animatedEmojiStickers[strippedEmoji] = [item]
                            }
                        }
                    }
                default:
                    break
            }
            return animatedEmojiStickers
        }
        
        let _ = (combineLatest(queue: Queue.mainQueue(), self.chatThemePromise.get(), animatedEmojiStickers)
        |> take(1)).startStandalone(next: { [weak self] chatTheme, animatedEmojiStickers in
            guard let strongSelf = self, let peer = strongSelf.presentationInterfaceState.renderedPeer?.peer else {
                return
            }
            
            var canResetWallpaper = false
            if let cachedUserData = strongSelf.contentData?.state.peerView?.cachedData as? CachedUserData {
                canResetWallpaper = cachedUserData.wallpaper != nil
            }
            
            let controller = ChatThemeScreen(
                context: context,
                updatedPresentationData: strongSelf.updatedPresentationData,
                animatedEmojiStickers: animatedEmojiStickers,
                initiallySelectedTheme: chatTheme,
                peerName: strongSelf.presentationInterfaceState.renderedPeer?.chatMainPeer.flatMap(EnginePeer.init)?.compactDisplayTitle ?? "",
                canResetWallpaper: canResetWallpaper,
                previewTheme: { [weak self] chatTheme, dark in
                    if let strongSelf = self {
                        strongSelf.presentCrossfadeSnapshot()
                        strongSelf.chatThemeAndDarkAppearancePreviewPromise.set(.single((chatTheme, dark)))
                    }
                },
                changeWallpaper: { [weak self] in
                    guard let self, let peerId else {
                        return
                    }
                    if let themeController = self.themeScreen {
                        self.themeScreen = nil
                        themeController.dimTapped()
                    }                    
                    let dismissControllers = { [weak self] in
                        if let self, let navigationController = self.navigationController as? NavigationController {
                            let controllers = navigationController.viewControllers.filter({ controller in
                                if controller is WallpaperGalleryController || controller is AttachmentController {
                                    return false
                                }
                                return true
                            })
                            navigationController.setViewControllers(controllers, animated: true)
                        }
                    }
                    var openWallpaperPickerImpl: ((Bool) -> Void)?
                    let openWallpaperPicker = { [weak self] (animateAppearance: Bool) in
                        guard let self else {
                            return
                        }
                        let controller = wallpaperMediaPickerController(
                            context: context,
                            updatedPresentationData: self.updatedPresentationData,
                            peer: EnginePeer(peer),
                            animateAppearance: animateAppearance,
                            completion: { [weak self] _, result in
                                guard let self, let asset = result as? PHAsset else {
                                    return
                                }
                                let controller = WallpaperGalleryController(context: context, source: .asset(asset), mode: .peer(EnginePeer(peer), false))
                                controller.navigationPresentation = .modal
                                controller.apply = { wallpaper, options, editedImage, cropRect, brightness, forBoth in
                                    uploadCustomPeerWallpaper(context: context, wallpaper: wallpaper, mode: options, editedImage: editedImage, cropRect: cropRect, brightness: brightness, peerId: peerId, forBoth: forBoth, completion: {
                                        Queue.mainQueue().after(0.3, {
                                            dismissControllers()
                                        })
                                    })
                                }
                                self.push(controller)
                            },
                            openColors: { [weak self] in
                                guard let self else {
                                    return
                                }
                                let controller = standaloneColorPickerController(context: context, peer: EnginePeer(peer), push: { [weak self] controller in
                                    if let self {
                                        self.push(controller)
                                    }
                                }, openGallery: {
                                    openWallpaperPickerImpl?(false)
                                })
                                controller.navigationPresentation = .flatModal
                                self.push(controller)
                            }
                        )
                        controller.navigationPresentation = .flatModal
                        self.push(controller)
                    }
                    openWallpaperPickerImpl = openWallpaperPicker
                    let presentationData = self.presentationData
                    let isRu = presentationData.strings.baseLanguageCode.hasPrefix("ru")
                    let actionSheet = ActionSheetController(presentationData: presentationData)
                    actionSheet.setItemGroups([
                        ActionSheetItemGroup(items: [
                            ActionSheetButtonItem(title: isRu ? "Обычные обои Telegram" : "Standard Telegram Wallpapers", color: .accent, action: { [weak actionSheet] in
                                actionSheet?.dismissAnimated()
                                openWallpaperPicker(true)
                            }),
                            ActionSheetButtonItem(title: isRu ? "Анимированные видео-обои (DoxGram)" : "Animated Video Wallpapers (DoxGram)", color: .accent, action: { [weak actionSheet, weak self] in
                                actionSheet?.dismissAnimated()
                                self?.presentDoxAnimatedWallpaperDialog()
                            })
                        ]),
                        ActionSheetItemGroup(items: [
                            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                                actionSheet?.dismissAnimated()
                            })
                        ])
                    ])
                    self.present(actionSheet, in: .window(.root))
                },
                resetWallpaper: { [weak self] in
                    guard let self, let peerId else {
                        return
                    }
                    let _ = self.context.engine.themes.setChatWallpaper(peerId: peerId, wallpaper: nil, forBoth: false).startStandalone()
                },
                completion: { [weak self] chatTheme in
                    guard let self, let peerId else {
                        return
                    }
                    if canResetWallpaper && chatTheme != nil {
                        let _ = context.engine.themes.setChatWallpaper(peerId: peerId, wallpaper: nil, forBoth: true).startStandalone()
                    }
                    strongSelf.chatThemeAndDarkAppearancePreviewPromise.set(.single((chatTheme ?? .emoticon(""), nil)))
                    let _ = context.engine.themes.setChatTheme(peerId: peerId, chatTheme: chatTheme ?? .emoticon("")).startStandalone(completed: { [weak self] in
                        if let self {
                            self.chatThemeAndDarkAppearancePreviewPromise.set(.single((nil, nil)))
                        }
                    })
                }
            )
            controller.navigationPresentation = .flatModal
            controller.passthroughHitTestImpl = { [weak self] _ in
                if let strongSelf = self {
                    return strongSelf.chatDisplayNode.historyNode.view
                } else {
                    return nil
                }
            }
            controller.dismissed = { [weak self] in
                if let strongSelf = self {
                    strongSelf.chatDisplayNode.historyNode.tapped = nil
                }
            }
            strongSelf.chatDisplayNode.historyNode.tapped = { [weak controller] in
                controller?.dimTapped()
            }
            strongSelf.push(controller)
            strongSelf.themeScreen = controller
        })
    }
    
    func presentEmojiList(references: [StickerPackReference], previewIconFile: TelegramMediaFile? = nil) {
        guard let packReference = references.first else {
            return
        }
        self.chatDisplayNode.dismissTextInput()
        
        var previewIconFile: TelegramMediaFile? = previewIconFile
        if let file = previewIconFile, let peerId = self.chatLocation.peerId, !file.isValidForDisplay(chatPeerId: peerId) {
            previewIconFile = nil
        }
        
        let presentationData = self.presentationData
        let controller = StickerPackScreen(context: self.context, updatedPresentationData: self.updatedPresentationData, mainStickerPack: packReference, stickerPacks: Array(references), previewIconFile: previewIconFile, parentNavigationController: self.effectiveNavigationController, sendEmoji: canSendMessagesToChat(self.presentationInterfaceState) ? { [weak self] text, attribute in
            if let strongSelf = self {
                strongSelf.controllerInteraction?.sendEmoji(text, attribute, false)
            }
        } : nil, actionPerformed: { [weak self] actions in
            guard let strongSelf = self else {
                return
            }
            let context = strongSelf.context
            if actions.count > 1, let first = actions.first {
                if case .add = first.2 {
                    strongSelf.presentInGlobalOverlay(UndoOverlayController(presentationData: presentationData, content: .stickersModified(title: presentationData.strings.EmojiPackActionInfo_AddedTitle, text: presentationData.strings.EmojiPackActionInfo_MultipleAddedText(Int32(actions.count)), undo: false, info: first.0, topItem: first.1.first, context: context), elevatedLayout: true, animateInAsReplacement: false, action: { _ in
                        return true
                    }))
                } else if actions.allSatisfy({
                    if case .remove = $0.2 {
                        return true
                    } else {
                        return false
                    }
                }) {
                    let isEmoji = actions[0].0.id.namespace == Namespaces.ItemCollection.CloudEmojiPacks
                    strongSelf.presentInGlobalOverlay(UndoOverlayController(presentationData: presentationData, content: .stickersModified(title: isEmoji ? presentationData.strings.EmojiPackActionInfo_RemovedTitle : presentationData.strings.StickerPackActionInfo_RemovedTitle, text: isEmoji ? presentationData.strings.EmojiPackActionInfo_MultipleRemovedText(Int32(actions.count)) : presentationData.strings.StickerPackActionInfo_MultipleRemovedText(Int32(actions.count)), undo: true, info: actions[0].0, topItem: actions[0].1.first, context: context), elevatedLayout: true, animateInAsReplacement: false, action: { action in
                        if case .undo = action {
                            var itemsAndIndices: [(StickerPackCollectionInfo, [StickerPackItem], Int)] = actions.compactMap { action -> (StickerPackCollectionInfo, [StickerPackItem], Int)? in
                                if case let .remove(index) = action.2 {
                                    return (action.0, action.1, index)
                                } else {
                                    return nil
                                }
                            }
                            itemsAndIndices.sort(by: { $0.2 < $1.2 })
                            for (info, items, index) in itemsAndIndices.reversed() {
                                let _ = context.engine.stickers.addStickerPackInteractively(info: info, items: items, positionInList: index).startStandalone()
                            }
                        }
                        return true
                    }))
                }
            } else if let (info, items, action) = actions.first {
                let isEmoji = info.id.namespace == Namespaces.ItemCollection.CloudEmojiPacks
                switch action {
                case .add:
                    strongSelf.presentInGlobalOverlay(UndoOverlayController(presentationData: presentationData, content: .stickersModified(title: isEmoji ? presentationData.strings.EmojiPackActionInfo_AddedTitle : presentationData.strings.StickerPackActionInfo_AddedTitle, text: isEmoji ? presentationData.strings.EmojiPackActionInfo_AddedText(info.title).string : presentationData.strings.StickerPackActionInfo_AddedText(info.title).string, undo: false, info: info, topItem: items.first, context: context), elevatedLayout: true, animateInAsReplacement: false, action: { _ in
                        return true
                    }))
                case let .remove(positionInList):
                    strongSelf.presentInGlobalOverlay(UndoOverlayController(presentationData: presentationData, content: .stickersModified(title: isEmoji ? presentationData.strings.EmojiPackActionInfo_RemovedTitle : presentationData.strings.StickerPackActionInfo_RemovedTitle, text: isEmoji ? presentationData.strings.EmojiPackActionInfo_RemovedText(info.title).string : presentationData.strings.StickerPackActionInfo_RemovedText(info.title).string, undo: true, info: info, topItem: items.first, context: context), elevatedLayout: true, animateInAsReplacement: false, action: { action in
                        if case .undo = action {
                            let _ = context.engine.stickers.addStickerPackInteractively(info: info, items: items, positionInList: positionInList).startStandalone()
                        }
                        return true
                    }))
                }
            }
        })
        self.present(controller, in: .window(.root))
    }
    
    public func presentDoxAnimatedWallpaperDialog() {
        guard let peerId = self.chatLocation.peerId else {
            return
        }
        let presentationData = self.presentationData
        let isRu = presentationData.strings.baseLanguageCode.hasPrefix("ru")
        let rawPeerId = peerId.toInt64()
        let hasSpecific = SGDoxAnimatedWallpaperManager.shared.hasChatSpecificWallpaper(for: rawPeerId)
        
        let actionSheet = ActionSheetController(presentationData: presentationData)
        var items: [ActionSheetItem] = []
        
        items.append(ActionSheetButtonItem(title: isRu ? "Выбрать из Фото (Галереи)" : "Pick from Photo Library", color: .accent, action: { [weak actionSheet, weak self] in
            actionSheet?.dismissAnimated()
            guard let self = self else { return }
            SGDoxVideoPickerHelper.shared.pickVideoFromGallery(from: self) { [weak self] selectedUrl in
                guard let strongSelf = self, let selectedUrl = selectedUrl else { return }
                strongSelf.promptAndApplyDoxWallpaper(selectedUrl: selectedUrl, rawPeerId: rawPeerId)
            }
        }))
        
        items.append(ActionSheetButtonItem(title: isRu ? "Выбрать из Файлов (iCloud)" : "Pick from Files", color: .accent, action: { [weak actionSheet, weak self] in
            actionSheet?.dismissAnimated()
            guard let self = self else { return }
            SGDoxVideoPickerHelper.shared.pickVideoFromFiles(from: self) { [weak self] selectedUrl in
                guard let strongSelf = self, let selectedUrl = selectedUrl else { return }
                strongSelf.promptAndApplyDoxWallpaper(selectedUrl: selectedUrl, rawPeerId: rawPeerId)
            }
        }))
        
        items.append(ActionSheetButtonItem(title: isRu ? "Ввести ссылку (URL / TikTok)" : "Enter URL or TikTok Link", color: .accent, action: { [weak actionSheet, weak self] in
            actionSheet?.dismissAnimated()
            self?.presentDoxAnimatedWallpaperUrlAlert(peerId: rawPeerId)
        }))
        
        if hasSpecific {
            items.append(ActionSheetButtonItem(title: isRu ? "Сбросить обои для этого чата" : "Reset Wallpaper for This Chat", color: .destructive, action: { [weak actionSheet, weak self] in
                actionSheet?.dismissAnimated()
                SGDoxAnimatedWallpaperManager.shared.removeWallpaper(for: rawPeerId)
                self?.chatDisplayNode.updateDoxVideoWallpaper()
            }))
        }
        
        actionSheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                })
            ])
        ])
        self.present(actionSheet, in: .window(.root))
    }
    
    private func promptAndApplyDoxWallpaper(selectedUrl: URL, rawPeerId: Int64) {
        let presentationData = self.presentationData
        let isRu = presentationData.strings.baseLanguageCode.hasPrefix("ru")
        
        let alert = UIAlertController(
            title: isRu ? "Анимированные видео-обои" : "Animated Video Wallpapers",
            message: isRu ? "Установить анимированные обои только для себя или для обоих участников чата?" : "Set animated wallpaper only for yourself or for both participants in this chat?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: isRu ? "Только для себя" : "For Me Only", style: .default, handler: { [weak self] _ in
            SGDoxAnimatedWallpaperManager.shared.setLocalWallpaper(from: selectedUrl, for: rawPeerId) { [weak self] success, _ in
                if success {
                    self?.chatDisplayNode.updateDoxVideoWallpaper()
                }
            }
        }))
        
        alert.addAction(UIAlertAction(title: isRu ? "Установить для обоих (DoxGram)" : "Set for Both (DoxGram)", style: .default, handler: { [weak self] _ in
            guard let strongSelf = self else { return }
            
            // 1. Set locally immediately
            SGDoxAnimatedWallpaperManager.shared.setLocalWallpaper(from: selectedUrl, for: rawPeerId) { [weak self] success, _ in
                if success {
                    self?.chatDisplayNode.updateDoxVideoWallpaper()
                }
            }
            
            // 2. Send video into chat with #doxwall for automatic friend sync
            strongSelf.sendDoxVideoWallpaperMessage(videoUrl: selectedUrl)
        }))
        
        alert.addAction(UIAlertAction(title: presentationData.strings.Common_Cancel, style: .cancel, handler: nil))
        
        self.context.sharedContext.applicationBindings.presentNativeController(alert)
    }
    
    private func sendDoxVideoWallpaperMessage(videoUrl: URL) {
        let isSecurityScoped = videoUrl.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                videoUrl.stopAccessingSecurityScopedResource()
            }
        }
        
        guard let data = try? Data(contentsOf: videoUrl), !data.isEmpty else { return }
        
        let _ = (legacyEnqueueGifMessage(account: self.context.account, data: data)
        |> deliverOnMainQueue).startStandalone(next: { [weak self] message in
            guard let self = self else { return }
            var updatedMessage = message
            if case let .message(_, attributes, inlineStickers, mediaReference, _, replyToMessageId, replyToStoryId, localGroupingKey, correlationId, bubbleUpEmojiOrStickersets) = message {
                updatedMessage = .message(
                    text: "🎬 Анимированные обои чата #doxwall",
                    attributes: attributes,
                    inlineStickers: inlineStickers,
                    mediaReference: mediaReference,
                    threadId: self.chatLocation.threadId,
                    replyToMessageId: replyToMessageId,
                    replyToStoryId: replyToStoryId,
                    localGroupingKey: localGroupingKey,
                    correlationId: correlationId,
                    bubbleUpEmojiOrStickersets: bubbleUpEmojiOrStickersets
                )
            }
            self.sendMessages([updatedMessage])
        })
    }
    
    private func presentDoxAnimatedWallpaperUrlAlert(peerId: Int64) {
        let presentationData = self.presentationData
        let isRu = presentationData.strings.baseLanguageCode.hasPrefix("ru")
        
        let alert = UIAlertController(
            title: isRu ? "Анимированные видео-обои" : "Animated Video Wallpapers",
            message: isRu ? "Вставьте прямую ссылку на видео (MP4) или ссылку на видео из TikTok (tiktok.com, vt.tiktok.com):" : "Paste a direct MP4 URL or TikTok video link (tiktok.com, vt.tiktok.com):",
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.placeholder = "https://... / tiktok.com/..."
            textField.text = SGDoxAnimatedWallpaperManager.shared.wallpaperUrl(for: peerId)
            textField.clearButtonMode = .whileEditing
            textField.keyboardType = .URL
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        
        alert.addAction(UIAlertAction(title: presentationData.strings.Common_Cancel, style: .cancel, handler: nil))
        
        alert.addAction(UIAlertAction(title: isRu ? "Установить" : "Set", style: .default, handler: { [weak self, weak alert] _ in
            guard let strongSelf = self else { return }
            guard let urlString = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !urlString.isEmpty else {
                return
            }
            let quality = SGDoxAnimatedWallpaperManager.shared.currentQuality
            let hud = OverlayStatusController(style: .dark, type: .loading(cancelled: nil))
            strongSelf.present(hud, in: .window(.root))
            
            SGDoxAnimatedWallpaperManager.shared.setWallpaper(for: peerId, urlString: urlString, quality: quality) { [weak self, weak hud] success, errorText in
                hud?.dismiss()
                guard let strongSelf = self else { return }
                if success {
                    strongSelf.chatDisplayNode.updateDoxVideoWallpaper()
                    let overlay = UndoOverlayController(presentationData: strongSelf.presentationData, content: .actionSucceeded(title: nil, text: isRu ? "Видео-обои установлены" : "Video wallpaper applied", cancel: nil, destructive: false), elevatedLayout: false, action: { _ in return false })
                    strongSelf.present(overlay, in: .window(.root))
                } else {
                    let overlay = UndoOverlayController(presentationData: strongSelf.presentationData, content: .info(title: isRu ? "Ошибка" : "Error", text: errorText ?? (isRu ? "Не удалось загрузить видео" : "Failed to load video"), timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false })
                    strongSelf.present(overlay, in: .window(.root))
                }
            }
        }))
        
        alert.addAction(UIAlertAction(title: isRu ? "Установить для обоих (DoxGram)" : "Set for Both (DoxGram)", style: .default, handler: { [weak self, weak alert] _ in
            guard let strongSelf = self else { return }
            guard let urlString = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !urlString.isEmpty else {
                return
            }
            let quality = SGDoxAnimatedWallpaperManager.shared.currentQuality
            let hud = OverlayStatusController(style: .dark, type: .loading(cancelled: nil))
            strongSelf.present(hud, in: .window(.root))
            
            SGDoxAnimatedWallpaperManager.shared.setWallpaper(for: peerId, urlString: urlString, quality: quality) { [weak self, weak hud] success, errorText in
                hud?.dismiss()
                guard let strongSelf = self else { return }
                if success {
                    strongSelf.chatDisplayNode.updateDoxVideoWallpaper()
                    let syncTag = SGDoxAnimatedWallpaperManager.shared.formatSyncTag(url: urlString, quality: quality)
                    strongSelf.controllerInteraction?.sendMessage(syncTag, nil)
                    let overlay = UndoOverlayController(presentationData: strongSelf.presentationData, content: .actionSucceeded(title: nil, text: isRu ? "Обои установлены и отправлены собеседнику" : "Wallpaper applied and sent to chat", cancel: nil, destructive: false), elevatedLayout: false, action: { _ in return false })
                    strongSelf.present(overlay, in: .window(.root))
                } else {
                    let overlay = UndoOverlayController(presentationData: strongSelf.presentationData, content: .info(title: isRu ? "Ошибка" : "Error", text: errorText ?? (isRu ? "Не удалось загрузить видео" : "Failed to load video"), timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false })
                    strongSelf.present(overlay, in: .window(.root))
                }
            }
        }))
        
        self.context.sharedContext.applicationBindings.presentNativeController(alert)
    }
}
