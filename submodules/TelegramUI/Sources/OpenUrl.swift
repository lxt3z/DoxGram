import SGSettingsUI
import SGSimpleSettings
import UndoUI
//
import ContactListUI
import Foundation
import Display
import TelegramCore
import SwiftSignalKit
import MtProtoKit
import TelegramPresentationData
import TelegramUIPreferences
import AccountContext
import UrlEscaping
import PassportUI
import UrlHandling
import OpenInExternalAppUI
import BrowserUI
import OverlayStatusController
import PresentationDataUtils
import UrlWhitelist
import OpenUserGeneratedUrl
import DebugCompanionScreen

public struct ParsedSecureIdUrl {
    public let peerId: EnginePeer.Id
    public let scope: String
    public let publicKey: String
    public let callbackUrl: String
    public let opaquePayload: Data
    public let opaqueNonce: Data
}

public func parseProxyUrl(sharedContext: SharedAccountContext, url: URL) -> ProxyServerSettings? {
    // Checked first: a WEB link is a distinct scheme/path and must never be
    // downgraded into an .mtp entry by the generic proxy parser.
    if let webSettings = parseWebProxySettingsLink(url.absoluteString) {
        return webSettings
    }
    guard let proxy = parseProxyUrl(sharedContext: sharedContext, url: url.absoluteString) else {
        return nil
    }
    if let secret = proxy.secret, let _ = MTProxySecret.parseData(secret) {
        return ProxyServerSettings(host: proxy.host, port: proxy.port, connection: .mtp(secret: secret))
    } else {
        return ProxyServerSettings(host: proxy.host, port: proxy.port, connection: .socks5(username: proxy.username, password: proxy.password))
    }
}

public func isOAuthUrl(_ url: URL) -> Bool {
    guard let query = url.query, let params = QueryParameters(query), ["oauth", "resolve"].contains(url.host) else {
        return false
    }

    let domain = params["domain"]
    let startApp = params["startapp"]
    let token = params["token"]

    var valid = false
    if url.host == "resolve" {
        if domain == "oauth", let _ = startApp {
            valid = true
        }
    } else {
        if let _ = token {
            valid = true
        }
    }

    return valid
}

public func parseSecureIdUrl(_ url: URL) -> ParsedSecureIdUrl? {
    guard let query = url.query, let params = QueryParameters(query), ["passport", "resolve"].contains(url.host) else {
        return nil
    }

    let domain = params["domain"]
    let botId = params["bot_id"].flatMap(Int64.init)
    let scope = params["scope"]
    let publicKey = params["public_key"]
    let callbackUrl = params["callback_url"]
    var opaquePayload = Data()
    var opaqueNonce = Data()
    if let payloadValue = params["payload"], let data = payloadValue.data(using: .utf8) {
        opaquePayload = data
    }
    if let nonceValue = params["nonce"], let data = nonceValue.data(using: .utf8) {
        opaqueNonce = data
    }

    let valid: Bool
    if url.host == "resolve" {
        if domain == "telegrampassport" {
            valid = true
        } else {
            valid = false
        }
    } else {
        valid = true
    }

    if valid {
        if let botId = botId, let scope = scope, let publicKey = publicKey, let callbackUrl = callbackUrl {
            if scope.hasPrefix("{") && scope.hasSuffix("}") {
                opaquePayload = Data()
                if opaqueNonce.isEmpty {
                    return nil
                }
            } else if opaquePayload.isEmpty {
                return nil
            }

            return ParsedSecureIdUrl(peerId: EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(botId)), scope: scope, publicKey: publicKey, callbackUrl: callbackUrl, opaquePayload: opaquePayload, opaqueNonce: opaqueNonce)
        }
    }

    return nil
}

public func parseConfirmationCodeUrl(sharedContext: SharedAccountContext, url: URL) -> Int? {
    if url.pathComponents.count == 3 && url.pathComponents[1].lowercased() == "login" {
        if let code = Int(url.pathComponents[2]) {
            return code
        }
    }
    if url.scheme == "tg" {
        if let host = url.host, let query = url.query, let parsedUrl = parseInternalUrl(sharedContext: sharedContext, context: nil, query: host + "?" + query) {
            switch parsedUrl {
            case let .confirmationCode(code):
                return code
            default:
                break
            }
        }
    }
    return nil
}

