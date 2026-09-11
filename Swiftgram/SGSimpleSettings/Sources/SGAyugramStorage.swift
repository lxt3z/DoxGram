import Foundation
import SGAppGroupIdentifier
import SGLogging

public struct SGAyugramEditEntry: Codable, Equatable {
    public let text: String
    public let timestamp: Int32

    public init(text: String, timestamp: Int32) {
        self.text = text
        self.timestamp = timestamp
    }
}

public struct SGAyugramDeletedEntry: Codable, Equatable {
    public let text: String
    public let timestamp: Int32
    public let deletedAt: Int32

    public init(text: String, timestamp: Int32, deletedAt: Int32) {
        self.text = text
        self.timestamp = timestamp
        self.deletedAt = deletedAt
    }
}

public final class SGAyugramLogger {
    public static let shared = SGAyugramLogger()
    private let lock = RWLock()
    private let logFileUrl: URL?

    private init() {
        let fileManager = FileManager.default
        let baseDir: URL?
        if let containerUrl = fileManager.containerURL(forSecurityApplicationGroupIdentifier: sgAppGroupIdentifier()) {
            baseDir = containerUrl.appendingPathComponent("ayugram", isDirectory: true)
        } else {
            baseDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("ayugram", isDirectory: true)
        }
        if let dir = baseDir {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
            self.logFileUrl = dir.appendingPathComponent("ayugram_debug.log")
        } else {
            self.logFileUrl = nil
        }
    }

    public static func log(_ message: String) {
        shared.appendLog(message)
    }

    public func appendLog(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        self.lock.writeLock()
        defer { self.lock.unlock() }

        guard let url = self.logFileUrl else { return }
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path) {
                if let fileHandle = try? FileHandle(forWritingTo: url) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    try? fileHandle.close()
                }
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    public static func getLogFileUrl() -> URL? {
        return shared.logFileUrl
    }

    public static func getLogData() -> Data? {
        shared.lock.readLock()
        defer { shared.lock.unlock() }
        guard let url = shared.logFileUrl else { return nil }
        return try? Data(contentsOf: url)
    }

