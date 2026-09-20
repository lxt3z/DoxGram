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
