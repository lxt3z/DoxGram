import Foundation
import UIKit
import ImageIO

public final class SGDoxImageLoader: @unchecked Sendable {
    public static let shared = SGDoxImageLoader()
    
    private let memoryCache = NSCache<NSString, UIImage>()
    private let session: URLSession
    
    private init() {
        self.memoryCache.countLimit = 150
        self.memoryCache.totalCostLimit = 50 * 1024 * 1024 // 50 MB
        
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 20 * 1024 * 1024, diskCapacity: 100 * 1024 * 1024, diskPath: "dox_music_art_cache")
        config.requestCachePolicy = .returnCacheDataElseLoad
        self.session = URLSession(configuration: config)
    }
    
    public func loadImage(urlString: String, targetSize: CGSize? = nil, scale: CGFloat = 2.0, completion: @escaping @Sendable (UIImage?) -> Void) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            completion(nil)
            return
        }
        
        let cacheKey = targetSize != nil ? "\(trimmed)_\(Int(targetSize!.width))x\(Int(targetSize!.height))" : trimmed
        if let cached = self.memoryCache.object(forKey: cacheKey as NSString) {
            completion(cached)
            return
        }
        
        let request = URLRequest(url: url)
        self.session.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            DispatchQueue.global(qos: .userInitiated).async {
                let decodedImage: UIImage?
                if let target = targetSize, target.width > 0, target.height > 0 {
                    decodedImage = self.downsample(data: data, to: target, scale: scale)
                } else {
                    decodedImage = UIImage(data: data)
                }
                
                if let image = decodedImage {
                    let cost = Int(image.size.width * image.size.height * 4)
                    self.memoryCache.setObject(image, forKey: cacheKey as NSString, cost: cost)
                }
                
                DispatchQueue.main.async {
                    completion(decodedImage)
                }
            }
        }.resume()
    }
    
    private func downsample(data: Data, to targetSize: CGSize, scale: CGFloat) -> UIImage? {
        let maxDimension = max(targetSize.width, targetSize.height) * scale
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]
        
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let downsampledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            return UIImage(data: data)
        }
        
        return UIImage(cgImage: downsampledImage)
    }
}
