import Foundation
import SGAppGroupIdentifier
import SGLogging

public extension Notification.Name {
    static let doxChatWallpaperDidChange = Notification.Name("SGDoxChatWallpaperDidChange")
}

public final class SGDoxAnimatedWallpaperManager {
    public static let shared = SGDoxAnimatedWallpaperManager()
    public static let globalWallpaperPeerId: Int64 = 0
    
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

    public var hasGlobalWallpaper: Bool {
        return self.getWallpaper(for: Self.globalWallpaperPeerId, fallbackToGlobal: false) != nil
    }

    public var globalWallpaperUrl: String? {
        return self.getWallpaper(for: Self.globalWallpaperPeerId, fallbackToGlobal: false)?.url
    }

    public func removeGlobalWallpaper() {
        self.removeWallpaper(for: Self.globalWallpaperPeerId)
    }

    public func hasChatSpecificWallpaper(for peerId: Int64) -> Bool {
        return self.getWallpaper(for: peerId, fallbackToGlobal: false) != nil
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
    private let cacheLock = NSLock()
    private var memoryCache: [String: (url: String, localPath: String, quality: String)] = [:]
    private var isCacheLoaded = false
    private var activeDownloads = Set<String>()
    
    public func isDownloading(for peerId: Int64) -> Bool {
        self.cacheLock.lock()
        defer { self.cacheLock.unlock() }
        return self.activeDownloads.contains(String(peerId))
    }
    
    public func markDownloading(for peerId: Int64, url: String) {
        self.cacheLock.lock()
        self.activeDownloads.insert(String(peerId))
        self.cacheLock.unlock()
    }
    
    public func clearDownloading(for peerId: Int64) {
        self.cacheLock.lock()
        self.activeDownloads.remove(String(peerId))
        self.cacheLock.unlock()
    }
    
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

        self.cacheLock.lock()
        var updatedCache: [String: (url: String, localPath: String, quality: String)] = [:]
        for (key, entry) in data {
            if let url = entry["url"],
               let localPath = entry["localPath"] {
                let quality = entry["quality"] ?? "720p"
                updatedCache[key] = (url, localPath, quality)
            }
        }
        self.memoryCache = updatedCache
        self.isCacheLoaded = true
        self.cacheLock.unlock()
    }
    
    public func getWallpaper(for peerId: Int64, fallbackToGlobal: Bool = true) -> (url: String, localPath: String, quality: String)? {
        self.cacheLock.lock()
        if !self.isCacheLoaded {
            let data = self.getStoredData()
            var loadedCache: [String: (url: String, localPath: String, quality: String)] = [:]
            for (key, entry) in data {
                if let url = entry["url"],
                   let localPath = entry["localPath"],
                   FileManager.default.fileExists(atPath: localPath) {
                    let quality = entry["quality"] ?? "720p"
                    loadedCache[key] = (url, localPath, quality)
                }
            }
            self.memoryCache = loadedCache
            self.isCacheLoaded = true
        }
        let cached = self.memoryCache[String(peerId)]
        self.cacheLock.unlock()

        if let cached = cached {
            return cached
        }
        if fallbackToGlobal && peerId != Self.globalWallpaperPeerId {
            return self.getWallpaper(for: Self.globalWallpaperPeerId, fallbackToGlobal: false)
        }
        return nil
    }

    // MARK: - Local Video Picker (Gallery / Files)

