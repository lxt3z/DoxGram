// MARK: DoxGram Settings Controller
import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import MtProtoKit
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import OverlayStatusController
import AccountContext
import AppBundle
import UndoUI
import SettingsUI

import SGItemListUI
import SGLogging
import SGSimpleSettings
import SGStrings
import SGProUI

private enum SGDoxControllerSection: Int32, SGItemListSection {
    case doxgramPro
    case doxMusic
    case ghost
    case media
    case streamer
    case privacy
    case antiDeanon
    case wsProxy
    case animatedWallpapers
    case debug
}

private enum SGDoxBoolSetting: String {
    case inputToolbar
    case ghostDontSendTyping
    case ghostDontSendOnline
    case ghostDontSendRead
    case ghostDontSendVoiceListen
    case ghostDontReadStories
    case keepViewOnceMedia
    case antiRecall
    case keepEditHistory
    case streamerMode
    case hideAds
    case hideChannelAds
    case blockScreenshotNotifications
    case bypassCopyProtection
    case disableTelemetry
    case warnOnIpLoggers
    case cleanUrlTrackers
    case warnOnAllExternalLinks
    case tgWsProxyEnabled
    case tgWsProxyFakeTLS
    case hideProxyButton
    case ayugramDebugger
    case discordRpcEnabled
}

private enum SGDoxOneFromManySetting: String {
    case pinnedMessageNotifications
    case mentionsAndRepliesNotifications
    case ayugramRetention
    case animatedWallpaperQuality
}

private enum SGDoxDisclosureLink: String {
    case sessionBackupManager
    case messageFilter
    case appIcons
    case appBages
    case doxMusic
    case discordRpcToken
    case deletedMediaVault
    case streamerSettings
    case tgWsProxyWorkerDomain
    case globalAnimatedWallpaper
    case clearAnimatedWallpaperCache
    case ayugramExportLogs
    case ayugramClearLogs
}

private typealias SGDoxControllerEntry = SGItemListUIEntry<SGDoxControllerSection, SGDoxBoolSetting, AnyHashable, SGDoxOneFromManySetting, SGDoxDisclosureLink, AnyHashable>