    public static func clearLogs() {
        shared.lock.writeLock()
        defer { shared.lock.unlock() }
        guard let url = shared.logFileUrl else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

public final class SGAyugramStorage {
    public static let shared = SGAyugramStorage()

    private let lock = RWLock()
    private var deletedMessages: [String: SGAyugramDeletedEntry] = [:]
    private var editHistories: [String: [SGAyugramEditEntry]] = [:]
    private var _isScreenCaptured: Bool = false

    private let fileManager = FileManager.default
    private let storageUrl: URL?

    public var isScreenCaptured: Bool {
        self.lock.readLock()
        let val = self._isScreenCaptured
        self.lock.unlock()
        return val
    }

    public func setIsScreenCaptured(_ captured: Bool) {
        self.lock.writeLock()
        let changed = (self._isScreenCaptured != captured)
        self._isScreenCaptured = captured
        self.lock.unlock()
        if changed {
            SGAyugramLogger.log("Screen capture state changed to: \(captured)")
        }
    }

    private init() {
        if let containerUrl = fileManager.containerURL(forSecurityApplicationGroupIdentifier: sgAppGroupIdentifier()) {
            let dir = containerUrl.appendingPathComponent("ayugram", isDirectory: true)
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
            self.storageUrl = dir
        } else {
            let dir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("ayugram", isDirectory: true)
            if let dir = dir {
                try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
            }
            self.storageUrl = dir
        }

        self.loadFromDisk()
    }

    private func keyFor(peerId: Int64, namespace: Int32, id: Int32) -> String {
        return "\(peerId)_\(namespace)_\(id)"
    }

    public func markDeleted(peerId: Int64, namespace: Int32, id: Int32, text: String? = nil, timestamp: Int32? = nil) {
        let key = self.keyFor(peerId: peerId, namespace: namespace, id: id)
        let now = Int32(Date().timeIntervalSince1970)
        self.lock.writeLock()
        if let existing = self.deletedMessages[key] {
            let updatedText = (text?.isEmpty == false) ? (text ?? "") : existing.text
            let updatedTimestamp = ((timestamp ?? 0) != 0) ? (timestamp ?? 0) : existing.timestamp
            self.deletedMessages[key] = SGAyugramDeletedEntry(text: updatedText, timestamp: updatedTimestamp, deletedAt: existing.deletedAt)
        } else {
            self.deletedMessages[key] = SGAyugramDeletedEntry(text: text ?? "", timestamp: timestamp ?? now, deletedAt: now)
        }
        self.lock.unlock()
        SGAyugramLogger.log("Marked deleted message: \(key) (len=\(text?.count ?? 0))")
        self.saveDeletedToDisk()
    }

    public func getDeletedEntry(peerId: Int64, namespace: Int32, id: Int32) -> SGAyugramDeletedEntry? {
        let key = self.keyFor(peerId: peerId, namespace: namespace, id: id)
        self.lock.readLock()
        let entry = self.deletedMessages[key]
        self.lock.unlock()
        return entry
    }

    public func isDeleted(peerId: Int64, namespace: Int32, id: Int32) -> Bool {
        let key = self.keyFor(peerId: peerId, namespace: namespace, id: id)
        self.lock.readLock()
        let contains = (self.deletedMessages[key] != nil)
        self.lock.unlock()
        return contains
    }

    public func recordEdit(peerId: Int64, namespace: Int32, id: Int32, text: String, timestamp: Int32) {
        guard !text.isEmpty else { return }
        let key = self.keyFor(peerId: peerId, namespace: namespace, id: id)
        let entry = SGAyugramEditEntry(text: text, timestamp: timestamp)
        self.lock.writeLock()
        var list = self.editHistories[key] ?? []
        if list.last?.text != text {
            list.append(entry)
            self.editHistories[key] = list
            SGAyugramLogger.log("Recorded edit for: \(key), revisions: \(list.count)")
        }
        self.lock.unlock()
        self.saveEditsToDisk()
    }

    public func getEditHistory(peerId: Int64, namespace: Int32, id: Int32) -> [SGAyugramEditEntry] {
        let key = self.keyFor(peerId: peerId, namespace: namespace, id: id)
        self.lock.readLock()
        let list = self.editHistories[key] ?? []
        self.lock.unlock()
        return list
    }

    public func hasEditHistory(peerId: Int64, namespace: Int32, id: Int32) -> Bool {
        let key = self.keyFor(peerId: peerId, namespace: namespace, id: id)
        self.lock.readLock()
        let has = !(self.editHistories[key]?.isEmpty ?? true)
        self.lock.unlock()
        return has
    }

    public func cleanupExpired(retentionDays: Int) {
        guard retentionDays > 0 else { return }
        let cutoff = Int32(Date().timeIntervalSince1970) - Int32(retentionDays * 86400)
        self.lock.writeLock()
        var deletedChanged = false
        var editsChanged = false

        for (k, entry) in self.deletedMessages {
            if entry.deletedAt < cutoff {
                self.deletedMessages.removeValue(forKey: k)
                deletedChanged = true
            }
        }

        for (k, edits) in self.editHistories {
            let filtered = edits.filter { $0.timestamp >= cutoff }
            if filtered.count != edits.count {
                if filtered.isEmpty {
                    self.editHistories.removeValue(forKey: k)
                } else {
                    self.editHistories[k] = filtered
                }
                editsChanged = true
            }
        }
        self.lock.unlock()

        if deletedChanged {
            self.saveDeletedToDisk()
        }
        if editsChanged {
            self.saveEditsToDisk()
        }
        SGAyugramLogger.log("Expired messages purged for retentionDays=\(retentionDays)")
    }

    private func saveDeletedToDisk() {
        guard let url = self.storageUrl?.appendingPathComponent("deleted_messages.json") else { return }
        self.lock.readLock()
        let dict = self.deletedMessages
        self.lock.unlock()
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(dict) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private func saveEditsToDisk() {
        guard let url = self.storageUrl?.appendingPathComponent("edit_history.json") else { return }
        self.lock.readLock()
        let edits = self.editHistories
        self.lock.unlock()
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(edits) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private func loadFromDisk() {
        guard let storageUrl = self.storageUrl else { return }
        let deletedUrl = storageUrl.appendingPathComponent("deleted_messages.json")
        if let data = try? Data(contentsOf: deletedUrl) {
            if let dict = try? JSONDecoder().decode([String: SGAyugramDeletedEntry].self, from: data) {
                self.deletedMessages = dict
            } else if let keys = try? JSONDecoder().decode([String].self, from: data) {
                let now = Int32(Date().timeIntervalSince1970)
                var dict: [String: SGAyugramDeletedEntry] = [:]
                for k in keys {
                    dict[k] = SGAyugramDeletedEntry(text: "", timestamp: now, deletedAt: now)
                }
                self.deletedMessages = dict
            }
        }

        let editsUrl = storageUrl.appendingPathComponent("edit_history.json")
        if let data = try? Data(contentsOf: editsUrl),
           let edits = try? JSONDecoder().decode([String: [SGAyugramEditEntry]].self, from: data) {
            self.editHistories = edits
        }
    }
}