func formattedConfirmationCode(_ code: Int) -> String {
    let source = "\(code)"
    let segmentLength = 3
    var result = ""
    for c in source {
        if !result.isEmpty && result.count % segmentLength == 0 {
            result.append("-")
        }
        result.append(c)
    }
    return result
}

private func makeResolvedUrlHandler(
    context: AccountContext,
    presentationData: PresentationData,
    navigationController: NavigationController?,
    dismissInput: @escaping () -> Void
) -> (ResolvedUrl) -> Void {
    return { resolved in
        if case let .externalUrl(value) = resolved {
            context.sharedContext.applicationBindings.openUrl(value)
        } else {
            context.sharedContext.openResolvedUrl(
                resolved,
                context: context,
                urlContext: .generic,
                navigationController: navigationController,
                forceExternal: false,
                forceUpdate: false,
                openPeer: { peer, navigation in
                    switch navigation {
                    case .info:
                        if let infoController = context.sharedContext.makePeerInfoController(context: context, updatedPresentationData: nil, peer: peer, mode: .generic, avatarInitiallyExpanded: false, fromChat: false, requestsContext: nil) {
                            context.sharedContext.applicationBindings.dismissNativeController()
                            navigationController?.pushViewController(infoController)
                        }
                    case let .chat(textInputState, subject, peekData):
                        context.sharedContext.applicationBindings.dismissNativeController()
                        if let navigationController {
                            context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peer), subject: subject, updateTextInputState: !peer.id.isGroupOrChannel ? textInputState : nil, peekData: peekData))
                        }
                    case let .withBotStartPayload(payload):
                        context.sharedContext.applicationBindings.dismissNativeController()
                        if let navigationController {
                            context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peer), botStart: payload))
                        }
                    case let .withAttachBot(attachBotStart):
                        context.sharedContext.applicationBindings.dismissNativeController()
                        if let navigationController {
                            context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peer), attachBotStart: attachBotStart))
                        }
                    case let .withBotApp(botAppStart):
                        context.sharedContext.applicationBindings.dismissNativeController()
                        if let navigationController {
                            context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peer), botAppStart: botAppStart))
                        }
                    default:
                        break
                    }
                },
                sendFile: nil,
                sendSticker: nil,
                sendEmoji: nil,
                requestMessageActionUrlAuth: nil,
                joinVoiceChat: { _, _, _ in },
                present: { c, a in
                    context.sharedContext.applicationBindings.dismissNativeController()
                    c.presentationArguments = a
                    context.sharedContext.applicationBindings.getWindowHost()?.present(c, on: .root, blockInteraction: false, completion: {})
                },
                dismissInput: {
                    dismissInput()
                },
                contentContext: nil,
                progress: nil,
                completion: nil
            )
        }
    }
}

private func makeInternalUrlHandler(
    context: AccountContext,
    resolvedHandler: @escaping (ResolvedUrl) -> Void
) -> (String) -> Void {
    return { url in
        let _ = (context.sharedContext.resolveUrl(context: context, peerId: nil, url: url, skipUrlAuth: true)
        |> deliverOnMainQueue).startStandalone(next: resolvedHandler)
    }
}

private let internetSchemes: [String] = ["http", "https"]
private let telegramMeHosts: [String] = ["t.me", "telegram.me", "telegram.dog"]

