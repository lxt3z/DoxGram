import Foundation
import Postbox
import SwiftSignalKit
import MtProtoKit


func _internal_addAppLogEvent(postbox: Postbox, time: Double = Date().timeIntervalSince1970, type: String, peerId: PeerId? = nil, data: JSON = .dictionary([:])) {
}

public func invokeAppLogEventsSynchronization(postbox: Postbox) {
}
