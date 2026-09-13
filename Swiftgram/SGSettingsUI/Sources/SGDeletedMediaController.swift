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
import UndoUI

private enum SGDeletedMediaSection: Int32, SGItemListSection {
    case media
    case empty
}

private typealias SGDeletedMediaEntry = SGItemListUIEntry<SGDeletedMediaSection, String, String, String, String, String>

private func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useAll]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}

private func formatDate(_ timestamp: Int32) -> String {
    let date = Date(timeIntervalSince1970: Double(timestamp))
    let formatter = DateFormatter()
    formatter.dateFormat = "dd.MM.yy HH:mm"
    return formatter.string(from: date)
}

public func sgDeletedMediaController(context: AccountContext, peerId: Int64? = nil) -> ViewController {
    let updatePromise = ValuePromise(true, ignoreRepeated: false)
    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?

    let arguments = SGItemListArguments<String, String, String, String, String>(
        context: context,
        setOneFromManyValue: { itemId in
            let allItems: [SGAyugramMediaItem]
            if let peerId = peerId {
                allItems = SGAyugramStorage.shared.getDeletedMedia(peerId: peerId)
            } else {
                allItems = SGAyugramStorage.shared.getAllDeletedMedia()
            }
            guard let item = allItems.first(where: { $0.id == itemId }) else { return }
            guard let fileUrl = SGAyugramStorage.shared.getMediaFileUrl(item: item), FileManager.default.fileExists(atPath: fileUrl.path) else {
                return
            }

            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let isRu = presentationData.strings.baseLanguageCode.hasPrefix("ru")

            let actionSheet = ActionSheetController(presentationData: presentationData)
            var actionItems: [ActionSheetItem] = []

            actionItems.append(ActionSheetTextItem(title: item.fileName))

            actionItems.append(ActionSheetButtonItem(title: isRu ? "Поделиться / Сохранить" : "Share / Save", color: .accent, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                let activityVC = UIActivityViewController(activityItems: [fileUrl], applicationActivities: nil)
                if let window = context.sharedContext.mainWindow?.viewController?.view {
                    activityVC.popoverPresentationController?.sourceView = window
                    activityVC.popoverPresentationController?.sourceRect = CGRect(origin: CGPoint(x: window.bounds.width / 2.0, y: window.bounds.height / 2.0), size: CGSize(width: 1.0, height: 1.0))
                }
                context.sharedContext.applicationBindings.presentNativeController(activityVC)
            }))

            actionItems.append(ActionSheetButtonItem(title: isRu ? "Удалить из хранилища" : "Delete from vault", color: .destructive, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                SGAyugramStorage.shared.deleteMediaItem(id: item.id)
                updatePromise.set(true)
                let overlay = UndoOverlayController(presentationData: presentationData, content: .actionSucceeded(title: nil, text: isRu ? "Файл удалён" : "File deleted", cancel: nil, destructive: false), elevatedLayout: false, action: { _ in return false })
                presentControllerImpl?(overlay, nil)
            }))

            actionSheet.setItemGroups([
                ActionSheetItemGroup(items: actionItems),
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                    })
                ])
            ])
            presentControllerImpl?(actionSheet, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
        }
    )

    let signal = combineLatest(
        updatePromise.get(),
        context.sharedContext.presentationData
    )
    |> map { _, presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let isRu = presentationData.strings.baseLanguageCode.hasPrefix("ru")
        let title = isRu ? "Удалённые медиа" : "Deleted Media"

        let mediaItems: [SGAyugramMediaItem]
        if let peerId = peerId {
            mediaItems = SGAyugramStorage.shared.getDeletedMedia(peerId: peerId)
        } else {
            mediaItems = SGAyugramStorage.shared.getAllDeletedMedia()
        }

        var entries: [SGDeletedMediaEntry] = []
        let id = SGItemListCounter()

        if mediaItems.isEmpty {
            entries.append(.notice(id: id.count, section: .empty, text: isRu ? "Здесь будут сохраняться удалённые собеседником фото, видео и одноразовые файлы." : "Deleted photos, videos, and view-once files will appear here."))
        } else {
            var totalBytes: Int64 = 0
            for item in mediaItems {
                totalBytes += item.fileSize
            }
            let headerText = isRu ? "СОХРАНЕНО: \(mediaItems.count) (\(formatBytes(totalBytes)))" : "SAVED: \(mediaItems.count) (\(formatBytes(totalBytes)))"
            entries.append(.header(id: id.count, section: .media, text: headerText, badge: nil))

            for item in mediaItems {
                let icon: String
                switch item.mediaType {
                case "photo":
                    icon = "📸"
                case "video":
                    icon = "🎥"
                case "voice":
                    icon = "🎙"
                default:
                    icon = "📄"
                }
                let captionText = (item.caption?.isEmpty == false) ? " · \(item.caption!)" : ""
                let detail = "\(formatBytes(item.fileSize)) · \(formatDate(item.deletedAt))\(captionText)"
                entries.append(.oneFromManySelector(
                    id: id.count,
                    section: .media,
                    settingName: item.id,
                    text: "\(icon) \(item.fileName)",
                    value: detail,
                    enabled: true
                ))
            }
            entries.append(.notice(id: id.count, section: .media, text: isRu ? "Нажмите на файл, чтобы поделиться им или сохранить в Фото/Файлы." : "Tap a file to share it or save to Photos/Files."))
        }

        let rightButton: ItemListNavigationButton?
        if !mediaItems.isEmpty {
            rightButton = ItemListNavigationButton(
                content: .text(isRu ? "Очистить" : "Clear"),
                style: .regular,
                enabled: true,
                action: {
                    let confirmSheet = ActionSheetController(presentationData: presentationData)
                    confirmSheet.setItemGroups([
                        ActionSheetItemGroup(items: [
                            ActionSheetTextItem(title: isRu ? "Удалить все сохранённые файлы из локальной папки?" : "Delete all saved files from the local vault?"),
                            ActionSheetButtonItem(title: isRu ? "Очистить всё" : "Clear All", color: .destructive, action: { [weak confirmSheet] in
                                confirmSheet?.dismissAnimated()
                                SGAyugramStorage.shared.clearDeletedMedia(peerId: peerId)
                                updatePromise.set(true)
                            })
                        ]),
                        ActionSheetItemGroup(items: [
                            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak confirmSheet] in
                                confirmSheet?.dismissAnimated()
                            })
                        ])
                    ])
                    presentControllerImpl?(confirmSheet, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
                }
            )
        } else {
            rightButton = nil
        }

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(title),
            leftNavigationButton: nil,
            rightNavigationButton: rightButton,
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

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c, a in
        controller?.present(c, in: .window(.root), with: a)
    }
    return controller
}
