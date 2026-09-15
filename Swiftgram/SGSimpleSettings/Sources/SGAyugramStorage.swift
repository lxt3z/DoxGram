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

public struct SGAyugramMediaItem: Codable, Equatable {
    public let id: String
    public let peerId: Int64
    public let messageId: Int32
    public let fileName: String
    public let fileExtension: String
    public let mediaType: String // "photo", "video", "voice", "file"
    public let localFileName: String
    public let fileSize: Int64
    public let timestamp: Int32
    public let deletedAt: Int32
    public let caption: String?

    public init(
        id: String,
        peerId: Int64,
        messageId: Int32,
        fileName: String,
        fileExtension: String,
        mediaType: String,
        localFileName: String,
        fileSize: Int64,
        timestamp: Int32,
        deletedAt: Int32,
        caption: String?
    ) {
        self.id = id
        self.peerId = peerId
        self.messageId = messageId
        self.fileName = fileName
        self.fileExtension = fileExtension
        self.mediaType = mediaType
        self.localFileName = localFileName
        self.fileSize = fileSize
        self.timestamp = timestamp
        self.deletedAt = deletedAt
        self.caption = caption
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

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        return formatter
    }()

    public static func log(_ message: String) {
        guard SGSimpleSettings.shared.ayugramDebugger else { return }
        shared.appendLog(message)
    }

