import Foundation
import Postbox
import SwiftSignalKit
import MtProtoKit


func _internal_addAppLogEvent(postbox: Postbox, time: Double = Date().timeIntervalSince1970, type: String, peerId: PeerId? = nil, data: JSON = .dictionary([:])) {
}

func _internal_addAppLogEvent(transaction: Transaction, time: Double, type: String, data: JSON) {
    let tag: PeerOperationLogTag = OperationLogTags.SynchronizeAppLogEvents
    let peerId = PeerId(0)
    transaction.operationLogAddEntry(peerId: peerId, tag: tag, tagLocalIndex: .automatic, tagMergedIndex: .automatic, contents: SynchronizeAppLogEventsOperation(content: .add(time: time, type: type, peerId: peerId, data: data)))
}

public func invokeAppLogEventsSynchronization(postbox: Postbox) {
}
