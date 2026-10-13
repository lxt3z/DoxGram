import Foundation
import AVFoundation
import Network

public enum SGDoxVideoQuality: String, CaseIterable, Sendable {
    case auto = "auto"
    case p1080 = "1080p"
    case p720 = "720p"
    case p480 = "480p"
    case off = "off"
    
    public var title: String {
        switch self {
        case .auto: return "Авто"
        case .p1080: return "1080p Full HD"
        case .p720: return "720p HD"
        case .p480: return "480p SD"
        case .off: return "Выключено"
        }
    }
    
    public var shortTitle: String {
        switch self {
        case .auto: return "Авто"
        case .p1080: return "1080p"
        case .p720: return "720p"
        case .p480: return "480p"
        case .off: return "Выкл"
        }
    }
}

public final class SGDoxVideoClipService: @unchecked Sendable {
    public static let shared = SGDoxVideoClipService()
    
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "org.swiftgram.doxmusic.video.network", qos: .utility)
    
    private var isWifi: Bool = true
    private var isConstrained: Bool = false
    private var isExpensive: Bool = false
    
    private var videoCache: [String: String] = [:]
    private let cacheLock = NSLock()
    private var activeQueries: [String: [(@MainActor (String?) -> Void)]] = [:]
    
    private func dispatchMain(videoUrl: String?, completion: @escaping @MainActor (String?) -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                completion(videoUrl)
            }
        } else {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    completion(videoUrl)
                }
            }
        }
    }
    
    public var preferredQuality: SGDoxVideoQuality {
        get {
            let saved = UserDefaults.standard.string(forKey: "dox_music_video_quality") ?? "auto"
            return SGDoxVideoQuality(rawValue: saved) ?? .auto
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "dox_music_video_quality")
            NotificationCenter.default.post(name: NSNotification.Name("SGDoxVideoQualityChanged"), object: nil)
        }
    }
    
    public var isVideoEnabled: Bool {
        return self.preferredQuality != .off
    }
    
    private init() {
        self.monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            self.isWifi = path.usesInterfaceType(.wifi)
            self.isConstrained = path.isConstrained
            self.isExpensive = path.isExpensive
        }
        self.monitor.start(queue: self.monitorQueue)
    }
    
    public func resolveEffectiveQuality() -> SGDoxVideoQuality {
        let pref = self.preferredQuality
        if pref != .auto {
            return pref
        }
        if self.isConstrained {
            return .p480
        } else if self.isWifi {
            return .p1080
        } else {
            return .p720
        }
    }
    
    public func applyQuality(to playerItem: AVPlayerItem) {
        let quality = self.resolveEffectiveQuality()
        switch quality {
        case .p1080:
            playerItem.preferredMaximumResolution = CGSize(width: 1920, height: 1080)
            playerItem.preferredPeakBitRate = 12_000_000
        case .p720:
            playerItem.preferredMaximumResolution = CGSize(width: 1280, height: 720)
            playerItem.preferredPeakBitRate = 4_500_000
        case .p480:
            playerItem.preferredMaximumResolution = CGSize(width: 854, height: 480)
            playerItem.preferredPeakBitRate = 1_500_000
        case .auto, .off:
            playerItem.preferredMaximumResolution = CGSize(width: 1280, height: 720)
            playerItem.preferredPeakBitRate = 4_500_000
        }
    }
    
    public func fetchVideoClip(for track: SGDoxMusicTrack, completion: @escaping @MainActor (String?) -> Void) {
        guard self.isVideoEnabled else {
            self.dispatchMain(videoUrl: nil, completion: completion)
            return
        }
        
        let trackKey = "\(track.artist.lowercased()) - \(track.title.lowercased())"
        
        self.cacheLock.lock()
        if let cached = self.videoCache[trackKey] {
            self.cacheLock.unlock()
            self.dispatchMain(videoUrl: cached.isEmpty ? nil : cached, completion: completion)
            return
        }
        
        if let directUrl = track.videoUrl, !directUrl.isEmpty {
            self.videoCache[trackKey] = directUrl
            self.cacheLock.unlock()
            self.dispatchMain(videoUrl: directUrl, completion: completion)
            return
        }
        
        if var callbacks = self.activeQueries[trackKey] {
            callbacks.append(completion)
            self.activeQueries[trackKey] = callbacks
            self.cacheLock.unlock()
            return
        } else {
            self.activeQueries[trackKey] = [completion]
            self.cacheLock.unlock()
        }
        
        let cleanArtist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTitle = track.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let countries = ["RU", "KZ", "US"]
        
        self.searchMusicVideoRecursive(artist: cleanArtist, title: cleanTitle, countries: countries, index: 0) { [weak self] videoUrl in
            guard let self = self else { return }
            self.cacheLock.lock()
            self.videoCache[trackKey] = videoUrl ?? ""
            let callbacks = self.activeQueries.removeValue(forKey: trackKey) ?? []
            self.cacheLock.unlock()
            
            for cb in callbacks {
                self.dispatchMain(videoUrl: videoUrl, completion: cb)
            }
        }
    }
    
    private static func normalizeForComparison(_ str: String) -> String {
        var s = str.lowercased()
        let regexPatterns = [
            "\\(.*?\\)",
            "\\[.*?\\]",
            "\\b(feat|ft|featuring|remix|prod|live)\\b.*"
        ]
        for pattern in regexPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                s = regex.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: s.utf16.count), withTemplate: "")
            }
        }
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        s = s.components(separatedBy: allowed.inverted).joined()
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func searchMusicVideoRecursive(artist: String, title: String, countries: [String], index: Int, completion: @escaping @Sendable (String?) -> Void) {
        guard index < countries.count else {
            completion(nil)
            return
        }
        
        let country = countries[index]
        let queryTerm = "\(artist) \(title)"
        guard let encoded = queryTerm.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&entity=musicVideo&limit=5&country=\(country)") else {
            self.searchMusicVideoRecursive(artist: artist, title: title, countries: countries, index: index + 1, completion: completion)
            return
        }
        
        var req = URLRequest(url: url)
        req.timeoutInterval = 4.0
        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            guard let self = self else { return }
            if let data = data, error == nil,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let results = json["results"] as? [[String: Any]] {
                let normTargetArtist = Self.normalizeForComparison(artist)
                let normTargetTitle = Self.normalizeForComparison(title)
                let targetArtistWords = normTargetArtist.split(separator: " ").filter { $0.count > 2 }

                for item in results {
                    guard let previewUrl = item["previewUrl"] as? String, !previewUrl.isEmpty else { continue }
                    let itemArtist = item["artistName"] as? String ?? ""
                    let itemTrack = item["trackName"] as? String ?? ""
                    let normItemArtist = Self.normalizeForComparison(itemArtist)
                    let normItemTrack = Self.normalizeForComparison(itemTrack)
                    
                    let artistMatches = normItemArtist.contains(normTargetArtist)
                        || normTargetArtist.contains(normItemArtist)
                        || targetArtistWords.contains(where: { normItemArtist.contains($0) })
                        
                    let titleMatches = normItemTrack.contains(normTargetTitle)
                        || normTargetTitle.contains(normItemTrack)
                        
                    if artistMatches && titleMatches {
                        completion(previewUrl)
                        return
                    }
                }
            }
            self.searchMusicVideoRecursive(artist: artist, title: title, countries: countries, index: index + 1, completion: completion)
        }.resume()
    }
}
