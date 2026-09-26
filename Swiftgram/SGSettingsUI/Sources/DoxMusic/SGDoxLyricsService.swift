import Foundation
import UIKit

public struct SGDoxLyricsLine: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let timestamp: Double // seconds
    public let text: String
    
    public var time: Double {
        return self.timestamp
    }
    
    public init(timestamp: Double, text: String) {
        self.id = "\(timestamp)_\(text.hashValue)"
        self.timestamp = timestamp
        self.text = text
    }
}

public struct SGDoxLyrics: Equatable, Codable, Sendable {
    public let trackId: String
    public let plainText: String?
    public let lines: [SGDoxLyricsLine]
    
    public var plainLyrics: String? {
        return self.plainText
    }
    
    public var isSynced: Bool {
        return !self.lines.isEmpty
    }
    
    public init(trackId: String, plainText: String?, lines: [SGDoxLyricsLine]) {
        self.trackId = trackId
        self.plainText = plainText
        self.lines = lines
    }
}

public final class SGDoxLyricsService: @unchecked Sendable {
    public static let shared = SGDoxLyricsService()
    
    private let lock = NSLock()
    private var memoryCache: [String: SGDoxLyrics] = [:]
    private let session: URLSession
    
    private func dispatchMain(lyrics: SGDoxLyrics?, completion: @escaping @MainActor (SGDoxLyrics?) -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                completion(lyrics)
            }
        } else {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    completion(lyrics)
                }
            }
        }
    }
    
    private var diskCacheDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("DoxMusicLyrics", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12.0
        config.timeoutIntervalForResource = 20.0
        config.httpAdditionalHeaders = [
            "User-Agent": "DoxGram/1.0 (iOS; Apple-iPhone)"
        ]
        self.session = URLSession(configuration: config)
    }
    
    private func sanitizeId(_ id: String) -> String {
        return id.components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: "_")
    }
    
    public func cachedLyrics(for trackId: String) -> SGDoxLyrics? {
        self.lock.lock()
        if let cached = self.memoryCache[trackId] {
            self.lock.unlock()
            return cached
        }
        self.lock.unlock()
        
        let cleanId = self.sanitizeId(trackId)
        let fileUrl = self.diskCacheDirectory.appendingPathComponent("\(cleanId).json")
        if let data = try? Data(contentsOf: fileUrl),
           let lyrics = try? JSONDecoder().decode(SGDoxLyrics.self, from: data) {
            self.lock.lock()
            self.memoryCache[trackId] = lyrics
            self.lock.unlock()
            return lyrics
        }
        return nil
    }
    
    public func saveLyricsToDisk(_ lyrics: SGDoxLyrics) {
        self.lock.lock()
        self.memoryCache[lyrics.trackId] = lyrics
        self.lock.unlock()
        
        let cleanId = self.sanitizeId(lyrics.trackId)
        let fileUrl = self.diskCacheDirectory.appendingPathComponent("\(cleanId).json")
        if let data = try? JSONEncoder().encode(lyrics) {
            try? data.write(to: fileUrl, options: .atomic)
        }
    }
    
    public func deleteLyrics(for trackId: String) {
        self.lock.lock()
        self.memoryCache.removeValue(forKey: trackId)
        self.lock.unlock()
        
        let cleanId = self.sanitizeId(trackId)
        let fileUrl = self.diskCacheDirectory.appendingPathComponent("\(cleanId).json")
        try? FileManager.default.removeItem(at: fileUrl)
    }
    
    public func fetchLyrics(for track: SGDoxMusicTrack, completion: @escaping @MainActor (SGDoxLyrics?) -> Void) {
        // 1. Check local cache
        if let cached = self.cachedLyrics(for: track.id) {
            self.dispatchMain(lyrics: cached, completion: completion)
            return
        }
        
        let cleanTitle = track.title
            .replacingOccurrences(of: "\\(feat.*\\)", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "\\[feat.*\\]", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "\\(ft.*\\)", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "\\[ft.*\\]", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "\\(official.*\\)", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "\\[official.*\\]", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: ".mp3", with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            
        let cleanArtist = track.artist
            .replacingOccurrences(of: ",.*", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try LRCLIB exact get
        var components = URLComponents(string: "https://lrclib.net/api/get")
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "track_name", value: cleanTitle),
            URLQueryItem(name: "artist_name", value: cleanArtist)
        ]
        if !track.album.isEmpty {
            queryItems.append(URLQueryItem(name: "album_name", value: track.album))
        }
        if track.duration > 0 {
            queryItems.append(URLQueryItem(name: "duration", value: String(Int(track.duration))))
        }
        components?.queryItems = queryItems
        
        guard let getUrl = components?.url else {
            self.fallbackSearch(track: track, query: "\(cleanArtist) \(cleanTitle)", completion: completion)
            return
        }
        
        let task = self.session.dataTask(with: URLRequest(url: getUrl)) { [weak self] data, response, _ in
            guard let self = self else { return }
            
            if let http = response as? HTTPURLResponse, http.statusCode == 200, let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let lyrics = self.parseLyricsJson(json, trackId: track.id) {
                    self.saveLyricsToDisk(lyrics)
                    self.dispatchMain(lyrics: lyrics, completion: completion)
                    return
                }
            }
            
            // Fallback search
            self.fallbackSearch(track: track, query: "\(cleanArtist) \(cleanTitle)", completion: completion)
        }
        task.resume()
    }
    
    private func fallbackSearch(track: SGDoxMusicTrack, query: String, completion: @escaping @MainActor (SGDoxLyrics?) -> Void) {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchUrl = URL(string: "https://lrclib.net/api/search?q=\(encoded)") else {
            self.dispatchMain(lyrics: nil, completion: completion)
            return
        }
        
        let task = self.session.dataTask(with: URLRequest(url: searchUrl)) { [weak self] data, response, _ in
            guard let self = self else { return }
            
            if let http = response as? HTTPURLResponse, http.statusCode == 200, let data = data,
               let results = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let firstMatch = results.first(where: {
                   let synced = $0["syncedLyrics"] as? String
                   let plain = $0["plainLyrics"] as? String
                   return (synced != nil && !synced!.isEmpty) || (plain != nil && !plain!.isEmpty)
               }) ?? results.first {
                
                if let lyrics = self.parseLyricsJson(firstMatch, trackId: track.id) {
                    self.saveLyricsToDisk(lyrics)
                    self.dispatchMain(lyrics: lyrics, completion: completion)
                    return
                }
            }
            
            self.dispatchMain(lyrics: nil, completion: completion)
        }
        task.resume()
    }
    
    private func parseLyricsJson(_ json: [String: Any], trackId: String) -> SGDoxLyrics? {
        let syncedStr = json["syncedLyrics"] as? String
        let plainStr = json["plainLyrics"] as? String
        
        var lines: [SGDoxLyricsLine] = []
        if let synced = syncedStr, !synced.isEmpty {
            lines = self.parseLRC(synced)
        }
        
        let cleanPlain = plainStr?.trimmingCharacters(in: .whitespacesAndNewlines)
        if lines.isEmpty && (cleanPlain == nil || cleanPlain!.isEmpty) {
            return nil
        }
        
        return SGDoxLyrics(trackId: trackId, plainText: cleanPlain, lines: lines)
    }
    
    private func parseLRC(_ lrc: String) -> [SGDoxLyricsLine] {
        var result: [SGDoxLyricsLine] = []
        let rawLines = lrc.components(separatedBy: .newlines)
        
        // Regex pattern: \[(\d+):(\d+(?:\.\d+)?)\](.*)
        for line in rawLines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("[") else { continue }
            
            guard let closingBracketIndex = trimmed.firstIndex(of: Character("]")) else { continue }
            let timeString = String(trimmed[trimmed.index(after: trimmed.startIndex)..<closingBracketIndex])
            let text = String(trimmed[trimmed.index(after: closingBracketIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip metadata tags like [ar:Linkin Park], [ti:Numb]
            if timeString.contains(":") {
                let parts = timeString.components(separatedBy: ":")
                if parts.count == 2, let mins = Double(parts[0]), let secs = Double(parts[1]) {
                    let totalSeconds = mins * 60.0 + secs
                    if !text.isEmpty {
                        result.append(SGDoxLyricsLine(timestamp: totalSeconds, text: text))
                    }
                }
            }
        }
        
        return result.sorted { $0.timestamp < $1.timestamp }
    }
}
