import Foundation
import AVFoundation
import UIKit

public final class SGDoxMusicOfflineManager: @unchecked Sendable {
    public static let shared = SGDoxMusicOfflineManager()
    
    private let lock = NSLock()
    private var downloadedTrackMap: [String: SGDoxMusicTrack] = [:]
    public var onDownloadsChanged: (() -> Void)?
    
    private var offlineDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("DoxMusicOffline", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    private init() {
        self.loadMetadata()
    }
    
    private func sanitizeId(_ id: String) -> String {
        return id.components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: "_")
    }
    
    public func isDownloaded(trackId: String) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        let cleanId = self.sanitizeId(trackId)
        let filePath = self.offlineDirectory.appendingPathComponent("\(cleanId).mp3").path
        return self.downloadedTrackMap[trackId] != nil && FileManager.default.fileExists(atPath: filePath)
    }
    
    public func localAudioUrl(for trackId: String) -> URL? {
        self.lock.lock()
        defer { self.lock.unlock() }
        let cleanId = self.sanitizeId(trackId)
        let fileUrl = self.offlineDirectory.appendingPathComponent("\(cleanId).mp3")
        if FileManager.default.fileExists(atPath: fileUrl.path) {
            return fileUrl
        }
        return nil
    }
    
    public func localArtworkUrl(for trackId: String) -> URL? {
        self.lock.lock()
        defer { self.lock.unlock() }
        let cleanId = self.sanitizeId(trackId)
        let fileUrl = self.offlineDirectory.appendingPathComponent("\(cleanId).jpg")
        if FileManager.default.fileExists(atPath: fileUrl.path) {
            return fileUrl
        }
        return nil
    }
    
    public func localArtwork(for trackId: String) -> UIImage? {
        if let url = self.localArtworkUrl(for: trackId) {
            return UIImage(contentsOfFile: url.path)
        }
        return nil
    }
    
    public func downloadedTracks() -> [SGDoxMusicTrack] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return Array(self.downloadedTrackMap.values)
    }
    
    public func downloadTrack(track: SGDoxMusicTrack, completion: @escaping (Bool) -> Void) {
        if self.isDownloaded(trackId: track.id) {
            completion(true)
            return
        }
        
        let cleanId = self.sanitizeId(track.id)
        let destinationAudioUrl = self.offlineDirectory.appendingPathComponent("\(cleanId).mp3")
        let destinationArtworkUrl = self.offlineDirectory.appendingPathComponent("\(cleanId).jpg")
        
        let resolveAudioSource: (@escaping (URL?) -> Void) -> Void = { handler in
            if let preview = track.previewUrl, let url = URL(string: preview), !preview.isEmpty {
                handler(url)
                return
            }
            
            // Query Deezer search for MP3 audio preview
            let query = "\(track.artist) \(track.title)"
            guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let searchUrl = URL(string: "https://api.deezer.com/search?q=\(encoded)") else {
                handler(nil)
                return
            }
            
            let task = URLSession.shared.dataTask(with: searchUrl) { data, _, _ in
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let dataArray = json["data"] as? [[String: Any]],
                      let first = dataArray.first,
                      let previewStr = first["preview"] as? String,
                      let previewUrl = URL(string: previewStr) else {
                    handler(nil)
                    return
                }
                handler(previewUrl)
            }
            task.resume()
        }
        
        resolveAudioSource { [weak self] audioSourceUrl in
            guard let self = self, let sourceUrl = audioSourceUrl else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            let downloadTask = URLSession.shared.downloadTask(with: sourceUrl) { [weak self] tempUrl, _, error in
                guard let self = self, let tempUrl = tempUrl, error == nil else {
                    DispatchQueue.main.async { completion(false) }
                    return
                }
                
                do {
                    if FileManager.default.fileExists(atPath: destinationAudioUrl.path) {
                        try FileManager.default.removeItem(at: destinationAudioUrl)
                    }
                    try FileManager.default.moveItem(at: tempUrl, to: destinationAudioUrl)
                    
                    // Download artwork if available
                    if let art = track.artworkUrl, let artUrl = URL(string: art) {
                        let artTask = URLSession.shared.downloadTask(with: artUrl) { artTemp, _, _ in
                            if let artTemp = artTemp {
                                if FileManager.default.fileExists(atPath: destinationArtworkUrl.path) {
                                    try? FileManager.default.removeItem(at: destinationArtworkUrl)
                                }
                                try? FileManager.default.moveItem(at: artTemp, to: destinationArtworkUrl)
                            }
                        }
                        artTask.resume()
                    }
                    
                    var savedTrack = track
                    savedTrack.previewUrl = destinationAudioUrl.absoluteString
                    if FileManager.default.fileExists(atPath: destinationArtworkUrl.path) {
                        savedTrack.artworkUrl = destinationArtworkUrl.absoluteString
                    }
                    
                    self.lock.lock()
                    self.downloadedTrackMap[track.id] = savedTrack
                    self.saveMetadata()
                    self.lock.unlock()
                    
                    // Pre-fetch and cache lyrics for offline usage
                    SGDoxLyricsService.shared.fetchLyrics(for: savedTrack) { _ in }
                    
                    DispatchQueue.main.async {
                        self.onDownloadsChanged?()
                        completion(true)
                    }
                } catch {
                    DispatchQueue.main.async { completion(false) }
                }
            }
            downloadTask.resume()
        }
    }
    
    public func deleteTrack(trackId: String) {
        self.lock.lock()
        defer { self.lock.unlock() }
        
        let cleanId = self.sanitizeId(trackId)
        let audioUrl = self.offlineDirectory.appendingPathComponent("\(cleanId).mp3")
        let artUrl = self.offlineDirectory.appendingPathComponent("\(cleanId).jpg")
        
        try? FileManager.default.removeItem(at: audioUrl)
        try? FileManager.default.removeItem(at: artUrl)
        SGDoxLyricsService.shared.deleteLyrics(for: trackId)
        
        self.downloadedTrackMap.removeValue(forKey: trackId)
        self.saveMetadata()
        
        DispatchQueue.main.async {
            self.onDownloadsChanged?()
        }
    }
    
    private func loadMetadata() {
        if let data = UserDefaults.standard.data(forKey: "dox_music_downloaded_tracks_v1"),
           let tracks = try? JSONDecoder().decode([SGDoxMusicTrack].self, from: data) {
            for track in tracks {
                let cleanId = self.sanitizeId(track.id)
                let audioUrl = self.offlineDirectory.appendingPathComponent("\(cleanId).mp3")
                if FileManager.default.fileExists(atPath: audioUrl.path) {
                    self.downloadedTrackMap[track.id] = track
                }
            }
        }
    }
    
    private func saveMetadata() {
        let tracks = Array(self.downloadedTrackMap.values)
        if let data = try? JSONEncoder().encode(tracks) {
            UserDefaults.standard.set(data, forKey: "dox_music_downloaded_tracks_v1")
        }
    }
}