    public func appendLog(_ message: String) {
        let timestamp = SGAyugramLogger.dateFormatter.string(from: Date())
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

    public static func getLogFileSize() -> String? {
        shared.lock.readLock()
        defer { shared.lock.unlock() }
        guard let url = shared.logFileUrl,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64, size > 0 else {
            return nil
        }
        if size < 1024 {
            return "\(size) B"
        } else if size < 1024 * 1024 {
            return String(format: "%.1f KB", Double(size) / 1024.0)
        } else {
            return String(format: "%.2f MB", Double(size) / (1024.0 * 1024.0))
        }
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
    private var deletedMediaItems: [String: SGAyugramMediaItem] = [:]
    private var _isScreenCaptured: Bool = false

    private let fileManager = FileManager.default
    private let storageUrl: URL?
    private let saveQueue = DispatchQueue(label: "org.doxgram.storage.save", qos: .utility)
    private var pendingDeletedSave: DispatchWorkItem?
    private var pendingEditsSave: DispatchWorkItem?
    private var pendingMediaSave: DispatchWorkItem?

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

    @discardableResult
    public func saveDeletedMedia(
        peerId: Int64,
        messageId: Int32,
        sourcePath: String,
        fileName: String,
        mediaType: String,
        timestamp: Int32,
        caption: String? = nil
    ) -> SGAyugramMediaItem? {
        guard self.fileManager.fileExists(atPath: sourcePath) else {
            return nil
        }
        guard let storageUrl = self.storageUrl else { return nil }

        let peerMediaDir = storageUrl
            .appendingPathComponent("deleted_media", isDirectory: true)
            .appendingPathComponent("\(peerId)", isDirectory: true)
        try? self.fileManager.createDirectory(at: peerMediaDir, withIntermediateDirectories: true, attributes: nil)

        let ext = (fileName as NSString).pathExtension.lowercased()
        let fileExt: String
        if !ext.isEmpty {
            fileExt = ext
        } else if mediaType == "photo" {
            fileExt = "jpg"
        } else if mediaType == "video" {
            fileExt = "mp4"
        } else if mediaType == "voice" {
            fileExt = "m4a"
        } else {
            fileExt = "dat"
        }

        let hashSuffix = abs(fileName.hashValue % 100000)
        let itemId = "\(peerId)_\(messageId)_\(hashSuffix)"
        let localFileName = "\(itemId).\(fileExt)"
        let destinationUrl = peerMediaDir.appendingPathComponent(localFileName)

        if !self.fileManager.fileExists(atPath: destinationUrl.path) {
            try? self.fileManager.copyItem(at: URL(fileURLWithPath: sourcePath), to: destinationUrl)
        }

        let attr = (try? self.fileManager.attributesOfItem(atPath: destinationUrl.path)) ?? [:]
        let fileSize = (attr[.size] as? NSNumber)?.int64Value ?? 0

        let now = Int32(Date().timeIntervalSince1970)
        let item = SGAyugramMediaItem(
            id: itemId,
            peerId: peerId,
            messageId: messageId,
            fileName: fileName,
            fileExtension: fileExt,
            mediaType: mediaType,
            localFileName: localFileName,
            fileSize: fileSize,
            timestamp: timestamp > 0 ? timestamp : now,
            deletedAt: now,
            caption: caption
        )

        self.lock.writeLock()
        self.deletedMediaItems[itemId] = item
        self.lock.unlock()

        self.saveMediaToDisk()
        SGAyugramLogger.log("Saved deleted media: \(fileName) (\(fileSize) bytes) for peer \(peerId)")
        return item
    }

    public func getMediaFileUrl(item: SGAyugramMediaItem) -> URL? {
        guard let storageUrl = self.storageUrl else { return nil }
        return storageUrl
            .appendingPathComponent("deleted_media", isDirectory: true)
            .appendingPathComponent("\(item.peerId)", isDirectory: true)
            .appendingPathComponent(item.localFileName)
    }

    public func getDeletedMedia(peerId: Int64) -> [SGAyugramMediaItem] {
        self.lock.readLock()
        let items = self.deletedMediaItems.values
            .filter { $0.peerId == peerId }
            .sorted { $0.deletedAt > $1.deletedAt }
        self.lock.unlock()
        return items
    }

    public func getAllDeletedMedia() -> [SGAyugramMediaItem] {
        self.lock.readLock()
        let items = self.deletedMediaItems.values
            .sorted { $0.deletedAt > $1.deletedAt }
        self.lock.unlock()
        return items
    }

    public func getDeletedMediaCount(peerId: Int64) -> Int {
        self.lock.readLock()
        let count = self.deletedMediaItems.values.filter { $0.peerId == peerId }.count
        self.lock.unlock()
        return count
    }

    public func deleteMediaItem(id: String) {
        self.lock.writeLock()
        if let item = self.deletedMediaItems.removeValue(forKey: id) {
            self.lock.unlock()
            if let url = self.getMediaFileUrl(item: item) {
                try? self.fileManager.removeItem(at: url)
            }
            self.saveMediaToDisk()
        } else {
            self.lock.unlock()
        }
    }

    public func clearDeletedMedia(peerId: Int64? = nil) {
        self.lock.writeLock()
        if let peerId = peerId {
            let toRemove = self.deletedMediaItems.values.filter { $0.peerId == peerId }
            for item in toRemove {
                self.deletedMediaItems.removeValue(forKey: item.id)
                if let url = self.getMediaFileUrl(item: item) {
                    try? self.fileManager.removeItem(at: url)
                }
            }
        } else {
            for item in self.deletedMediaItems.values {
                if let url = self.getMediaFileUrl(item: item) {
                    try? self.fileManager.removeItem(at: url)
                }
            }
            self.deletedMediaItems.removeAll()
        }
        self.lock.unlock()
        self.saveMediaToDisk()
    }

    public func cleanupExpired(retentionDays: Int) {
        guard retentionDays > 0 else { return }
        let cutoff = Int32(Date().timeIntervalSince1970) - Int32(retentionDays * 86400)
        self.lock.writeLock()
        var deletedChanged = false
        var editsChanged = false
        var mediaChanged = false

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

        for (k, item) in self.deletedMediaItems {
            if item.deletedAt < cutoff {
                self.deletedMediaItems.removeValue(forKey: k)
                if let url = self.getMediaFileUrl(item: item) {
                    try? self.fileManager.removeItem(at: url)
                }
                mediaChanged = true
            }
        }
        self.lock.unlock()

        if deletedChanged {
            self.saveDeletedToDisk()
        }
        if editsChanged {
            self.saveEditsToDisk()
        }
        if mediaChanged {
            self.saveMediaToDisk()
        }
        SGAyugramLogger.log("Expired messages purged for retentionDays=\(retentionDays)")
    }

    private func saveDeletedToDisk() {
        guard let url = self.storageUrl?.appendingPathComponent("deleted_messages.json") else { return }
        self.lock.readLock()
        let dict = self.deletedMessages
        self.lock.unlock()
        self.saveQueue.async {
            self.pendingDeletedSave?.cancel()
            let workItem = DispatchWorkItem {
                if let data = try? JSONEncoder().encode(dict) {
                    try? data.write(to: url, options: .atomic)
                }
            }
            self.pendingDeletedSave = workItem
            self.saveQueue.asyncAfter(deadline: .now() + 2.0, execute: workItem)
        }
    }

    private func saveEditsToDisk() {
        guard let url = self.storageUrl?.appendingPathComponent("edit_history.json") else { return }
        self.lock.readLock()
        let edits = self.editHistories
        self.lock.unlock()
        self.saveQueue.async {
            self.pendingEditsSave?.cancel()
            let workItem = DispatchWorkItem {
                if let data = try? JSONEncoder().encode(edits) {
                    try? data.write(to: url, options: .atomic)
                }
            }
            self.pendingEditsSave = workItem
            self.saveQueue.asyncAfter(deadline: .now() + 2.0, execute: workItem)
        }
    }

    private func saveMediaToDisk() {
        guard let url = self.storageUrl?.appendingPathComponent("deleted_media.json") else { return }
        self.lock.readLock()
        let items = self.deletedMediaItems
        self.lock.unlock()
        self.saveQueue.async {
            self.pendingMediaSave?.cancel()
            let workItem = DispatchWorkItem {
                if let data = try? JSONEncoder().encode(items) {
                    try? data.write(to: url, options: .atomic)
                }
            }
            self.pendingMediaSave = workItem
            self.saveQueue.asyncAfter(deadline: .now() + 2.0, execute: workItem)
        }
    }

    public func flushNow() {
        guard let storageUrl = self.storageUrl else { return }
        self.lock.readLock()
        let dict = self.deletedMessages
        let edits = self.editHistories
        let items = self.deletedMediaItems
        self.lock.unlock()

        self.saveQueue.sync {
            self.pendingDeletedSave?.cancel()
            self.pendingDeletedSave = nil
            self.pendingEditsSave?.cancel()
            self.pendingEditsSave = nil
            self.pendingMediaSave?.cancel()
            self.pendingMediaSave = nil

            let deletedUrl = storageUrl.appendingPathComponent("deleted_messages.json")
            if let data = try? JSONEncoder().encode(dict) {
                try? data.write(to: deletedUrl, options: .atomic)
            }
            let editsUrl = storageUrl.appendingPathComponent("edit_history.json")
            if let data = try? JSONEncoder().encode(edits) {
                try? data.write(to: editsUrl, options: .atomic)
            }
            let mediaUrl = storageUrl.appendingPathComponent("deleted_media.json")
            if let data = try? JSONEncoder().encode(items) {
                try? data.write(to: mediaUrl, options: .atomic)
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

        let mediaUrl = storageUrl.appendingPathComponent("deleted_media.json")
        if let data = try? Data(contentsOf: mediaUrl),
           let items = try? JSONDecoder().decode([String: SGAyugramMediaItem].self, from: data) {
            self.deletedMediaItems = items
        }
    }
}