private func handleInternetUrl(
    parsedUrl: URL,
    originalUrl: String,
    context: AccountContext,
    presentationData: PresentationData,
    navigationController: NavigationController?,
    handleInternalUrl: @escaping (String) -> Void
) {
    let urlScheme = (parsedUrl.scheme ?? "").lowercased()
    var isInternetUrl = false
    if internetSchemes.contains(urlScheme) {
        isInternetUrl = true
    }
    if urlScheme == "tonsite" {
        isInternetUrl = true
    }

    if isInternetUrl {
        if let host = parsedUrl.host, telegramMeHosts.contains(host) {
            handleInternalUrl(parsedUrl.absoluteString)
        } else {
            let settings = combineLatest(
                context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.webBrowserSettings]),
                context.engine.data.subscribe(TelegramEngine.EngineData.Item.Configuration.ApplicationSpecificPreference(key: PreferencesKeys.webBrowserSettings))
            )
            |> take(1)
            |> map { sharedData, accountSettingsEntry -> (WebBrowserSettings, AccountWebBrowserSettings) in
                let localSettings = sharedData.entries[ApplicationSpecificSharedDataKeys.webBrowserSettings]?.get(WebBrowserSettings.self) ?? WebBrowserSettings.defaultSettings
                let accountSettings = accountSettingsEntry?.get(AccountWebBrowserSettings.self) ?? AccountWebBrowserSettings.defaultSettings
                return (localSettings, accountSettings)
            }

            let _ = (settings
            |> deliverOnMainQueue).startStandalone(next: { settings in
                let localSettings = settings.0
                let accountSettings = settings.1

                var isTonSite = false
                if let host = parsedUrl.host, host.lowercased().hasSuffix(".ton") {
                    isTonSite = true
                } else if let scheme = parsedUrl.scheme, scheme.lowercased().hasPrefix("tonsite") {
                    isTonSite = true
                }

                var isExceptedDomain = false
                let host = ".\((parsedUrl.host ?? "").lowercased())"
                let exceptions = accountSettings.openExternalBrowser ? accountSettings.inAppExceptions : accountSettings.externalExceptions
                for exception in exceptions {
                    if host.hasSuffix(".\(exception.domain.lowercased())") {
                        isExceptedDomain = true
                        break
                    }
                }

                let shouldOpenInApp: Bool
                if isTonSite {
                    shouldOpenInApp = true
                } else if accountSettings.openExternalBrowser {
                    shouldOpenInApp = isExceptedDomain
                } else {
                    shouldOpenInApp = !isExceptedDomain
                }

                if shouldOpenInApp {
                    let controller = BrowserScreen(context: context, subject: .webPage(url: parsedUrl.absoluteString))
                    navigationController?.pushViewController(controller)
                } else {
                    // MARK: Swiftgram
                    if localSettings.defaultWebBrowser == "inApp" {
                        sgOpenUrlWithSafariController(parsedUrl: parsedUrl, originalUrl: originalUrl, context: context, presentationData: presentationData, navigationController: navigationController)
                    } else {
                        let openInOptions = availableOpenInOptions(context: context, item: .url(url: originalUrl))
                        var defaultWebBrowser = localSettings.defaultWebBrowser
                        if defaultWebBrowser == nil || defaultWebBrowser == "inAppSafari" {
                            defaultWebBrowser = "safari"
                        }
                        if let option = openInOptions.first(where: { $0.identifier == defaultWebBrowser }) {
                            if case let .openUrl(openInUrl) = option.action() {
                                context.sharedContext.applicationBindings.openUrl(openInUrl)
                            } else {
                                context.sharedContext.applicationBindings.openUrl(originalUrl)
                            }
                        } else {
                            context.sharedContext.applicationBindings.openUrl(originalUrl)
                        }
                    }
                    //
                }
            })
        }
    } else {
        context.sharedContext.applicationBindings.openUrl(originalUrl)
    }
}

private struct QueryParameters {
    private let map: [String: [String?]]
    let items: [URLQueryItem]

    init?(_ query: String) {
        guard let components = URLComponents(string: "/?" + query) else {
            return nil
        }
        let queryItems = components.queryItems ?? []
        self.items = queryItems

        var map: [String: [String?]] = [:]
        for item in queryItems {
            map[item.name, default: []].append(item.value)
        }
        self.map = map
    }

    subscript(_ name: String) -> String? {
        return self.map[name]?.first ?? nil
    }
}

private func appendQueryItems(to base: String, items: [URLQueryItem]) -> String {
    guard !items.isEmpty else {
        return base
    }
    var components = URLComponents()
    components.queryItems = items
    guard let query = components.percentEncodedQuery, !query.isEmpty else {
        return base
    }
    let separator = base.contains("?") ? "&" : "?"
    return base + separator + query
}

private func makeTelegramUrl(_ path: String, queryItems: [URLQueryItem] = []) -> String {
    return appendQueryItems(to: "https://t.me\(path)", items: queryItems)
}

