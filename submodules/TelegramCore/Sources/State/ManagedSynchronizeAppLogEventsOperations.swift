import Foundation
import Postbox
import SwiftSignalKit
internal import TelegramApi
import MtProtoKit
import SGSimpleSettings

private let appLogEventsBatchLimit = 50
private let appLogEventsBatchDelay: Double = 30.0
private let appLogEventsBatchMaxBytes = 256 * 1024

func managedSynchronizeAppLogEventsOperations(postbox: Postbox, network: Network) -> Signal<Void, NoError> {
    return .complete()
}

private func synchronizeAppLogEvents(transaction: Transaction, postbox: Postbox, network: Network, operations: [SynchronizeAppLogEventsOperation]) -> Signal<Void, NoError> {
    return .complete()
}