private func SGDoxControllerEntries(presentationData: PresentationData) -> [SGDoxControllerEntry] {
    var entries: [SGDoxControllerEntry] = []
    let lang = presentationData.strings.baseLanguageCode
    let isRu = lang.hasPrefix("ru")
    let id = SGItemListCounter()

    // MARK: - DoxGram Pro
    entries.append(.header(id: id.count, section: .doxgramPro, text: "DoxGram Pro", badge: nil))
    entries.append(.disclosure(id: id.count, section: .doxgramPro, link: .sessionBackupManager, text: "SessionBackup.Title".i18n(lang)))
    entries.append(.disclosure(id: id.count, section: .doxgramPro, link: .messageFilter, text: "MessageFilter.Title".i18n(lang)))
    entries.append(.toggle(id: id.count, section: .doxgramPro, settingName: .inputToolbar, value: SGSimpleSettings.shared.inputToolbar, text: "InputToolbar.Title".i18n(lang), enabled: true))
    entries.append(.oneFromManySelector(id: id.count, section: .doxgramPro, settingName: .pinnedMessageNotifications, text: "Notifications.PinnedMessages.Title".i18n(lang), value: "Notifications.PinnedMessages.value.\(SGSimpleSettings.shared.pinnedMessageNotifications)".i18n(lang), enabled: true))
    entries.append(.oneFromManySelector(id: id.count, section: .doxgramPro, settingName: .mentionsAndRepliesNotifications, text: "Notifications.MentionsAndReplies.Title".i18n(lang), value: "Notifications.MentionsAndReplies.value.\(SGSimpleSettings.shared.mentionsAndRepliesNotifications)".i18n(lang), enabled: true))
    entries.append(.disclosure(id: id.count, section: .doxgramPro, link: .appIcons, text: presentationData.strings.Appearance_AppIcon))
    entries.append(.disclosure(id: id.count, section: .doxgramPro, link: .appBages, text: "AppBadge.Title".i18n(lang)))
    entries.append(.notice(id: id.count, section: .doxgramPro, text: "AppBadge.Notice".i18n(lang)))

    // MARK: - DoxMusic & Discord RPC
    entries.append(.header(id: id.count, section: .doxMusic, text: isRu ? "Музыка DoxMusic (Apple Music & Spotify)" : "DoxMusic (Apple Music & Spotify)", badge: nil))
    entries.append(.disclosure(id: id.count, section: .doxMusic, link: .doxMusic, text: isRu ? "Плеер и стриминг" : "Music Player & Streaming"))
    entries.append(.toggle(id: id.count, section: .doxMusic, settingName: .discordRpcEnabled, value: SGSimpleSettings.shared.discordRpcEnabled, text: "Discord Rich Presence (RPC)", enabled: true))
    if SGSimpleSettings.shared.discordRpcEnabled {
        let tokenSet = !SGSimpleSettings.shared.discordRpcToken.isEmpty
        let tokenDesc = tokenSet ? (isRu ? "Настроен" : "Configured") : (isRu ? "Не настроен" : "Not configured")
        entries.append(.disclosure(id: id.count, section: .doxMusic, link: .discordRpcToken, text: "\(isRu ? "Токен Discord" : "Discord Token") (\(tokenDesc))"))
    }
    entries.append(.notice(id: id.count, section: .doxMusic, text: isRu ? "Слушайте треки из Apple Music и Spotify с умной «Волной». Любой трек можно поставить в официальный профиль Telegram одним тапом и транслировать статус «Слушает...» в Discord." : "Stream tracks from Apple Music & Spotify with smart Wave. Pin any track directly to your official Telegram profile in 1 tap, and broadcast your listening status to Discord."))

    // MARK: - Ghost Mode
    entries.append(.header(id: id.count, section: .ghost, text: i18n("Settings.Ayugram.GhostHeader", lang), badge: nil))
    entries.append(.toggle(id: id.count, section: .ghost, settingName: .ghostDontSendTyping, value: SGSimpleSettings.shared.ghostDontSendTyping, text: i18n("Settings.Ayugram.GhostDontSendTyping", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .ghost, settingName: .ghostDontSendOnline, value: SGSimpleSettings.shared.ghostDontSendOnline, text: i18n("Settings.Ayugram.GhostDontSendOnline", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .ghost, settingName: .ghostDontSendRead, value: SGSimpleSettings.shared.ghostDontSendRead, text: i18n("Settings.Ayugram.GhostDontSendRead", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .ghost, settingName: .ghostDontSendVoiceListen, value: SGSimpleSettings.shared.ghostDontSendVoiceListen, text: i18n("Settings.Ayugram.GhostDontSendVoiceListen", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .ghost, settingName: .ghostDontReadStories, value: SGSimpleSettings.shared.ghostDontReadStories, text: i18n("Settings.Ayugram.GhostDontReadStories", lang), enabled: true))

    // MARK: - Messages & Media
    let retentionDays = SGSimpleSettings.shared.ayugramRetentionDays
    let retentionText: String
    switch retentionDays {
    case 7:
        retentionText = isRu ? "7 дней" : "7 days"
    case 30:
        retentionText = isRu ? "30 дней" : "30 days"
    case 90:
        retentionText = isRu ? "90 дней" : "90 days"
    default:
        retentionText = isRu ? "Без ограничений" : "Unlimited"
    }

    entries.append(.header(id: id.count, section: .media, text: i18n("Settings.Ayugram.MediaHeader", lang), badge: nil))
    entries.append(.toggle(id: id.count, section: .media, settingName: .keepViewOnceMedia, value: SGSimpleSettings.shared.keepViewOnceMedia, text: i18n("Settings.Ayugram.KeepViewOnceMedia", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .media, settingName: .antiRecall, value: SGSimpleSettings.shared.antiRecall, text: i18n("Settings.Ayugram.AntiRecall", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .media, settingName: .keepEditHistory, value: SGSimpleSettings.shared.keepEditHistory, text: i18n("Settings.Ayugram.KeepEditHistory", lang), enabled: true))
    entries.append(.oneFromManySelector(id: id.count, section: .media, settingName: .ayugramRetention, text: i18n("Settings.Ayugram.Retention", lang), value: retentionText, enabled: true))
    entries.append(.disclosure(id: id.count, section: .media, link: .deletedMediaVault, text: i18n("Settings.Ayugram.DeletedMediaVault", lang)))

    // MARK: - Streamer Mode
    entries.append(.header(id: id.count, section: .streamer, text: i18n("Settings.Ayugram.StreamerHeader", lang), badge: nil))
    entries.append(.toggle(id: id.count, section: .streamer, settingName: .streamerMode, value: SGSimpleSettings.shared.streamerMode, text: i18n("Settings.Ayugram.StreamerMode", lang), enabled: true))
    entries.append(.disclosure(id: id.count, section: .streamer, link: .streamerSettings, text: i18n("Settings.Ayugram.StreamerSettings", lang)))
    entries.append(.notice(id: id.count, section: .streamer, text: i18n("Settings.Ayugram.StreamerMode.Notice", lang)))

    // MARK: - Privacy & Protection
    entries.append(.header(id: id.count, section: .privacy, text: i18n("Settings.Ayugram.PrivacyHeader", lang), badge: nil))
    entries.append(.toggle(id: id.count, section: .privacy, settingName: .hideAds, value: SGSimpleSettings.shared.hideAds, text: i18n("Settings.Ayugram.HideAds", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .privacy, settingName: .hideChannelAds, value: SGSimpleSettings.shared.hideChannelAds, text: isRu ? "Скрывать рекламу в каналах" : "Hide Channel Ads", enabled: true))
    entries.append(.notice(id: id.count, section: .privacy, text: isRu ? "Скрывает рекламу, подборки каналов и казино в каналах плашкой в стиле даты. По тапу на «Показать» сообщение раскрывается без автозагрузки медиа." : "Hides ads, channel collections, and casino posts in channels using a date-style badge. Tapping 'Show' reveals the post without auto-loading media."))
    entries.append(.toggle(id: id.count, section: .privacy, settingName: .blockScreenshotNotifications, value: SGSimpleSettings.shared.blockScreenshotNotifications, text: isRu ? "Блокировать уведомления о скриншотах" : "Block Screenshot Notifications", enabled: true))
    entries.append(.notice(id: id.count, section: .privacy, text: isRu ? "Собеседник не получит уведомление о том, что вы сделали снимок экрана в секретном чате или при просмотре самоуничтожающихся фото и видео." : "Prevents sending screenshot notifications in secret chats and view-once media."))
    entries.append(.toggle(id: id.count, section: .privacy, settingName: .bypassCopyProtection, value: SGSimpleSettings.shared.bypassCopyProtection, text: i18n("Settings.Ayugram.BypassCopyProtection", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .privacy, text: i18n("Settings.Ayugram.BypassCopyProtection.Notice", lang)))
    entries.append(.toggle(id: id.count, section: .privacy, settingName: .disableTelemetry, value: SGSimpleSettings.shared.disableTelemetry, text: i18n("Settings.Ayugram.DisableTelemetry", lang), enabled: true))

    // MARK: - Anti-Deanon & IP Protection
    entries.append(.header(id: id.count, section: .antiDeanon, text: i18n("Settings.AntiDeanon.Header", lang), badge: nil))
    entries.append(.toggle(id: id.count, section: .antiDeanon, settingName: .warnOnIpLoggers, value: SGSimpleSettings.shared.warnOnIpLoggers, text: i18n("Settings.AntiDeanon.WarnIpLoggers", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .antiDeanon, text: i18n("Settings.AntiDeanon.WarnIpLoggers.Notice", lang)))
    entries.append(.toggle(id: id.count, section: .antiDeanon, settingName: .cleanUrlTrackers, value: SGSimpleSettings.shared.cleanUrlTrackers, text: i18n("Settings.AntiDeanon.CleanTrackers", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .antiDeanon, text: i18n("Settings.AntiDeanon.CleanTrackers.Notice", lang)))
    entries.append(.toggle(id: id.count, section: .antiDeanon, settingName: .warnOnAllExternalLinks, value: SGSimpleSettings.shared.warnOnAllExternalLinks, text: i18n("Settings.AntiDeanon.WarnAllExternal", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .antiDeanon, text: i18n("Settings.AntiDeanon.WarnAllExternal.Notice", lang)))

    // MARK: - TG WS Proxy
    entries.append(.header(id: id.count, section: .wsProxy, text: i18n("Settings.WsProxy.Header", lang), badge: nil))
    entries.append(.toggle(id: id.count, section: .wsProxy, settingName: .tgWsProxyEnabled, value: SGSimpleSettings.shared.tgWsProxyEnabled, text: i18n("Settings.WsProxy.Enabled", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .wsProxy, settingName: .tgWsProxyFakeTLS, value: SGSimpleSettings.shared.tgWsProxyFakeTLS, text: i18n("Settings.WsProxy.FakeTLS", lang), enabled: true))
    let workerText = SGSimpleSettings.shared.tgWsProxyCustomWorker.isEmpty ? (isRu ? "Авто" : "Auto") : SGSimpleSettings.shared.tgWsProxyCustomWorker
    entries.append(.disclosure(id: id.count, section: .wsProxy, link: .tgWsProxyWorkerDomain, text: i18n("Settings.WsProxy.WorkerDomain", lang) + ": " + workerText))
    entries.append(.toggle(id: id.count, section: .wsProxy, settingName: .hideProxyButton, value: SGSimpleSettings.shared.hideProxyButton, text: i18n("Settings.WsProxy.HideButton", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .wsProxy, text: i18n("Settings.WsProxy.Enabled.Notice", lang)))

    // MARK: - Animated Video Wallpapers
    entries.append(.header(id: id.count, section: .animatedWallpapers, text: isRu ? "Анимированные обои DoxGram" : "DoxGram Animated Wallpapers", badge: nil))
    let hasGlobalWall = SGDoxAnimatedWallpaperManager.shared.hasGlobalWallpaper
    let globalStatus = hasGlobalWall ? (isRu ? "Включены" : "Enabled") : (isRu ? "Выключены" : "Disabled")
    entries.append(.disclosure(id: id.count, section: .animatedWallpapers, link: .globalAnimatedWallpaper, text: "\(isRu ? "Обои для всех чатов" : "Wallpaper for all chats") (\(globalStatus))"))
    entries.append(.oneFromManySelector(id: id.count, section: .animatedWallpapers, settingName: .animatedWallpaperQuality, text: isRu ? "Качество загрузки видео" : "Video Download Quality", value: SGSimpleSettings.shared.animatedWallpaperQuality, enabled: true))
    entries.append(.disclosure(id: id.count, section: .animatedWallpapers, link: .clearAnimatedWallpaperCache, text: isRu ? "Очистить кэш видео-обоев" : "Clear Video Wallpapers Cache"))
    entries.append(.notice(id: id.count, section: .animatedWallpapers, text: isRu ? "Установите анимированные видео-обои (MP4, TikTok или из галереи/файлов) для всех чатов сразу либо индивидуально внутри конкретного чата. При включении опции «Установить для обоих» они автоматически применятся у собеседника с DoxGram." : "Set animated video wallpapers (MP4, TikTok, or from gallery/files) globally for all chats or individually inside any chat. If 'Set for Both' is selected, it will also apply for peers using DoxGram."))

    // MARK: - Debug & Logs
    entries.append(.header(id: id.count, section: .debug, text: i18n("Settings.Ayugram.DebugHeader", lang), badge: nil))
    entries.append(.toggle(id: id.count, section: .debug, settingName: .ayugramDebugger, value: SGSimpleSettings.shared.ayugramDebugger, text: i18n("Settings.Ayugram.Debugger", lang), enabled: true))
    let exportLogsTitle: String
    if let size = SGAyugramLogger.getLogFileSize() {
        exportLogsTitle = "\(i18n("Settings.Ayugram.ExportLogs", lang)) (\(size))"
    } else {
        exportLogsTitle = i18n("Settings.Ayugram.ExportLogs", lang)
    }
    entries.append(.disclosure(id: id.count, section: .debug, link: .ayugramExportLogs, text: exportLogsTitle))
    entries.append(.disclosure(id: id.count, section: .debug, link: .ayugramClearLogs, text: i18n("Settings.Ayugram.ClearLogs", lang)))

    return entries
}

private final class SGDoxPresentationContext: @unchecked Sendable {
    var present: ((ViewController, ViewControllerPresentationArguments?) -> Void)?
    var push: ((ViewController) -> Void)?
}

public func doxSettingsController(context: AccountContext) -> ViewController {
    let presentationContext = SGDoxPresentationContext()
    let presentControllerImpl: (ViewController, ViewControllerPresentationArguments?) -> Void = { c, a in
        presentationContext.present?(c, a)
    }
    let pushControllerImpl: (ViewController) -> Void = { c in
        presentationContext.push?(c)
    }

    let simplePromise = ValuePromise(true, ignoreRepeated: false)

    let arguments = SGItemListArguments<SGDoxBoolSetting, AnyHashable, SGDoxOneFromManySetting, SGDoxDisclosureLink, AnyHashable>(context: context, setBoolValue: { toggleName, value in
        switch toggleName {
        case .inputToolbar:
            SGSimpleSettings.shared.inputToolbar = value
        case .ghostDontSendTyping:
            SGSimpleSettings.shared.ghostDontSendTyping = value
        case .ghostDontSendOnline:
            SGSimpleSettings.shared.ghostDontSendOnline = value
        case .ghostDontSendRead:
            SGSimpleSettings.shared.ghostDontSendRead = value
        case .ghostDontSendVoiceListen:
            SGSimpleSettings.shared.ghostDontSendVoiceListen = value
        case .ghostDontReadStories:
            SGSimpleSettings.shared.ghostDontReadStories = value
        case .keepViewOnceMedia:
            SGSimpleSettings.shared.keepViewOnceMedia = value
        case .antiRecall:
            SGSimpleSettings.shared.antiRecall = value
        case .keepEditHistory:
            SGSimpleSettings.shared.keepEditHistory = value
        case .streamerMode:
            SGSimpleSettings.shared.streamerMode = value
        case .hideAds:
            SGSimpleSettings.shared.hideAds = value
        case .hideChannelAds:
            SGSimpleSettings.shared.hideChannelAds = value
        case .blockScreenshotNotifications:
            SGSimpleSettings.shared.blockScreenshotNotifications = value
            simplePromise.set(true)
        case .bypassCopyProtection:
            SGSimpleSettings.shared.bypassCopyProtection = value
        case .disableTelemetry:
            SGSimpleSettings.shared.disableTelemetry = value
        case .warnOnIpLoggers:
            SGSimpleSettings.shared.warnOnIpLoggers = value
        case .cleanUrlTrackers:
            SGSimpleSettings.shared.cleanUrlTrackers = value
        case .warnOnAllExternalLinks:
            SGSimpleSettings.shared.warnOnAllExternalLinks = value
        case .tgWsProxyEnabled:
            SGSimpleSettings.shared.tgWsProxyEnabled = value
            if value {
                SGTGWsProxy.shared.start()
            } else {
                SGTGWsProxy.shared.stop()
            }
            simplePromise.set(true)
            let _ = updateProxySettingsInteractively(accountManager: context.sharedContext.accountManager, { $0 }).start()
        case .tgWsProxyFakeTLS:
            SGSimpleSettings.shared.tgWsProxyFakeTLS = value
            simplePromise.set(true)
        case .hideProxyButton:
            SGSimpleSettings.shared.hideProxyButton = value
            simplePromise.set(true)
        case .ayugramDebugger:
            SGSimpleSettings.shared.ayugramDebugger = value
        case .discordRpcEnabled:
            SGSimpleSettings.shared.discordRpcEnabled = value
            simplePromise.set(true)
            if value {
                DiscordRPCService.shared.connect()
            } else {
                DiscordRPCService.shared.disconnect()
            }
        }
    }, setOneFromManyValue: { setting in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let lang = presentationData.strings.baseLanguageCode
        let isRu = lang.hasPrefix("ru")
        let actionSheet = ActionSheetController(presentationData: presentationData)
        var items: [ActionSheetItem] = []

        switch setting {
        case .pinnedMessageNotifications:
            let setAction: (String) -> Void = { value in
                SGSimpleSettings.shared.pinnedMessageNotifications = value
                SGSimpleSettings.shared.synchronizeShared()
                simplePromise.set(true)
            }
            for value in SGSimpleSettings.PinnedMessageNotificationsSettings.allCases {
                items.append(ActionSheetButtonItem(title: "Notifications.PinnedMessages.value.\(value.rawValue)".i18n(lang), color: .accent, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    setAction(value.rawValue)
                }))
            }
        case .mentionsAndRepliesNotifications:
            let setAction: (String) -> Void = { value in
                SGSimpleSettings.shared.mentionsAndRepliesNotifications = value
                SGSimpleSettings.shared.synchronizeShared()
                simplePromise.set(true)
            }
            for value in SGSimpleSettings.MentionsAndRepliesNotificationsSettings.allCases {
                items.append(ActionSheetButtonItem(title: "Notifications.MentionsAndReplies.value.\(value.rawValue)".i18n(lang), color: .accent, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    setAction(value.rawValue)
                }))
            }
        case .ayugramRetention:
            let setAction: (Int) -> Void = { value in
                SGSimpleSettings.shared.ayugramRetentionDays = value
                SGAyugramStorage.shared.cleanupExpired(retentionDays: value)
                simplePromise.set(true)
            }
            let options: [(Int, String)] = [
                (7, isRu ? "7 дней" : "7 days"),
                (30, isRu ? "30 дней" : "30 days"),
                (90, isRu ? "90 дней" : "90 days"),
                (0, isRu ? "Без ограничений" : "Unlimited")
            ]
            for (days, title) in options {
                items.append(ActionSheetButtonItem(title: title, color: .accent, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    setAction(days)
                }))
            }
        case .animatedWallpaperQuality:
            let setAction: (String) -> Void = { value in
                SGSimpleSettings.shared.animatedWallpaperQuality = value
                simplePromise.set(true)
            }
            for quality in SGDoxAnimatedWallpaperManager.Quality.allCases {
                items.append(ActionSheetButtonItem(title: quality.displayName, color: .accent, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    setAction(quality.rawValue)
                }))
            }
        }

        actionSheet.setItemGroups([ActionSheetItemGroup(items: items), ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
            })
        ])])
        presentControllerImpl?(actionSheet, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
    }, openDisclosureLink: { link in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let isRu = presentationData.strings.baseLanguageCode.hasPrefix("ru")

        switch link {
        case .sessionBackupManager:
            pushControllerImpl?(sgSessionBackupManagerController(context: context, presentationData: presentationData))
        case .messageFilter:
            pushControllerImpl?(sgMessageFilterController(presentationData: presentationData))
        case .appIcons:
            pushControllerImpl?(themeSettingsController(context: context, focusOnItemTag: .icon))
        case .appBages:
            if #available(iOS 14.0, *) {
                pushControllerImpl?(sgAppBadgeSettingsController(context: context, presentationData: presentationData))
            } else {
                presentControllerImpl?(context.sharedContext.makeSGUpdateIOSController(), nil)
            }
        case .doxMusic:
            pushControllerImpl?(SGDoxMusicHubController(context: context))
        case .discordRpcToken:
            let alert = UIAlertController(
                title: "Discord Token",
                message: isRu ? "Введите User Token аккаунта Discord для трансляции музыки в статус (RPC):" : "Enter your Discord User Token to broadcast music to your status (RPC):",
                preferredStyle: .alert
            )
            alert.addTextField { textField in
                textField.text = SGSimpleSettings.shared.discordRpcToken
                textField.placeholder = "User Token..."
                textField.clearButtonMode = .whileEditing
                textField.isSecureTextEntry = true
                textField.autocapitalizationType = .none
                textField.autocorrectionType = .no
            }
            alert.addAction(UIAlertAction(title: presentationData.strings.Common_Cancel, style: .cancel, handler: nil))
            alert.addAction(UIAlertAction(title: presentationData.strings.Common_Done, style: .default, handler: { [weak alert] _ in
                let newToken = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                SGSimpleSettings.shared.discordRpcToken = newToken
                simplePromise.set(true)
                if !newToken.isEmpty {
                    let hud = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: nil))
                    presentControllerImpl(hud, nil)
                    DiscordRPCService.shared.validateToken(newToken) { success, usernameOrError in
                        hud.dismiss()
                        if success {
                            DiscordRPCService.shared.connect()
                            let overlay = UndoOverlayController(presentationData: presentationData, content: .actionSucceeded(title: nil, text: isRu ? "Discord подключен: \(usernameOrError ?? "")" : "Discord connected: \(usernameOrError ?? "")", cancel: nil, destructive: false), elevatedLayout: false, action: { _ in return false })
                            presentControllerImpl(overlay, nil)
                        } else {
                            let errOverlay = UndoOverlayController(presentationData: presentationData, content: .info(title: isRu ? "Ошибка" : "Error", text: usernameOrError ?? "Неверный токен", timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false })
                            presentControllerImpl(errOverlay, nil)
                        }
                    }
                } else {
                    DiscordRPCService.shared.disconnect()
                }
            }))
            context.sharedContext.applicationBindings.presentNativeController(alert)
        case .deletedMediaVault:
            pushControllerImpl?(sgDeletedMediaController(context: context, peerId: nil))
        case .streamerSettings:
            pushControllerImpl?(sgStreamerSettingsController(context: context))
        case .tgWsProxyWorkerDomain:
            let alert = UIAlertController(
                title: "Cloudflare Worker",
                message: isRu ? "Введите домен своего воркера (например: worker.example.com). Оставьте пустым для авто-выбора встроенных доменов." : "Enter your worker domain (e.g. worker.example.com). Leave empty for auto-selection.",
                preferredStyle: .alert
            )
            alert.addTextField { textField in
                textField.text = SGSimpleSettings.shared.tgWsProxyCustomWorker
                textField.placeholder = "worker.example.com"
                textField.clearButtonMode = .whileEditing
                textField.autocapitalizationType = .none
                textField.autocorrectionType = .no
            }
            alert.addAction(UIAlertAction(title: presentationData.strings.Common_Cancel, style: .cancel, handler: nil))
            alert.addAction(UIAlertAction(title: presentationData.strings.Common_Done, style: .default, handler: { [weak alert] _ in
                let newDomain = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                SGSimpleSettings.shared.tgWsProxyCustomWorker = newDomain
                simplePromise.set(true)
                if SGSimpleSettings.shared.tgWsProxyEnabled {
                    SGTGWsProxy.shared.stop()
                    SGTGWsProxy.shared.start()
                }
            }))
            context.sharedContext.applicationBindings.presentNativeController(alert)
        case .globalAnimatedWallpaper:
            let actionSheet = ActionSheetController(presentationData: presentationData)
            var items: [ActionSheetItem] = []

            items.append(ActionSheetButtonItem(title: isRu ? "Выбрать из Фото (Галереи)" : "Pick from Photo Library", color: .accent, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                SGDoxVideoPickerHelper.shared.pickVideoFromGallery(presentation: { picker in
                    context.sharedContext.applicationBindings.presentNativeController(picker)
                }) { selectedUrl in
                    guard let selectedUrl = selectedUrl else { return }
                    SGDoxAnimatedWallpaperManager.shared.setLocalWallpaper(from: selectedUrl, for: SGDoxAnimatedWallpaperManager.globalWallpaperPeerId) { success, _ in
                        if success {
                            simplePromise.set(true)
                            let overlay = UndoOverlayController(presentationData: presentationData, content: .actionSucceeded(title: nil, text: isRu ? "Обои для всех чатов установлены" : "Global wallpaper set", cancel: nil, destructive: false), elevatedLayout: false, action: { _ in return false })
                            presentControllerImpl?(overlay, nil)
                        }
                    }
                }
            }))

            items.append(ActionSheetButtonItem(title: isRu ? "Выбрать из Файлов (iCloud)" : "Pick from Files", color: .accent, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                SGDoxVideoPickerHelper.shared.pickVideoFromFiles(presentation: { picker in
                    context.sharedContext.applicationBindings.presentNativeController(picker)
                }) { selectedUrl in
                    guard let selectedUrl = selectedUrl else { return }
                    SGDoxAnimatedWallpaperManager.shared.setLocalWallpaper(from: selectedUrl, for: SGDoxAnimatedWallpaperManager.globalWallpaperPeerId) { success, _ in
                        if success {
                            simplePromise.set(true)
                            let overlay = UndoOverlayController(presentationData: presentationData, content: .actionSucceeded(title: nil, text: isRu ? "Обои для всех чатов установлены" : "Global wallpaper set", cancel: nil, destructive: false), elevatedLayout: false, action: { _ in return false })
                            presentControllerImpl?(overlay, nil)
                        }
                    }
                }
            }))

            items.append(ActionSheetButtonItem(title: isRu ? "Ввести ссылку (URL / TikTok)" : "Enter URL or TikTok Link", color: .accent, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                let alert = UIAlertController(
                    title: isRu ? "Обои для всех чатов" : "Global Animated Wallpaper",
                    message: isRu ? "Вставьте прямую ссылку на видео (MP4) или ссылку на видео из TikTok (tiktok.com, vt.tiktok.com):" : "Paste a direct MP4 URL or TikTok video link (tiktok.com, vt.tiktok.com):",
                    preferredStyle: .alert
                )
                alert.addTextField { textField in
                    textField.placeholder = "https://... / tiktok.com/..."
                    textField.text = SGDoxAnimatedWallpaperManager.shared.globalWallpaperUrl
                    textField.clearButtonMode = .whileEditing
                    textField.keyboardType = .URL
                    textField.autocapitalizationType = .none
                    textField.autocorrectionType = .no
                }
                alert.addAction(UIAlertAction(title: presentationData.strings.Common_Cancel, style: .cancel, handler: nil))
                alert.addAction(UIAlertAction(title: presentationData.strings.Common_Done, style: .default, handler: { [weak alert] _ in
                    guard let text = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                        return
                    }
                    let quality = SGDoxAnimatedWallpaperManager.shared.currentQuality
                    let hud = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: nil))
                    presentControllerImpl?(hud, nil)

                    SGDoxAnimatedWallpaperManager.shared.setWallpaper(for: SGDoxAnimatedWallpaperManager.globalWallpaperPeerId, urlString: text, quality: quality) { success, error in
                        hud.dismiss()
                        if success {
                            simplePromise.set(true)
                            let overlay = UndoOverlayController(presentationData: presentationData, content: .actionSucceeded(title: nil, text: isRu ? "Обои для всех чатов установлены" : "Global wallpaper set", cancel: nil, destructive: false), elevatedLayout: false, action: { _ in return false })
                            presentControllerImpl?(overlay, nil)
                        } else {
                            let errOverlay = UndoOverlayController(presentationData: presentationData, content: .info(title: isRu ? "Ошибка" : "Error", text: error ?? (isRu ? "Не удалось скачать видео" : "Failed to download video"), timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false })
                            presentControllerImpl?(errOverlay, nil)
                        }
                    }
                }))
                context.sharedContext.applicationBindings.presentNativeController(alert)
            }))

            if SGDoxAnimatedWallpaperManager.shared.hasGlobalWallpaper {
                items.append(ActionSheetButtonItem(title: isRu ? "Удалить обои для всех чатов" : "Remove Global Wallpaper", color: .destructive, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    SGDoxAnimatedWallpaperManager.shared.removeGlobalWallpaper()
                    simplePromise.set(true)
                    let overlay = UndoOverlayController(presentationData: presentationData, content: .actionSucceeded(title: nil, text: isRu ? "Обои для всех чатов удалены" : "Global wallpaper removed", cancel: nil, destructive: false), elevatedLayout: false, action: { _ in return false })
                    presentControllerImpl?(overlay, nil)
                }))
            }

            actionSheet.setItemGroups([ActionSheetItemGroup(items: items), ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                })
            ])])
            presentControllerImpl?(actionSheet, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
        case .clearAnimatedWallpaperCache:
            SGDoxAnimatedWallpaperManager.shared.clearCache()
            let overlay = UndoOverlayController(presentationData: presentationData, content: .actionSucceeded(title: nil, text: isRu ? "Кэш видео-обоев очищен" : "Video wallpaper cache cleared", cancel: nil, destructive: false), elevatedLayout: false, action: { _ in return false })
            presentControllerImpl?(overlay, nil)
        case .ayugramExportLogs:
            if let url = SGAyugramLogger.getLogFileUrl(), FileManager.default.fileExists(atPath: url.path) {
                let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                if let window = context.sharedContext.mainWindow?.viewController?.view {
                    activityVC.popoverPresentationController?.sourceView = window
                    activityVC.popoverPresentationController?.sourceRect = CGRect(origin: CGPoint(x: window.bounds.width / 2.0, y: window.bounds.height / 2.0), size: CGSize(width: 1.0, height: 1.0))
                }
                context.sharedContext.applicationBindings.presentNativeController(activityVC)
            } else {
                let overlay = UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: isRu ? "Логи пока пусты" : "Logs are empty", timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false })
                presentControllerImpl?(overlay, nil)
            }
        case .ayugramClearLogs:
            SGAyugramLogger.clearLogs()
            let overlay = UndoOverlayController(presentationData: presentationData, content: .actionSucceeded(title: nil, text: isRu ? "Логи очищены" : "Logs cleared", cancel: nil, destructive: false), elevatedLayout: false, action: { _ in return false })
            presentControllerImpl?(overlay, nil)
        }
    })

    let signal = combineLatest(context.sharedContext.presentationData, simplePromise.get())
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let entries = SGDoxControllerEntries(presentationData: presentationData)
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("DoxGram"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, ensureVisibleItemTag: nil, initialScrollToItem: nil)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentationContext.present = { [weak controller] c, a in
        controller?.present(c, in: .window(.root), with: a)
    }
    presentationContext.push = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }

    return controller
}