func openExternalUrlImpl(context: AccountContext, urlContext: OpenURLContext, url: String, forceExternal: Bool, presentationData: PresentationData, navigationController: NavigationController?, dismissInput: @escaping () -> Void, skipSecurityCheck: Bool = false) {
    // A login part hides the host a link opens (see `externalUrlWithLoginPart`). Every external link leaves through
    // here, whoever opens it, so here it is confirmed.
    if forceExternal || url.lowercased().hasPrefix("tel:") || url.lowercased().hasPrefix("calshow:") {
        if url.lowercased().hasPrefix("tel:+888") {
            context.sharedContext.presentGlobalController(textAlertController(context: context, title: nil, text: presentationData.strings.Conversation_CantPhoneCallAnonymousNumberError, actions: [
                TextAlertAction(type: .genericAction, title: presentationData.strings.Common_OK, action: {
                }),
            ], parseMarkdown: true), nil)
            return
        }
        context.sharedContext.applicationBindings.openUrl(url)
        return
    }

    guard let canonicalUrl = canonicalExternalUrl(from: url) else {
        return
    }
    if canonicalUrl.scheme?.lowercased() == "tg", canonicalUrl.host?.lowercased() == "companion" {
        dismissInput()
        let controller = DebugCompanionScreen(context: context, standalone: navigationController == nil)
        if let navigationController {
            navigationController.pushViewController(controller)
        } else {
            context.sharedContext.presentGlobalController(controller, nil)
        }
        return
    }
    var noPaidMessagesToken: String?
                    for queryItem in params.items {
                        if let value = queryItem.value {
                            switch queryItem.name {
                            case "free":
                                noPaidMessagesToken = value
                            case "phone":
                                phone = value
                            case "domain":
                                domain = value
                            case "start":
                                start = value
                            case "startgroup":
                                startGroup = value
                            case "admin":
                                admin = value
                            case "game":
                                game = value
                            case "post":
                                post = value
                            case "voicechat", "videochat", "livestream":
                                voiceChat = value
                            case "attach":
                                attach = value
                            case "startattach":
                                startAttach = value
                            case "choose":
                                choose = value
                            case "thread":
                                threadId = Int64(value)
                            case "appname":
                                appName = value
                            case "startapp":
                                startApp = value
                            case "text":
                                text = value
                            case "ref":
                                referrer = value
                            case "album":
                                albumId = Int64(value)
                            case "collection":
                                collectionId = Int64(value)
                            default:
                                break
                            }
                        } else {
                            switch queryItem.name {
                            case "voicechat", "videochat", "livestream":
                                voiceChat = ""
                            case "startattach":
                                startAttach = ""
                            case "startgroup":
                                startGroup = ""
                            case "startchannel":
                                startChannel = ""
                            case "profile":
                                profile = true
                            case "direct":
                                direct = true
                            case "startapp":
                                startApp = ""
                            default:
                                break
                            }
                        }
                    }

                    if let phone = phone {
                        var queryItems: [URLQueryItem] = []
                        if let text {
                            queryItems.append(URLQueryItem(name: "text", value: text))
                        }
                        if let referrer {
                            queryItems.append(URLQueryItem(name: "ref", value: referrer))
                        }
                        if profile {
                            queryItems.append(URLQueryItem(name: "profile", value: nil))
                        }
                        if direct {
                            queryItems.append(URLQueryItem(name: "direct", value: nil))
                        }
                        if let noPaidMessagesToken {
                            queryItems.append(URLQueryItem(name: "free", value: noPaidMessagesToken))
                        }
                        convertedUrl = makeTelegramUrl("/+\(phone)", queryItems: queryItems)
                    } else if let domain = domain {
                        var path = "/\(domain)"
                        if let appName {
                            path += "/\(appName)"
                        }
                        if let threadId {
                            path += "/\(threadId)"
                            if let post, let postValue = Int(post) {
                                path += "/\(postValue)"
                            }
                        } else if let post, let postValue = Int(post) {
                            path += "/\(postValue)"
                        }
                        if let albumId {
                            path += "/a/\(albumId)"
                        } else if let collectionId {
                            path += "/c/\(collectionId)"
                        }

                        var queryItems: [URLQueryItem] = []
                        if let startApp {
                            queryItems.append(URLQueryItem(name: "startapp", value: startApp.isEmpty ? "" : startApp))
                        }
                        if let start {
                            queryItems.append(URLQueryItem(name: "start", value: start))
                        } else if let startGroup {
                            queryItems.append(URLQueryItem(name: "startgroup", value: startGroup.isEmpty ? nil : startGroup))
                            if let admin {
                                queryItems.append(URLQueryItem(name: "admin", value: admin))
                            }
                        } else if let startChannel {
                            queryItems.append(URLQueryItem(name: "startchannel", value: startChannel.isEmpty ? nil : startChannel))
                            if let admin = admin {
                                queryItems.append(URLQueryItem(name: "admin", value: admin))
                            }
                        } else if let game {
                            queryItems.append(URLQueryItem(name: "game", value: game))
                        } else if let voiceChat {
                            queryItems.append(URLQueryItem(name: "voicechat", value: voiceChat.isEmpty ? "" : voiceChat))
                        } else if let attach {
                            queryItems.append(URLQueryItem(name: "attach", value: attach))
                        }

                        if let startAttach {
                            queryItems.append(URLQueryItem(name: "startattach", value: startAttach.isEmpty ? nil : startAttach))
                            if let choose {
                                queryItems.append(URLQueryItem(name: "choose", value: choose))
                            }
                        }
                        if let text {
                            queryItems.append(URLQueryItem(name: "text", value: text))
                        }
                        if let referrer {
                            queryItems.append(URLQueryItem(name: "ref", value: referrer))
                        }
                        if profile {
                            queryItems.append(URLQueryItem(name: "profile", value: nil))
                        }
                        if direct {
                            queryItems.append(URLQueryItem(name: "direct", value: nil))
                        }
                        if let noPaidMessagesToken {
                            queryItems.append(URLQueryItem(name: "free", value: noPaidMessagesToken))
                        }
                        
                        convertedUrl = makeTelegramUrl(path, queryItems: queryItems)
                    }
                }
            } else {
                switch host {
                case "stars":
                    handleResolvedUrl(.stars)
                case "sg":
                    if let path = parsedUrl.pathComponents.last {
                        switch path {
                            case "debug":
                                if let debugController = context.sharedContext.makeDebugSettingsController(context: context) {
                                    navigationController?.pushViewController(debugController)
                                    return
                                }
                            case "settings":
                                navigationController?.pushViewController(sgSettingsController(context: context))
                                return
                            case "ios_settings":
                                context.sharedContext.applicationBindings.openSettings()
                                return
                            case "contacts":
                                if let lastViewController = navigationController?.viewControllers.last as? ViewController {
                                    lastViewController.present(ContactsController(context: context), in: .window(.root), with: ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
                                }
                                return
                            case "pro", "premium", "buy":
                                navigationController?.pushViewController(context.sharedContext.makeSGProController(context: context))
                            case "restart":
                                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                                let lang = presentationData.strings.baseLanguageCode
                                context.sharedContext.presentGlobalController(
                                    UndoOverlayController(
                                        presentationData: presentationData,
                                        content: .info(title: nil,
                                            text: "Common.RestartRequired".i18n(lang),
                                            timeout: nil,
                                            customUndoText: "Common.RestartNow".i18n(lang)
                                        ),
                                        elevatedLayout: false,
                                        action: { action in if action == .undo { exit(0) }; return true }
                                    ),
                                    nil
                                )
                            default:
                                break
                        }
                    }
                case "ton":
                    handleResolvedUrl(.ton)
                case "importstickers":
                    handleResolvedUrl(.importStickers)
                case "premium_offer":
                    handleResolvedUrl(.premiumOffer(reference: nil))
                case "restore_purchases":
                    let statusController = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: nil))
                    context.sharedContext.presentGlobalController(statusController, nil)

                    context.inAppPurchaseManager?.restorePurchases(completion: { [weak statusController] result in
                        statusController?.dismiss()

                        let text: String?
                        switch result {
                        case let .succeed(serverProvided):
                            text = serverProvided ? nil : presentationData.strings.Premium_Restore_Success
                        case .failed:
                            text = presentationData.strings.Premium_Restore_ErrorUnknown
                        }
                        if let text {
                            let alertController = textAlertController(context: context, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})])
                            context.sharedContext.presentGlobalController(alertController, nil)
                        }
                    })
                case "send_gift":
                    handleResolvedUrl(.sendGift(peerId: nil))
                case "contacts":
                    var section: ResolvedUrl.ContactsSection?
                    if let path = parsedUrl.pathComponents.last {
                        switch path {
                        case "search":
                            section = .search
                        case "sort":
                            section = .sort
                        case "new":
                            section = .new
                        case "invite":
                            section = .invite
                        case "manage":
                            section = .manage
                        default:
                            break
                        }
                    }
                    handleResolvedUrl(.contacts(section))
                case "chats":
                    var section: ResolvedUrl.ChatsSection?
                    if let path = parsedUrl.pathComponents.last {
                        switch path {
                        case "search":
                            section = .search
                        case "edit":
                            section = .edit
                        case "emoji-status":
                            section = .emojiStatus
                        default:
                            break
                        }
                    }
                    handleResolvedUrl(.chats(section))
                case "new":
                    var section: ResolvedUrl.ComposeSection?
                    if let path = parsedUrl.pathComponents.last {
                        switch path {
                        case "group":
                            section = .group
                        case "channel":
                            section = .channel
                        case "contact":
                            section = .contact
                        default:
                            break
                        }
                    }
                    handleResolvedUrl(.compose(section))
                case "post":
                    var section: ResolvedUrl.PostStorySection?
                    if let path = parsedUrl.pathComponents.last {
                        switch path {
                        case "photo":
                            section = .photo
                        case "video":
                            section = .video
                        case "live":
                            section = .live
                        default:
                            break
                        }
                    }
                    handleResolvedUrl(.postStory(section))
                case "settings":
                    if let lastComponent = parsedUrl.pathComponents.last {
                        let fullPath = parsedUrl.pathComponents.joined(separator: "/").replacingOccurrences(of: "//", with: "")
                        var section: ResolvedUrl.SettingsSection?
                        if parsedUrl.pathComponents.count == 2 {
                            switch lastComponent {
                            case "themes":
                                section = .legacy(.theme)
                            case "devices":
                                section = .legacy(.devices)
                            case "enable_log":
                                section = .legacy(.enableLog)
                            case "phone_privacy":
                                section = .legacy(.phonePrivacy)
                            case "login_email":
                                section = .legacy(.loginEmail)
                            default:
                                section = .path(fullPath)
                            }
                        } else {
                            section = .path(fullPath)
                        }
                        if let section {
                            handleResolvedUrl(.settings(section))
                        }
                    } else {
                        handleResolvedUrl(.settings(.path("")))
                    }
                default:
                    break
                }
            }

            if let convertedUrl {
                handleInternalUrl(convertedUrl)
            } else if let path = parsedUrl.host {
                handleResolvedUrl(.unknownDeepLink(path: path))
            }
            return
        }

        handleInternetUrl(
            parsedUrl: parsedUrl,
            originalUrl: url,
            context: context,
            presentationData: presentationData,
            navigationController: navigationController,
            handleInternalUrl: handleInternalUrl
        )
    }

    if let scheme = parsedUrl.scheme, internetSchemes.contains(scheme) {
        if let host = parsedUrl.host, telegramMeHosts.contains(host) {
            continueHandling()
        } else {
            if isTelegramWebShortLink(parsedUrl.absoluteString) {
                handleInternetUrl(
                    parsedUrl: parsedUrl,
                    originalUrl: url,
                    context: context,
                    presentationData: presentationData,
                    navigationController: navigationController,
                    handleInternalUrl: handleInternalUrl
                )
            } else if isTelegraPhLink(parsedUrl.absoluteString) {
                continueHandling()
            } else {
                context.sharedContext.applicationBindings.openUniversalUrl(url, TelegramApplicationOpenUrlCompletion(completion: { success in
                    if !success {
                        continueHandling()
                    }
                }))
            }
        }
    } else {
        continueHandling()
    }
}
