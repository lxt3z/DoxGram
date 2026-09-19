import Foundation
import StoreKit
import MediaPlayer
import AVFoundation
#if canImport(MusicKit)
import MusicKit
#endif

public final class AppleMusicService: @unchecked Sendable {
    public static let shared = AppleMusicService()
    
    public enum AuthStatus: String {
        case authorized
        case denied
        case notDetermined
        case restricted
    }
    
    private var avPlayer: AVPlayer?
    private var systemPlayer: MPMusicPlayerController {
        return MPMusicPlayerController.systemMusicPlayer
    }
    public private(set) var isUsingSystemPlayer = false
    
    private init() {}
    
    public var isAuthorized: Bool {
        if #available(iOS 15.0, *) {
            #if canImport(MusicKit)
            return MusicKit.MusicAuthorization.currentStatus == .authorized
            #else
            return SKCloudServiceController.authorizationStatus() == .authorized
            #endif
        } else {
            return SKCloudServiceController.authorizationStatus() == .authorized
        }
    }
    
    public func requestAuthorization(completion: @escaping @Sendable (Bool) -> Void) {
        if #available(iOS 15.0, *) {
            #if canImport(MusicKit)
            Task {
                let status = await MusicKit.MusicAuthorization.request()
                DispatchQueue.main.async {
                    completion(status == .authorized)
                }
            }
            return
            #endif
        }
        SKCloudServiceController.requestAuthorization { status in
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }
    
    public func search(query: String, completion: @escaping @Sendable ([SGDoxMusicTrack], String?) -> Void) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion([], nil)
            return
        }
        
        self.searchITunesPublic(query: trimmed) { [weak self] tracks, error in
            if !tracks.isEmpty {
                completion(tracks, nil)
            } else if let self = self, self.isAuthorized {
                #if canImport(MusicKit)
                if #available(iOS 15.0, *) {
                    Task {
                        do {
                            var request = MusicCatalogSearchRequest(term: trimmed, types: [Song.self])
                            request.limit = 30
                            let response = try await request.response()
                            
                            let musicKitTracks: [SGDoxMusicTrack] = response.songs.map { song in
                                let artworkUrl = song.artwork?.url(width: 600, height: 600)?.absoluteString
                                let duration = song.duration ?? 0.0
                                let previewUrl = song.previewAssets?.first?.url?.absoluteString
                                
                                return SGDoxMusicTrack(
                                    id: song.id.rawValue,
                                    title: song.title,
                                    artist: song.artistName,
                                    album: song.albumTitle ?? "",
                                    artworkUrl: artworkUrl,
                                    duration: duration,
                                    previewUrl: previewUrl,
                                    source: .appleMusic,
                                    appleMusicId: song.id.rawValue
                                )
                            }
                            DispatchQueue.main.async {
                                completion(musicKitTracks, nil)
                            }
                        } catch {
                            DispatchQueue.main.async {
                                completion([], error.localizedDescription)
                            }
                        }
                    }
                    return
                }
                #endif
                completion([], error)
            } else {
                completion([], error)
            }
        }
    }
    
    public func searchITunesPublic(query: String, completion: @escaping @Sendable ([SGDoxMusicTrack], String?) -> Void) {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) else {
            completion([], "Invalid search query")
            return
        }
        
        let country = Locale.current.regionCode ?? "RU"
        let urlString = "https://itunes.apple.com/search?term=\(encoded)&media=music&entity=song&limit=30&country=\(country)"
        guard let url = URL(string: urlString) else {
            completion([], "Invalid URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12.0
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                DispatchQueue.main.async { completion([], error.localizedDescription) }
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]] else {
                DispatchQueue.main.async { completion([], nil) }
                return
            }
            
            let tracks: [SGDoxMusicTrack] = results.compactMap { item in
                guard let trackId = (item["trackId"] as? Int64) ?? (item["trackId"] as? Int).map(Int64.init),
                      let title = item["trackName"] as? String,
                      let artist = item["artistName"] as? String else {
                    return nil
                }
                let album = item["collectionName"] as? String ?? ""
                let artwork100 = item["artworkUrl100"] as? String
                let artworkUrl = artwork100?.replacingOccurrences(of: "100x100bb", with: "600x600bb") ?? artwork100
                let previewUrl = item["previewUrl"] as? String
                let durationMs = item["trackTimeMillis"] as? Double ?? 30000.0
                let duration = durationMs / 1000.0
                
                return SGDoxMusicTrack(
                    id: "am_\(trackId)",
                    title: title,
                    artist: artist,
                    album: album,
                    artworkUrl: artworkUrl,
                    duration: duration,
                    previewUrl: previewUrl,
                    source: .appleMusic,
                    appleMusicId: "\(trackId)"
                )
            }
            
            DispatchQueue.main.async {
                completion(tracks, nil)
            }
        }.resume()
    }
    
    public func fetchWaveTracks(basedOn track: SGDoxMusicTrack?, completion: @escaping @Sendable ([SGDoxMusicTrack]) -> Void) {
        let query = (track?.artist.isEmpty == false) ? track!.artist : "Top Hits"
        self.search(query: query) { tracks, _ in
            if let track = track {
                completion(tracks.filter { $0.id != track.id })
            } else {
                completion(tracks)
            }
        }
    }
    
    // MARK: - Playback (Full Songs via MPMusicPlayerController or Preview)
    
    public func play(track: SGDoxMusicTrack, completion: @escaping @Sendable (Bool) -> Void) {
        // Attempt full playback via official Apple Music player first
        if let appleMusicId = track.appleMusicId, !appleMusicId.isEmpty {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.avPlayer?.pause()
                self.avPlayer = nil
                
                let player = self.systemPlayer
                player.setQueue(withStoreIDs: [appleMusicId])
                player.prepareToPlay { [weak self] error in
                    DispatchQueue.main.async {
                        if error == nil {
                            player.play()
                            self?.isUsingSystemPlayer = true
                            completion(true)
                        } else {
                            // Fallback to preview stream
                            self?.isUsingSystemPlayer = false
                            if let preview = track.previewUrl, let url = URL(string: preview) {
                                self?.playPreview(url: url, completion: completion)
                            } else {
                                completion(false)
                            }
                        }
                    }
                }
            }
            return
        }
        
        if let preview = track.previewUrl, let url = URL(string: preview) {
            self.isUsingSystemPlayer = false
            self.playPreview(url: url, completion: completion)
        } else {
            completion(false)
        }
    }
    
    private func playPreview(url: URL, completion: @escaping @Sendable (Bool) -> Void) {
        self.systemPlayer.stop()
        self.isUsingSystemPlayer = false
        self.avPlayer?.pause()
        let playerItem = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: playerItem)
        self.avPlayer = player
        player.play()
        DispatchQueue.main.async {
            completion(true)
        }
    }
    
    public func pause() {
        if self.isUsingSystemPlayer {
            self.systemPlayer.pause()
        }
        self.avPlayer?.pause()
    }
    
    public func resume() {
        if self.isUsingSystemPlayer {
            self.systemPlayer.play()
        } else {
            self.avPlayer?.play()
        }
    }
    
    public var currentPlaybackTime: Double {
        if self.isUsingSystemPlayer {
            let time = self.systemPlayer.currentPlaybackTime
            return time.isNaN ? 0.0 : time
        }
        let seconds = self.avPlayer?.currentTime().seconds ?? 0.0
        return seconds.isNaN ? 0.0 : seconds
    }
    
    public var playbackDuration: Double {
        if self.isUsingSystemPlayer, let duration = self.systemPlayer.nowPlayingItem?.playbackDuration, duration > 0 {
            return duration
        }
        let seconds = self.avPlayer?.currentItem?.duration.seconds ?? 0.0
        return seconds.isNaN ? 0.0 : seconds
    }
}