    public func setLocalWallpaper(from sourceUrl: URL, for peerId: Int64, customKey: String? = nil, completion: ((Bool, String?) -> Void)? = nil) {
        self.ensureDirectoryExists()
        let isSecurityScoped = sourceUrl.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                sourceUrl.stopAccessingSecurityScopedResource()
            }
        }

        let ext = sourceUrl.pathExtension.isEmpty ? "mp4" : sourceUrl.pathExtension
        let destinationFile = self.wallpapersDirectory.appendingPathComponent("\(peerId).\(ext)")

        do {
            if FileManager.default.fileExists(atPath: destinationFile.path) {
                try FileManager.default.removeItem(at: destinationFile)
            }
            try FileManager.default.copyItem(at: sourceUrl, to: destinationFile)

            self.queue.async {
                var data = self.getStoredData()
                let key = customKey ?? ("file://" + sourceUrl.lastPathComponent)
                data[String(peerId)] = [
                    "url": key,
                    "localPath": destinationFile.path,
                    "quality": "local"
                ]
                self.saveStoredData(data)

                DispatchQueue.main.async {
                    self.clearDownloading(for: peerId)
                    NotificationCenter.default.post(name: .doxChatWallpaperDidChange, object: nil, userInfo: ["peerId": peerId])
                    completion?(true, nil)
                }
            }
        } catch {
            self.clearDownloading(for: peerId)
            SGLogger.shared.log("SGDoxAnimatedWallpaperManager", "Local copy error: \(error.localizedDescription)")
            DispatchQueue.main.async {
                completion?(false, error.localizedDescription)
            }
        }
    }

    // MARK: - TikTok URL Detection & Resolution

    public func isTikTokUrl(_ urlString: String) -> Bool {
        guard let host = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines))?.host?.lowercased() else {
            return false
        }
        return host == "tiktok.com" || host.hasSuffix(".tiktok.com")
    }

    public func resolveTikTokUrl(_ urlString: String, completion: @escaping (String?, String?) -> Void) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let apiUrl = URL(string: "https://www.tikwm.com/api/?url=\(encoded)") else {
            completion(nil, "Invalid TikTok URL")
            return
        }

        var request = URLRequest(url: apiUrl)
        request.httpMethod = "GET"
        request.timeoutInterval = 15.0
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }
            if error != nil {
                self.resolveTikTokFallback(urlString: trimmed, completion: completion)
                return
            }
            guard let data = data else {
                self.resolveTikTokFallback(urlString: trimmed, completion: completion)
                return
            }
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let code = json["code"] as? Int, code == 0,
                   let dataObj = json["data"] as? [String: Any] {
                    let directUrl = (dataObj["hdplay"] as? String) ?? (dataObj["play"] as? String)
                    if let directUrl = directUrl, !directUrl.isEmpty {
                        completion(directUrl, nil)
                        return
                    }
                }
                self.resolveTikTokFallback(urlString: trimmed, completion: completion)
            } catch {
                self.resolveTikTokFallback(urlString: trimmed, completion: completion)
            }
        }
        task.resume()
    }

    private func resolveTikTokFallback(urlString: String, completion: @escaping (String?, String?) -> Void) {
        guard let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let apiUrl = URL(string: "https://api.tiklydown.eu.org/api/download?url=\(encoded)") else {
            completion(nil, "Не удалось распознать ссылку на TikTok")
            return
        }

        var request = URLRequest(url: apiUrl)
        request.httpMethod = "GET"
        request.timeoutInterval = 15.0
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")

        let task = URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                completion(nil, error.localizedDescription)
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let videoObj = json["video"] as? [String: Any],
                  let noWatermark = (videoObj["noWatermark"] as? String) ?? (videoObj["watermark"] as? String),
                  !noWatermark.isEmpty else {
                completion(nil, "Не удалось извлечь видео из TikTok. Проверьте ссылку.")
                return
            }
            completion(noWatermark, nil)
        }
        task.resume()
    }

    public func resolveVideoUrlIfNeeded(urlString: String, completion: @escaping (String?, String?) -> Void) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if self.isTikTokUrl(trimmed) {
            self.resolveTikTokUrl(trimmed, completion: completion)
        } else {
            completion(trimmed, nil)
        }
    }

    // MARK: - Download & Set Wallpaper
    
    public func setWallpaper(for peerId: Int64, urlString: String, quality: String, completion: @escaping (Bool, String?) -> Void) {
        let trimmedUrl = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedUrl), ["http", "https"].contains(url.scheme?.lowercased()) else {
            completion(false, "Invalid URL")
            return
        }

        self.markDownloading(for: peerId, url: trimmedUrl)
        self.resolveVideoUrlIfNeeded(urlString: trimmedUrl) { [weak self] resolvedUrlString, resolveError in
            guard let self = self else { return }
            guard let finalUrlString = resolvedUrlString, let finalUrl = URL(string: finalUrlString) else {
                self.clearDownloading(for: peerId)
                DispatchQueue.main.async {
                    completion(false, resolveError ?? "Не удалось получить видео по ссылке")
                }
                return
            }

            self.ensureDirectoryExists()
            let ext = finalUrl.pathExtension.isEmpty ? "mp4" : finalUrl.pathExtension
            let destinationFile = self.wallpapersDirectory.appendingPathComponent("\(peerId).\(ext)")

            var request = URLRequest(url: finalUrl)
            request.setValue("https://www.tiktok.com/", forHTTPHeaderField: "Referer")
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")

            let session = URLSession(configuration: .default)
            let task = session.downloadTask(with: request) { [weak self] tempUrl, _, error in
                guard let self = self else { return }

                if let error = error {
                    self.clearDownloading(for: peerId)
                    SGLogger.shared.log("SGDoxAnimatedWallpaperManager", "Download error: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        completion(false, error.localizedDescription)
                    }
                    return
                }

                guard let tempUrl = tempUrl else {
                    self.clearDownloading(for: peerId)
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
                            "directUrl": finalUrlString,
                            "localPath": destinationFile.path,
                            "quality": quality
                        ]
                        self.saveStoredData(data)

                        DispatchQueue.main.async {
                            self.clearDownloading(for: peerId)
                            NotificationCenter.default.post(name: .doxChatWallpaperDidChange, object: nil, userInfo: ["peerId": peerId])
                            completion(true, nil)
                        }
                    }
                } catch {
                    self.clearDownloading(for: peerId)
                    SGLogger.shared.log("SGDoxAnimatedWallpaperManager", "File error: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        completion(false, error.localizedDescription)
                    }
                }
            }
            task.resume()
        }
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

