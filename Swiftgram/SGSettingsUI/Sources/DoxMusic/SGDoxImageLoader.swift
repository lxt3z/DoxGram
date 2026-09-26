import Foundation
import UIKit
import MediaPlayer

public final class SGDoxImageLoader: @unchecked Sendable {
    public static let shared = SGDoxImageLoader()
    
    private let memoryCache = NSCache<NSString, UIImage>()
    private var placeholderCache: UIImage?
    private let session: URLSession
    
    private init() {
        self.memoryCache.countLimit = 500
        self.memoryCache.totalCostLimit = 120 * 1024 * 1024 // 120 MB
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15.0
        config.timeoutIntervalForResource = 30.0
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
            "Accept": "image/webp,image/png,image/jpeg,image/*;q=0.8"
        ]
        self.session = URLSession(configuration: config)
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
    
    public func saveImageToDisk(_ image: UIImage, name: String) -> URL? {
        guard let dir = self.diskCacheDirectory, let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        let fileUrl = dir.appendingPathComponent(name)
        do {
            try data.write(to: fileUrl, options: .atomic)
            return fileUrl
        } catch {
            return nil
        }
    }
    
    public func storeImage(_ image: UIImage, for key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        self.memoryCache.setObject(image, forKey: trimmed as NSString)
    }
    
    public func cachedImage(for key: String) -> UIImage? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return self.memoryCache.object(forKey: trimmed as NSString)
    }
    
    public func loadImage(urlString: String, targetSize: CGSize? = nil, scale: CGFloat = 2.0, completion: @escaping @MainActor (UIImage?) -> Void) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            self.dispatchMain(image: nil, completion: completion)
            return
        }
        
        let cacheKey = trimmed as NSString
        if let cached = self.memoryCache.object(forKey: cacheKey) {
            self.dispatchMain(image: cached, completion: completion)
            return
        }
        
        // Handle local file URLs
        if trimmed.hasPrefix("file://") {
            if let url = URL(string: trimmed) {
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    guard let self = self else { return }
                    if let img = UIImage(contentsOfFile: url.path) {
                        self.memoryCache.setObject(img, forKey: cacheKey)
                        self.dispatchMain(image: img, completion: completion)
                    } else {
                        self.dispatchMain(image: nil, completion: completion)
                    }
                }
                return
            }
        }
        
        // Handle local Apple Music library persistent IDs
        if trimmed.hasPrefix("am_local_") {
            let pidStr = trimmed.replacingOccurrences(of: "am_local_", with: "")
            if let pid = UInt64(pidStr) {
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    guard let self = self else { return }
                    
                    // Check disk cache first
                    if let dir = self.diskCacheDirectory {
                        let diskPath = dir.appendingPathComponent("am_art_\(pid).jpg").path
                        if let img = UIImage(contentsOfFile: diskPath) {
                            self.memoryCache.setObject(img, forKey: cacheKey)
                            self.dispatchMain(image: img, completion: completion)
                            return
                        }
                    }
                    
                    let query = MPMediaQuery.songs()
                    query.addFilterPredicate(MPMediaPropertyPredicate(value: NSNumber(value: pid), forProperty: MPMediaItemPropertyPersistentID))
                    var loadedImg: UIImage?
                    if let item = query.items?.first, let art = item.artwork?.image(at: targetSize ?? CGSize(width: 300, height: 300)) {
                        self.memoryCache.setObject(art, forKey: cacheKey)
                        let _ = self.saveImageToDisk(art, name: "am_art_\(pid).jpg")
                        loadedImg = art
                    }
                    self.dispatchMain(image: loadedImg, completion: completion)
                }
                return
            }
        }
        
        // Handle template URLs ({w}x{h} or {f}) from Apple Music / MusicKit
        var effectiveUrl = trimmed
        if effectiveUrl.contains("{w}") || effectiveUrl.contains("{h}") {
            effectiveUrl = effectiveUrl.replacingOccurrences(of: "{w}", with: "600")
                .replacingOccurrences(of: "{h}", with: "600")
                .replacingOccurrences(of: "{f}", with: "jpg")
        }
        
        guard let url = URL(string: effectiveUrl) else {
            self.dispatchMain(image: nil, completion: completion)
            return
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 15.0
        
        self.session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self, let data = data, error == nil, let image = UIImage(data: data) else {
                // If 600x600 failed, fallback to 100x100 if applicable
                if effectiveUrl.contains("600x600") {
                    let fallbackStr = effectiveUrl.replacingOccurrences(of: "600x600", with: "100x100")
                    if let fallbackUrl = URL(string: fallbackStr) {
                        self?.session.dataTask(with: URLRequest(url: fallbackUrl)) { [weak self] fbData, _, _ in
                            guard let self = self else { return }
                            if let fbData = fbData, let fbImg = UIImage(data: fbData) {
                                self.memoryCache.setObject(fbImg, forKey: cacheKey, cost: fbData.count)
                                self.dispatchMain(image: fbImg, completion: completion)
                            } else {
                                self.dispatchMain(image: nil, completion: completion)
                            }
                        }.resume()
                        return
                    }
                }
                
                self?.dispatchMain(image: nil, completion: completion)
                return
            }
            
            self.memoryCache.setObject(image, forKey: cacheKey, cost: data.count)
            self.dispatchMain(image: image, completion: completion)
        }.resume()
    }
    
    public func loadArtwork(for track: SGDoxMusicTrack, targetSize: CGSize? = nil, completion: @escaping @MainActor (UIImage?) -> Void) {
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
            for cand in candidates {
                let path = dir.appendingPathComponent(cand).path
                if let img = UIImage(contentsOfFile: path) {
                    self.storeImage(img, for: track.id)
                    if let artUrl = track.artworkUrl { self.storeImage(img, for: artUrl) }
                    self.dispatchMain(image: img, completion: completion)
                    return
                }
            }
        }
        
        // 2. Try local MPMediaLibrary by persistentID or (Title + Artist)
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
        if let appleId = track.appleMusicId, let _ = UInt64(appleId), !appleId.hasPrefix("local_"), !appleId.hasPrefix("am_local_") {
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
                                let _ = self.saveImageToDisk(img, name: "am_art_\(track.id).jpg")
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
                        let _ = self.saveImageToDisk(img, name: "am_art_\(track.id).jpg")
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
                    let _ = self.saveImageToDisk(img, name: "am_art_\(track.id).jpg")
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
