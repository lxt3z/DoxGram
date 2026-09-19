import Foundation
import UIKit

public final class SGDoxImageLoader: @unchecked Sendable {
    public static let shared = SGDoxImageLoader()
    
    private let memoryCache = NSCache<NSString, UIImage>()
    
    private init() {
        self.memoryCache.countLimit = 200
        self.memoryCache.totalCostLimit = 60 * 1024 * 1024 // 60 MB
    }
    
    public func loadImage(urlString: String, targetSize: CGSize? = nil, scale: CGFloat = 2.0, completion: @escaping @MainActor (UIImage?) -> Void) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
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
}
