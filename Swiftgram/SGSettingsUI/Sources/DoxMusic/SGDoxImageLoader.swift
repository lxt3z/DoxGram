import Foundation
import UIKit
import ImageIO
import CommonCrypto
import MediaPlayer

public final class SGDoxImageLoader: @unchecked Sendable {
    public static let shared = SGDoxImageLoader()

    /// Decoded-bitmap budget. Cost is width × height × 4, so this is real RAM, not JPEG size.
    private static let memoryBudgetBytes = 24 * 1024 * 1024
    /// On-disk artwork cap. Older files, including the pre-fix hash-named ones, are deleted past this.
    private static let diskBudgetBytes: Int64 = 80 * 1024 * 1024
    private static let maxPixelEdge: CGFloat = 600

    private let memoryCache = NSCache<NSString, UIImage>()
    private var placeholderCache: UIImage?
    private let session: URLSession
    private let ioQueue = DispatchQueue(label: "org.doxgram.artwork.cache", qos: .utility)
    
    private init() {
        self.memoryCache.countLimit = 40
        self.memoryCache.totalCostLimit = Self.memoryBudgetBytes
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15.0
        config.timeoutIntervalForResource = 30.0
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = URLCache(memoryCapacity: 2 * 1024 * 1024, diskCapacity: 0)
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
            "Accept": "image/webp,image/png,image/jpeg,image/*;q=0.8"
        ]
        self.session = URLSession(configuration: config)
        self.ioQueue.async { [weak self] in
            self?.trimDiskCache()
        }
        
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil) { [weak self] _ in
            self?.memoryCache.removeAllObjects()
            self?.placeholderCache = nil
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { [weak self] _ in
            self?.memoryCache.removeAllObjects()
        }
    }
    
    private func dispatchMain(image: UIImage?, completion: @escaping @MainActor (UIImage?) -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                completion(image)
            }
        } else {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    completion(image)
                }
            }
        }
    }
    
    private var diskCacheDirectory: URL? {
        let urls = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        guard let base = urls.first else { return nil }
        let dir = base.appendingPathComponent("DoxMusicArtwork", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    @discardableResult
    public func saveImageToDisk(_ image: UIImage, name: String) -> URL? {
        let prepared = self.scaledImage(image, maxPixel: Self.maxPixelEdge)
        guard let dir = self.diskCacheDirectory, let data = prepared.jpegData(compressionQuality: 0.82) else { return nil }
        let fileUrl = dir.appendingPathComponent(name)
        do {
            try data.write(to: fileUrl, options: .atomic)
            self.noteDiskWrite()
            return fileUrl
        } catch {
            return nil
        }
    }
    
    public func storeImage(_ image: UIImage, for key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        self.remember(image, forKey: trimmed as NSString)
    }
    
    public func cachedImage(for key: String) -> UIImage? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return self.memoryCache.object(forKey: trimmed as NSString)
    }
    
    private func diskFileName(for key: String) -> String {
        let data = Data(key.utf8)
        var buffer = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { raw in
            _ = CC_SHA256(raw.baseAddress, CC_LONG(data.count), &buffer)
        }
        let hex = buffer.map { String(format: "%02x", $0) }.joined()
        return "art_\(hex).jpg"
    }

    private func pixelEdge(for targetSize: CGSize?, scale: CGFloat) -> CGFloat {
        let screen = scale > 0 ? scale : 2
        let edge: CGFloat
        if let targetSize, targetSize.width > 1, targetSize.height > 1 {
            edge = max(targetSize.width, targetSize.height) * screen
        } else {
            edge = Self.maxPixelEdge
        }
        return min(Self.maxPixelEdge, max(64, edge))
    }

    private func sizedCacheKey(for key: String, maxPixel: CGFloat) -> NSString {
        return "\(Int(maxPixel.rounded()))|\(key)" as NSString
    }

    private func decodedCost(_ image: UIImage) -> Int {
        let width = image.size.width * image.scale
        let height = image.size.height * image.scale
        return Int(width * height * 4)
    }

    private func scaledImage(_ image: UIImage, maxPixel: CGFloat) -> UIImage {
        let pixelW = image.size.width * image.scale
        let pixelH = image.size.height * image.scale
        let maxSide = max(pixelW, pixelH)
        guard maxSide > maxPixel + 1, maxSide > 0 else {
            return image
        }
        let ratio = maxPixel / maxSide
        let newSize = CGSize(width: max(1, floor(pixelW * ratio)), height: max(1, floor(pixelH * ratio)))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private func remember(_ image: UIImage, forKey key: NSString) {
        let prepared = self.scaledImage(image, maxPixel: Self.maxPixelEdge)
        self.memoryCache.setObject(prepared, forKey: key, cost: self.decodedCost(prepared))
    }

    private func downsampledImage(data: Data, maxPixel: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        return self.thumbnail(from: source, maxPixel: maxPixel)
    }

    private func downsampledImage(at path: String, maxPixel: CGFloat) -> UIImage? {
        let url = URL(fileURLWithPath: path) as CFURL
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url, sourceOptions) else {
            return nil
        }
        return self.thumbnail(from: source, maxPixel: maxPixel)
    }

    private func thumbnail(from source: CGImageSource, maxPixel: CGFloat) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel)
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    private func noteDiskWrite() {
        self.ioQueue.async { [weak self] in
            self?.trimDiskCache()
        }
    }

    private func trimDiskCache() {
        guard let dir = self.diskCacheDirectory else {
            return
        }
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey], options: .skipsHiddenFiles) else {
            return
        }
        var entries: [(url: URL, size: Int64, date: Date)] = []
        var total: Int64 = 0
        for url in urls {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = Int64(values?.fileSize ?? 0)
            entries.append((url, size, values?.contentModificationDate ?? .distantPast))
            total += size
        }
        guard total > Self.diskBudgetBytes else {
            return
        }
        entries.sort { $0.date < $1.date }
        let target = Self.diskBudgetBytes * 4 / 5
        for entry in entries {
            if total <= target {
                break
            }
            try? fileManager.removeItem(at: entry.url)
            total -= entry.size
        }
    }

    private func writeImageToDisk(_ image: UIImage, fileName: String) {
        guard let dir = self.diskCacheDirectory, let data = image.jpegData(compressionQuality: 0.82) else {
            return
        }
        try? data.write(to: dir.appendingPathComponent(fileName), options: .atomic)
        self.noteDiskWrite()
    }

    public func loadImage(urlString: String, targetSize: CGSize? = nil, scale: CGFloat = 2.0, completion: @escaping @MainActor (UIImage?) -> Void) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            self.dispatchMain(image: nil, completion: completion)
            return
        }
        
        let maxPixel = self.pixelEdge(for: targetSize, scale: scale)
        let cacheKey = self.sizedCacheKey(for: trimmed, maxPixel: maxPixel)
        if let cached = self.memoryCache.object(forKey: cacheKey) {
            self.dispatchMain(image: cached, completion: completion)
            return
        }
        
        let fileName = self.diskFileName(for: cacheKey as String)
        if let dir = self.diskCacheDirectory {
            let diskPath = dir.appendingPathComponent(fileName).path
            if FileManager.default.fileExists(atPath: diskPath) {
                self.ioQueue.async { [weak self] in
                    guard let self = self else { return }
                    if let img = self.downsampledImage(at: diskPath, maxPixel: maxPixel) {
                        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: diskPath)
                        self.remember(img, forKey: cacheKey)
                        self.dispatchMain(image: img, completion: completion)
                    } else {
                        self.fetchRemoteImage(trimmed: trimmed, maxPixel: maxPixel, cacheKey: cacheKey, fileName: fileName, completion: completion)
                    }
                }
                return
            }
        }
        
        self.fetchRemoteImage(trimmed: trimmed, maxPixel: maxPixel, cacheKey: cacheKey, fileName: fileName, completion: completion)
    }

    private func fetchRemoteImage(trimmed: String, maxPixel: CGFloat, cacheKey: NSString, fileName: String, completion: @escaping @MainActor (UIImage?) -> Void) {
        if trimmed.hasPrefix("file://") {
            if let url = URL(string: trimmed) {
                self.ioQueue.async { [weak self] in
                    guard let self = self else { return }
                    if let img = self.downsampledImage(at: url.path, maxPixel: maxPixel) {
                        self.remember(img, forKey: cacheKey)
                        self.dispatchMain(image: img, completion: completion)
                    } else {
                        self.dispatchMain(image: nil, completion: completion)
                    }
                }
                return
            }
        }
        
        if trimmed.hasPrefix("am_local_") {
            let pidStr = trimmed.replacingOccurrences(of: "am_local_", with: "")
            if let pid = UInt64(pidStr) {
                self.ioQueue.async { [weak self] in
                    guard let self = self else { return }
                    
                    if let dir = self.diskCacheDirectory {
                        let diskPath = dir.appendingPathComponent("am_art_\(pid).jpg").path
                        if let img = self.downsampledImage(at: diskPath, maxPixel: maxPixel) {
                            self.remember(img, forKey: cacheKey)
                            self.dispatchMain(image: img, completion: completion)
                            return
                        }
                    }
                    
                    let query = MPMediaQuery.songs()
                    query.addFilterPredicate(MPMediaPropertyPredicate(value: NSNumber(value: pid), forProperty: MPMediaItemPropertyPersistentID))
                    var loadedImg: UIImage?
                    let point = max(64, maxPixel)
                    if let item = query.items?.first, let art = item.artwork?.image(at: CGSize(width: point, height: point)) {
                        self.remember(art, forKey: cacheKey)
                        self.saveImageToDisk(art, name: "am_art_\(pid).jpg")
                        loadedImg = art
                    }
                    self.dispatchMain(image: loadedImg, completion: completion)
                }
                return
            }
        }
        
        var effectiveUrl = trimmed
        if effectiveUrl.hasPrefix("http://") {
            effectiveUrl = "https://" + effectiveUrl.dropFirst(7)
        }
        let pixel = String(Int(maxPixel.rounded()))
        if effectiveUrl.contains("{w}") || effectiveUrl.contains("{h}") {
            effectiveUrl = effectiveUrl.replacingOccurrences(of: "{w}", with: pixel)
                .replacingOccurrences(of: "{h}", with: pixel)
                .replacingOccurrences(of: "{f}", with: "jpg")
        }
        
        guard let url = URL(string: effectiveUrl) else {
            self.dispatchMain(image: nil, completion: completion)
            return
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 15.0
        
        self.session.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil, let image = self.downsampledImage(data: data, maxPixel: maxPixel) else {
                var fallbackStr: String? = nil
                if effectiveUrl.contains("1200x1200") {
                    fallbackStr = effectiveUrl.replacingOccurrences(of: "1200x1200", with: "600x600")
                } else if effectiveUrl.contains("600x600") {
                    fallbackStr = effectiveUrl.replacingOccurrences(of: "600x600", with: "100x100")
                } else if effectiveUrl.contains("500x500") {
                    fallbackStr = effectiveUrl.replacingOccurrences(of: "500x500", with: "100x100")
                }
                if let fallbackStr = fallbackStr, let fallbackUrl = URL(string: fallbackStr) {
                    self?.session.dataTask(with: URLRequest(url: fallbackUrl)) { [weak self] fbData, _, _ in
                        guard let self = self else { return }
                        if let fbData = fbData, let fbImg = self.downsampledImage(data: fbData, maxPixel: maxPixel) {
                            self.remember(fbImg, forKey: cacheKey)
                            self.writeImageToDisk(fbImg, fileName: fileName)
                            self.dispatchMain(image: fbImg, completion: completion)
                        } else {
                            self.dispatchMain(image: nil, completion: completion)
                        }
                    }.resume()
                    return
                }
                
                self?.dispatchMain(image: nil, completion: completion)
                return
            }
            
            self.remember(image, forKey: cacheKey)
            self.writeImageToDisk(image, fileName: fileName)
            self.dispatchMain(image: image, completion: completion)
        }.resume()
    }
    
    public func loadArtwork(for track: SGDoxMusicTrack, targetSize: CGSize? = nil, completion: @escaping @MainActor (UIImage?) -> Void) {
        // 0. Check offline manager downloaded artwork
        if let offlineArtUrl = SGDoxMusicOfflineManager.shared.localArtworkUrl(for: track.id) {
            let maxPixel = self.pixelEdge(for: targetSize, scale: 2)
            let path = offlineArtUrl.path
            self.ioQueue.async { [weak self] in
                guard let self = self else { return }
                guard let img = self.downsampledImage(at: path, maxPixel: maxPixel) else {
                    self.dispatchMain(image: nil, completion: completion)
                    return
                }
                self.storeImage(img, for: track.id)
                if let artUrl = track.artworkUrl { self.storeImage(img, for: artUrl) }
                self.dispatchMain(image: img, completion: completion)
            }
            return
        }

        // 1. Direct memory cache check
        if let artUrl = track.artworkUrl, let cached = self.cachedImage(for: artUrl) {
            self.dispatchMain(image: cached, completion: completion)
            return
        }
        if let cached = self.cachedImage(for: track.id) {
            self.dispatchMain(image: cached, completion: completion)
            return
        }
        
        // 2. If valid remote/local URL
        if let artUrl = track.artworkUrl, !artUrl.isEmpty, !artUrl.hasPrefix("am_local_") {
            self.loadImage(urlString: artUrl, targetSize: targetSize) { [weak self] img in
                if let img = img {
                    self?.storeImage(img, for: track.id)
                    completion(img)
                } else {
                    self?.resolveArtwork(for: track, targetSize: targetSize, completion: completion)
                }
            }
            return
        }
        
        self.resolveArtwork(for: track, targetSize: targetSize, completion: completion)
    }
    
    private func resolveArtwork(for track: SGDoxMusicTrack, targetSize: CGSize? = nil, completion: @escaping @MainActor (UIImage?) -> Void) {
        // 1. Check disk cache
        if let dir = self.diskCacheDirectory {
            let pidStr = track.id.replacingOccurrences(of: "am_local_", with: "").replacingOccurrences(of: "local_", with: "")
            let candidates = ["am_art_\(track.id).jpg", "am_art_\(pidStr).jpg"]
            let maxPixel = self.pixelEdge(for: targetSize, scale: 2)
            for cand in candidates {
                let path = dir.appendingPathComponent(cand).path
                if FileManager.default.fileExists(atPath: path) {
                    self.ioQueue.async { [weak self] in
                        guard let self = self else { return }
                        guard let img = self.downsampledImage(at: path, maxPixel: maxPixel) else {
                            self.resolveArtworkFromLibrary(for: track, targetSize: targetSize, completion: completion)
                            return
                        }
                        self.storeImage(img, for: track.id)
                        if let artUrl = track.artworkUrl { self.storeImage(img, for: artUrl) }
                        self.dispatchMain(image: img, completion: completion)
                    }
                    return
                }
            }
        }
        
        self.resolveArtworkFromLibrary(for: track, targetSize: targetSize, completion: completion)
    }

    private func resolveArtworkFromLibrary(for track: SGDoxMusicTrack, targetSize: CGSize?, completion: @escaping @MainActor (UIImage?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            var foundLocalArt: UIImage?
            if track.id.hasPrefix("am_local_") || (track.appleMusicId?.hasPrefix("local_") == true) || (track.appleMusicId?.hasPrefix("am_local_") == true) {
                let pidStr = (track.id.hasPrefix("am_local_") ? track.id : (track.appleMusicId ?? track.id))
                    .replacingOccurrences(of: "am_local_", with: "")
                    .replacingOccurrences(of: "local_", with: "")
                if let pid = UInt64(pidStr) {
                    let query = MPMediaQuery.songs()
                    query.addFilterPredicate(MPMediaPropertyPredicate(value: NSNumber(value: pid), forProperty: MPMediaItemPropertyPersistentID))
                    if let item = query.items?.first {
                        let reqSize = targetSize ?? CGSize(width: 300, height: 300)
                        foundLocalArt = item.artwork?.image(at: reqSize) ?? item.artwork?.image(at: CGSize(width: 500, height: 500))
                    }
                }
            }
            
            // Fallback: match by title and artist in MPMediaQuery
            if foundLocalArt == nil {
                let query = MPMediaQuery.songs()
                if let songs = query.items {
                    let targetTitle = track.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    let targetArtist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if let matched = songs.first(where: { song in
                        guard let sTitle = song.title?.lowercased() else { return false }
                        if sTitle != targetTitle && !sTitle.contains(targetTitle) && !targetTitle.contains(sTitle) {
                            return false
                        }
                        if let sArtist = song.artist?.lowercased() {
                            return sArtist == targetArtist || sArtist.contains(targetArtist) || targetArtist.contains(sArtist)
                        }
                        return true
                    }) {
                        let reqSize = targetSize ?? CGSize(width: 300, height: 300)
                        foundLocalArt = matched.artwork?.image(at: reqSize) ?? matched.artwork?.image(at: CGSize(width: 500, height: 500))
                    }
                }
            }
            
            if let art = foundLocalArt {
                self.storeImage(art, for: track.id)
                if let diskUrl = self.saveImageToDisk(art, name: "am_art_\(track.id).jpg") {
                    SGDoxMusicManager.shared.updateTrackArtwork(trackId: track.id, newArtworkUrl: diskUrl.absoluteString)
                }
                self.dispatchMain(image: art, completion: completion)
                return
            }
            
            // 3. Fallback online search
            self.searchArtworkOnline(for: track, completion: completion)
        }
    }
    
    private func searchArtworkOnline(for track: SGDoxMusicTrack, completion: @escaping @MainActor (UIImage?) -> Void) {
        // If track has a direct Apple Music catalog ID, lookup directly
        if let appleId = track.appleMusicId, UInt64(appleId) != nil, !appleId.hasPrefix("local_"), !appleId.hasPrefix("am_local_") {
            let lookupUrlStr = "https://itunes.apple.com/lookup?id=\(appleId)&country=RU"
            if let lookupUrl = URL(string: lookupUrlStr) {
                self.session.dataTask(with: URLRequest(url: lookupUrl)) { [weak self] data, _, _ in
                    guard let self = self else { return }
                    if let data = data,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let results = json["results"] as? [[String: Any]],
                       let first = results.first,
                       let artUrl100 = first["artworkUrl100"] as? String {
                        let highRes = artUrl100.replacingOccurrences(of: "100x100bb", with: "600x600bb")
                        self.loadImage(urlString: highRes) { img in
                            if let img = img {
                                self.storeImage(img, for: track.id)
                                self.saveImageToDisk(img, name: "am_art_\(track.id).jpg")
                                SGDoxMusicManager.shared.updateTrackArtwork(trackId: track.id, newArtworkUrl: highRes)
                                completion(img)
                            } else {
                                self.searchByTitleArtistOnline(for: track, completion: completion)
                            }
                        }
                        return
                    }
                    self.searchByTitleArtistOnline(for: track, completion: completion)
                }.resume()
                return
            }
        }
        
        self.searchByTitleArtistOnline(for: track, completion: completion)
    }
    
    private func searchByTitleArtistOnline(for track: SGDoxMusicTrack, completion: @escaping @MainActor (UIImage?) -> Void) {
        var cleanTitle = track.title
        cleanTitle = cleanTitle.replacingOccurrences(of: "(?i)\\s*\\((?:feat|ft|with)\\..*?\\)", with: "", options: .regularExpression)
        cleanTitle = cleanTitle.replacingOccurrences(of: "(?i)\\s*\\[(?:feat|ft|with)\\..*?\\]", with: "", options: .regularExpression)
        cleanTitle = cleanTitle.replacingOccurrences(of: "(?i)\\s*-\\s*(?:Single|EP|Remix)", with: "", options: .regularExpression)
        cleanTitle = cleanTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = "\(track.artist) \(cleanTitle)".trimmingCharacters(in: .whitespacesAndNewlines)
        
        AppleMusicService.shared.searchITunesPublic(query: query) { [weak self] results, _ in
            guard let self = self else {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        completion(nil)
                    }
                }
                return
            }
            if let first = results.first(where: { $0.artworkUrl != nil }), let artUrl = first.artworkUrl {
                self.loadImage(urlString: artUrl) { img in
                    if let img = img {
                        self.storeImage(img, for: track.id)
                        if let old = track.artworkUrl { self.storeImage(img, for: old) }
                        self.saveImageToDisk(img, name: "am_art_\(track.id).jpg")
                        SGDoxMusicManager.shared.updateTrackArtwork(trackId: track.id, newArtworkUrl: artUrl)
                    }
                    completion(img)
                }
            } else {
                self.searchDeezerArtwork(for: track, query: query, completion: completion)
            }
        }
    }
    
    private func searchDeezerArtwork(for track: SGDoxMusicTrack, query: String, completion: @escaping @MainActor (UIImage?) -> Void) {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.deezer.com/search?q=\(encoded)&limit=5") else {
            self.dispatchMain(image: nil, completion: completion)
            return
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 8.0
        
        self.session.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["data"] as? [[String: Any]],
                  let first = items.first,
                  let album = first["album"] as? [String: Any] else {
                self?.dispatchMain(image: nil, completion: completion)
                return
            }
            
            let artUrl = (album["cover_xl"] as? String) ?? (album["cover_big"] as? String) ?? (album["cover_medium"] as? String) ?? (album["cover"] as? String)
            guard let validArtUrl = artUrl, !validArtUrl.isEmpty else {
                self.dispatchMain(image: nil, completion: completion)
                return
            }
            
            self.loadImage(urlString: validArtUrl) { img in
                if let img = img {
                    self.storeImage(img, for: track.id)
                    if let old = track.artworkUrl { self.storeImage(img, for: old) }
                    self.saveImageToDisk(img, name: "am_art_\(track.id).jpg")
                    SGDoxMusicManager.shared.updateTrackArtwork(trackId: track.id, newArtworkUrl: validArtUrl)
                }
                completion(img)
            }
        }.resume()
    }
    
    public func placeholderArtwork() -> UIImage {
        if let cached = self.placeholderCache {
            return cached
        }
        let size = CGSize(width: 80, height: 80)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let colors = [
                UIColor(red: 0.18, green: 0.18, blue: 0.22, alpha: 1.0).cgColor,
                UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1.0).cgColor
            ]
            let space = CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0.0, 1.0]) {
                ctx.cgContext.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size.height), options: [])
            }
            if let noteImage = UIImage(systemName: "music.note")?.withTintColor(UIColor(white: 1.0, alpha: 0.35), renderingMode: .alwaysOriginal) {
                let noteRect = CGRect(x: 24, y: 24, width: 32, height: 32)
                noteImage.draw(in: noteRect)
            }
        }
        self.placeholderCache = image
        return image
    }
}
