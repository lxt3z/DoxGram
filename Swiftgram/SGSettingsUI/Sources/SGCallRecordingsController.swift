import Foundation
import UIKit
import AccountContext
import ItemListUI
import SwiftSignalKit
import SGCallRecordings
import SGItemListUI

private enum RecordingSection: Int32, SGItemListSection {
    case files
}

func sgCallRecordingsController(context: AccountContext) -> ItemListController {
    typealias Arguments = SGItemListArguments<AnyHashable, AnyHashable, AnyHashable, URL, AnyHashable>
    typealias Entry = SGItemListUIEntry<RecordingSection, AnyHashable, AnyHashable, AnyHashable, URL, AnyHashable>

    let arguments = Arguments(context: context, openDisclosureLink: { url in
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        context.sharedContext.applicationBindings.presentNativeController(picker)
    })
    let state = context.sharedContext.presentationData
    |> map { data -> (ItemListControllerState, (ItemListNodeState, Arguments)) in
        let isRu = data.strings.baseLanguageCode.hasPrefix("ru")
        let presentation = ItemListPresentationData(data)
        let header = ItemListControllerState(presentationData: presentation,
            title: .text(isRu ? "Записи звонков" : "Call Recordings"),
            leftNavigationButton: nil, rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: data.strings.Common_Back))
        let files = SGCallRecordings.files()
        let entries: [Entry]
        if files.isEmpty {
            entries = [.notice(id: 0, section: .files, text: isRu ? "Нет сохранённых видео." : "No saved videos.")]
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .medium
            entries = files.enumerated().map { index, url in
                let values = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
                let name = values?.creationDate.map { dateFormatter.string(from: $0) } ?? url.lastPathComponent
                let size = ByteCountFormatter.string(fromByteCount: Int64(values?.fileSize ?? 0), countStyle: .file)
                return .disclosure(id: index, section: .files, link: url, text: "\(name) · \(size)")
            }
        }
        return (header, (ItemListNodeState(presentationData: presentation, entries: entries,
            style: .blocks, ensureVisibleItemTag: nil, initialScrollToItem: nil), arguments))
    }
    return ItemListController(context: context, state: state)
}
