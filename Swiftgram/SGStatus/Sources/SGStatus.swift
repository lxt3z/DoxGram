import Foundation
import SwiftSignalKit
import TelegramCore

public struct SGStatus: Equatable, Codable {
    private var _status: Int64 = 2

    public var status: Int64 {
        get {
            return max(self._status, 2)
        }
        set {
            self._status = max(newValue, 2)
        }
    }
    
    public static var `default`: SGStatus {
        return SGStatus(status: 2)
    }
    
    public init(status: Int64 = 2) {
        self._status = max(status, 2)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)

        let decoded = try container.decodeIfPresent(Int64.self, forKey: "status") ?? 2
        self._status = max(decoded, 2)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)

        try container.encodeIfPresent(self.status, forKey: "status")
    }

    public static func == (lhs: SGStatus, rhs: SGStatus) -> Bool {
        return lhs.status == rhs.status
    }
}

public func updateSGStatusInteractively(accountManager: AccountManager<TelegramAccountManagerTypes>, _ f: @escaping (SGStatus) -> SGStatus) -> Signal<Void, NoError> {
    return accountManager.transaction { transaction -> Void in
        transaction.updateSharedData(ApplicationSpecificSharedDataKeys.sgStatus, { entry in
            let currentSettings: SGStatus
            if let entry = entry?.get(SGStatus.self) {
                currentSettings = entry
            } else {
                currentSettings = SGStatus.default
            }
            return SharedPreferencesEntry(f(currentSettings))
        })
    }
}
