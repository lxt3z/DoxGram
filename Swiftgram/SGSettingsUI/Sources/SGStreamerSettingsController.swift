// MARK: Swiftgram
import SGLogging
import SGSimpleSettings
import SGStrings
import SGItemListUI
import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

private enum SGStreamerSection: Int32, SGItemListSection {
    case master
    case elements
}

private enum SGStreamerBoolSetting: String {
    case streamerMode
    case streamerAutoScreenCapture
    case streamerHideNames
    case streamerHideAvatars
    case streamerHideMessages
    case streamerHideUsernames
    case streamerHideStatuses
    case streamerHideGroupNames
    case streamerHideNotifications
}

private typealias SGStreamerEntry = SGItemListUIEntry<SGStreamerSection, SGStreamerBoolSetting, String, String, String, String>

private func sgStreamerEntries(presentationData: PresentationData) -> [SGStreamerEntry] {
    let lang = presentationData.strings.baseLanguageCode
    var entries: [SGStreamerEntry] = []
    let id = SGItemListCounter()
    
    let isMasterActive = SGSimpleSettings.shared.streamerMode || SGSimpleSettings.shared.streamerAutoScreenCapture
    
    let masterHeader = lang.hasPrefix("ru") ? "РЕЖИМ СТРИМЕРА" : "STREAMER MODE"
    entries.append(.header(id: id.count, section: .master, text: masterHeader, badge: nil))
    entries.append(.toggle(id: id.count, section: .master, settingName: .streamerMode, value: SGSimpleSettings.shared.streamerMode, text: i18n("Settings.Ayugram.StreamerMode", lang), enabled: true))
    entries.append(.toggle(id: id.count, section: .master, settingName: .streamerAutoScreenCapture, value: SGSimpleSettings.shared.streamerAutoScreenCapture, text: i18n("Settings.Ayugram.StreamerAutoScreenCapture", lang), enabled: true))
    entries.append(.notice(id: id.count, section: .master, text: i18n("Settings.Ayugram.StreamerMode.Notice", lang)))
    
    let elementsHeader = lang.hasPrefix("ru") ? "ЧТО СКРЫВАТЬ" : "WHAT TO HIDE"
    entries.append(.header(id: id.count, section: .elements, text: elementsHeader, badge: nil))
    entries.append(.toggle(id: id.count, section: .elements, settingName: .streamerHideNames, value: SGSimpleSettings.shared.streamerHideNames, text: i18n("Settings.Ayugram.StreamerHideNames", lang), enabled: isMasterActive))
    entries.append(.toggle(id: id.count, section: .elements, settingName: .streamerHideUsernames, value: SGSimpleSettings.shared.streamerHideUsernames, text: i18n("Settings.Ayugram.StreamerHideUsernames", lang), enabled: isMasterActive))
    entries.append(.toggle(id: id.count, section: .elements, settingName: .streamerHideAvatars, value: SGSimpleSettings.shared.streamerHideAvatars, text: i18n("Settings.Ayugram.StreamerHideAvatars", lang), enabled: isMasterActive))
    entries.append(.toggle(id: id.count, section: .elements, settingName: .streamerHideMessages, value: SGSimpleSettings.shared.streamerHideMessages, text: i18n("Settings.Ayugram.StreamerHideMessages", lang), enabled: isMasterActive))
    entries.append(.toggle(id: id.count, section: .elements, settingName: .streamerHideStatuses, value: SGSimpleSettings.shared.streamerHideStatuses, text: i18n("Settings.Ayugram.StreamerHideStatuses", lang), enabled: isMasterActive))
    entries.append(.toggle(id: id.count, section: .elements, settingName: .streamerHideGroupNames, value: SGSimpleSettings.shared.streamerHideGroupNames, text: i18n("Settings.Ayugram.StreamerHideGroupNames", lang), enabled: isMasterActive))
    entries.append(.toggle(id: id.count, section: .elements, settingName: .streamerHideNotifications, value: SGSimpleSettings.shared.streamerHideNotifications, text: i18n("Settings.Ayugram.StreamerHideNotifications", lang), enabled: isMasterActive))
    
    let noticeText = lang.hasPrefix("ru") ? "Выбранные конфиденциальные данные автоматически скрываются в интерфейсе при активном режиме стримера или захвате экрана." : "Selected private data will be automatically hidden throughout the interface when streamer mode or screen recording is active."
    entries.append(.notice(id: id.count, section: .elements, text: noticeText))
    
    return entries
}

public func sgStreamerSettingsController(context: AccountContext) -> ViewController {
    let simplePromise = ValuePromise(true, ignoreRepeated: false)
    
    let arguments = SGItemListArguments<SGStreamerBoolSetting, String, String, String, String>(
        context: context,
        setBoolValue: { setting, value in
            switch setting {
            case .streamerMode:
                SGSimpleSettings.shared.streamerMode = value
            case .streamerAutoScreenCapture:
                SGSimpleSettings.shared.streamerAutoScreenCapture = value
            case .streamerHideNames:
                SGSimpleSettings.shared.streamerHideNames = value
            case .streamerHideAvatars:
                SGSimpleSettings.shared.streamerHideAvatars = value
            case .streamerHideMessages:
                SGSimpleSettings.shared.streamerHideMessages = value
            case .streamerHideUsernames:
                SGSimpleSettings.shared.streamerHideUsernames = value
            case .streamerHideStatuses:
                SGSimpleSettings.shared.streamerHideStatuses = value
            case .streamerHideGroupNames:
                SGSimpleSettings.shared.streamerHideGroupNames = value
            case .streamerHideNotifications:
                SGSimpleSettings.shared.streamerHideNotifications = value
            }
            simplePromise.set(true)
            NotificationCenter.default.post(name: Notification.Name("SGStreamerStateChanged"), object: nil)
        }
    )
    
    let signal = combineLatest(
        simplePromise.get(),
        context.sharedContext.presentationData
    )
    |> map { _, presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let entries = sgStreamerEntries(presentationData: presentationData)
        let lang = presentationData.strings.baseLanguageCode
        let title = i18n("Settings.Ayugram.StreamerMode", lang)
        
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(title),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks,
            ensureVisibleItemTag: nil,
            initialScrollToItem: nil
        )
        return (controllerState, (listState, arguments))
    }
    
    return ItemListController(context: context, state: signal)
}
