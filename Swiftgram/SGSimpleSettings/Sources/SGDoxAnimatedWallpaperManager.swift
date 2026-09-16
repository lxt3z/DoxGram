import Foundation
import SGAppGroupIdentifier
import SGLogging

public extension Notification.Name {
    static let doxChatWallpaperDidChange = Notification.Name("SGDoxChatWallpaperDidChange")
}

public final class SGDoxAnimatedWallpaperManager {
    public static let shared = SGDoxAnimatedWallpaperManager()
    
    public enum Quality: String, CaseIterable {
        case p360 = "360p"
        case p480 = "480p"
        case p720 = "720p"
        case p1080 = "1080p"

        public var displayName: String {
            return self.rawValue
        }
    }

    public var currentQuality: String {
        return SGSimpleSettings.shared.animatedWallpaperQuality
    }

    public func wallpaperUrl(for peerId: Int64) -> String? {
        return self.getWallpaper(for: peerId)?.url
    }

    public func localFileUrl(for peerId: Int64) -> URL? {
        guard let localPath = self.getWallpaper(for: peerId)?.localPath else {
            return nil
        }
        return URL(fileURLWithPath: localPath)
    }

    public func setWallpaper(url: String, for peerId: Int64, quality: String = "720p") {
        self.setWallpaper(for: peerId, urlString: url, quality: quality, completion: { _, _ in })
    }

    public func clearCache() {
        self.clearAllCache()
    }
    
    public static let qualityOptions: [String] = ["360p", "480p", "720p", "1080p"]
    
    private let userDefaultsKey = "dox_chat_wallpapers_v1"
    private let queue = DispatchQueue(label: "org.doxgram.wallpaper.queue", qos: .utility)
    
    private init() {
        self.ensureDirectoryExists()
    }
    
    private var wallpapersDirectory: URL {
        let appGroupId = sgAppGroupIdentifier()
        let baseUrl: URL
        if let groupContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) {
            baseUrl = groupContainer
        } else {
            baseUrl = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        }
        return baseUrl.appendingPathComponent("dox_wallpapers", isDirectory: true)
    }
    
    private func ensureDirectoryExists() {
        let dir = self.wallpapersDirectory
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }
    }
    
    private func getStoredData() -> [String: [String: String]] {
        if let groupDefaults = UserDefaults(suiteName: sgAppGroupIdentifier()),
           let dict = groupDefaults.dictionary(forKey: self.userDefaultsKey) as? [String: [String: String]] {
            return dict
        }
        return (UserDefaults.standard.dictionary(forKey: self.userDefaultsKey) as? [String: [String: String]]) ?? [:]
    }
    
    private func saveStoredData(_ data: [String: [String: String]]) {
        if let groupDefaults = UserDefaults(suiteName: sgAppGroupIdentifier()) {
            groupDefaults.set(data, forKey: self.userDefaultsKey)
            groupDefaults.synchronize()
        }
        UserDefaults.standard.set(data, forKey: self.userDefaultsKey)
    }
    
    public func getWallpaper(for peerId: Int64) -> (url: String, localPath: String, quality: String)? {
        let data = self.getStoredData()
        guard let entry = data[String(peerId)],
              let url = entry["url"],
              let localPath = entry["localPath"],
              FileManager.default.fileExists(atPath: localPath) else {
            return nil
        }
        let quality = entry["quality"] ?? "720p"
        return (url, localPath, quality)
    }
    
    public func setWallpaper(for peerId: Int64, urlString: String, quality: String, completion: @escaping (Bool, String?) -> Void) {
        let trimmedUrl = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedUrl), ["http", "https"].contains(url.scheme?.lowercased()) else {
            completion(false, "Invalid URL")
            return
        }
        
        self.ensureDirectoryExists()
        let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
        let destinationFile = self.wallpapersDirectory.appendingPathComponent("\(peerId).\(ext)")
        
        let session = URLSession(configuration: .default)
        let task = session.downloadTask(with: url) { [weak self] tempUrl, response, error in
            guard let self = self else { return }
            
            if let error = error {
                SGLogger.shared.log("SGDoxAnimatedWallpaperManager", "Download error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(false, error.localizedDescription)
                }
                return
            }
            
            guard let tempUrl = tempUrl else {
                DispatchQueue.main.async {
                    completion(false, "Download failed")
                }
                return
            }
            
            do {
                if FileManager.default.fileExists(atPath: destinationFile.path) {
                    try FileManager.default.removeItem(at: destinationFile)
                }
                try FileManager.default.moveItem(at: tempUrl, to: destinationFile)
                
                self.queue.async {
                    var data = self.getStoredData()
                    data[String(peerId)] = [
                        "url": trimmedUrl,
                        "localPath": destinationFile.path,
                        "quality": quality
                    ]
                    self.saveStoredData(data)
                    
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .doxChatWallpaperDidChange, object: nil, userInfo: ["peerId": peerId])
                        completion(true, nil)
                    }
                }
            } catch {
                SGLogger.shared.log("SGDoxAnimatedWallpaperManager", "File error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(false, error.localizedDescription)
                }
            }
        }
        task.resume()
    }
    
    public func removeWallpaper(for peerId: Int64) {
        self.queue.async {
            var data = self.getStoredData()
            if let entry = data.removeValue(forKey: String(peerId)),
               let localPath = entry["localPath"] {
                try? FileManager.default.removeItem(atPath: localPath)
            }
            self.saveStoredData(data)
            
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .doxChatWallpaperDidChange, object: nil, userInfo: ["peerId": peerId])
            }
        }
    }
    
    public func clearAllCache() {
        self.queue.async {
            let data = self.getStoredData()
            for (_, entry) in data {
                if let localPath = entry["localPath"] {
                    try? FileManager.default.removeItem(atPath: localPath)
                }
            }
            self.saveStoredData([:])
            try? FileManager.default.removeItem(at: self.wallpapersDirectory)
            self.ensureDirectoryExists()
            
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .doxChatWallpaperDidChange, object: nil, userInfo: nil)
            }
        }
    }
    
    // MARK: - Peer Syncing for DoxGram Users
    
    public func formatSyncTag(url: String, quality: String) -> String {
        return "#doxwall:\(url):\(quality)"
    }
    
    public func parseSyncTag(from text: String) -> (url: String, quality: String)? {
        guard let range = text.range(of: "#doxwall:") else {
            return nil
        }
        let remainder = String(text[range.upperBound...])
        let components = remainder.components(separatedBy: ":")
        guard components.count >= 2 else {
            return nil
        }
        
        let quality = components.last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "720p"
        let urlPart = components.dropLast().joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)
        
        if urlPart.hasPrefix("http://") || urlPart.hasPrefix("https://") {
            return (urlPart, quality)
        }
        return nil
    }
}
