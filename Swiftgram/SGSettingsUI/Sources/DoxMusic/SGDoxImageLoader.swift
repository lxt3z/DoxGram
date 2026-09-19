import Foundation
import UIKit
import MediaPlayer

public final class SGDoxImageLoader: @unchecked Sendable {
    public static let shared = SGDoxImageLoader()
    
    private let memoryCache = NSCache<NSString, UIImage>()
    private var placeholderCache: UIImage?
    
    private init() {
        self.memoryCache.countLimit = 300
        self.memoryCache.totalCostLimit = 80 * 1024 * 1024 // 80 MB
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
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    completion(nil)
                }
            }
            return
        }
        
        let cacheKey = trimmed as NSString
        if let cached = self.memoryCache.object(forKey: cacheKey) {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    completion(cached)
                }
            }
            return
        }
        
        // Handle local Apple Music library persistent IDs
        if trimmed.hasPrefix("am_local_") {
            let pidString = trimmed.replacingOccurrences(of: "am_local_", with: "")
            if let pid = UInt64(pidString) {
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    let query = MPMediaQuery.songs()
                    query.addFilterPredicate(MPMediaPropertyPredicate(value: pid, forProperty: MPMediaItemPropertyPersistentID))
                    if let item = query.items?.first, let art = item.artwork?.image(at: targetSize ?? CGSize(width: 300, height: 300)) {
                        self?.memoryCache.setObject(art, forKey: cacheKey)
                        DispatchQueue.main.async {
                            MainActor.assumeIsolated {
                                completion(art)
                            }
                        }
                    } else {
                        DispatchQueue.main.async {
                            MainActor.assumeIsolated {
                                completion(nil)
                            }
                        }
                    }
                }
                return
            }
        }
        
        guard let url = URL(string: trimmed) else {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    completion(nil)
                }
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 15.0
        
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil, let image = UIImage(data: data) else {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        completion(nil)
                    }
                }
                return
            }
            
            self.memoryCache.setObject(image, forKey: cacheKey, cost: data.count)
            
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    completion(image)
                }
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
            let rect = CGRect(origin: .zero, size: size)
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
