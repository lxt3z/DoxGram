import Foundation
import StoreKit
import MediaPlayer
import AVFoundation
#if canImport(MusicKit)
import MusicKit
#endif

public final class AppleMusicService {
    public static let shared = AppleMusicService()
    
    public enum AuthStatus: String {
        case authorized
        case denied
        case notDetermined
        case restricted
    }
    
    private var avPlayer: AVPlayer?
    
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
    
    public func requestAuthorization(completion: @escaping (Bool) -> Void) {
        if #available(iOS 15.0, *) {
            #if canImport(MusicKit)
            Task {
                let status = await MusicKit.MusicAuthorization.request()
                DispatchQueue.main.async {
                    completion(status == .authorized)
                }
            }
            #else
            SKCloudServiceController.requestAuthorization { status in
                DispatchQueue.main.async {
                    completion(status == .authorized)
                }
            }
            #endif
        } else {
            SKCloudServiceController.requestAuthorization { status in
                DispatchQueue.main.async {
                    completion(status == .authorized)
                }
            }
        }
    }
    
    public func search(query: String, completion: @escaping ([SGDoxMusicTrack], String?) -> Void) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion([], nil)
            return
        }
        
        if #available(iOS 15.0, *) {
            #if canImport(MusicKit)
            Task {
                do {
                    var request = MusicCatalogSearchRequest(term: trimmed, types: [Song.self])
                    request.limit = 25
                    let response = try await request.response()
                    
                    let tracks: [SGDoxMusicTrack] = response.songs.map { song in
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
                        completion(tracks, nil)
                    }
                } catch {
                    DispatchQueue.main.async {
                        completion([], error.localizedDescription)
                    }
                }
            }
            #else
            completion([], "MusicKit is not supported in this build")
            #endif
        } else {
            completion([], "Apple Music integration requires iOS 15.0 or newer")
        }
    }
    
    public func fetchWaveTracks(basedOn track: SGDoxMusicTrack?, completion: @escaping ([SGDoxMusicTrack]) -> Void) {
        if #available(iOS 15.0, *) {
            #if canImport(MusicKit)
            Task {
                do {
                    var request = MusicPersonalRecommendationsRequest()
                    request.limit = 10
                    let response = try await request.response()
                    
                    var tracks: [SGDoxMusicTrack] = []
                    for recommendation in response.recommendations {
                        for item in recommendation.items {
                            if case let .song(song) = item {
                                let artworkUrl = song.artwork?.url(width: 600, height: 600)?.absoluteString
                                let duration = song.duration ?? 0.0
                                let previewUrl = song.previewAssets?.first?.url?.absoluteString
                                tracks.append(SGDoxMusicTrack(
                                    id: song.id.rawValue,
                                    title: song.title,
                                    artist: song.artistName,
                                    album: song.albumTitle ?? "",
                                    artworkUrl: artworkUrl,
                                    duration: duration,
                                    previewUrl: previewUrl,
                                    source: .appleMusic,
                                    appleMusicId: song.id.rawValue
                                ))
                            }
                        }
                    }
                    
                    if tracks.isEmpty, let track = track {
                        // Fallback search with artist for wave
                        self.search(query: track.artist) { artistTracks, _ in
                            completion(artistTracks.filter { $0.id != track.id })
                        }
                        return
                    }
                    
                    DispatchQueue.main.async {
                        completion(tracks)
                    }
                } catch {
                    if let track = track {
                        self.search(query: track.artist) { artistTracks, _ in
                            completion(artistTracks.filter { $0.id != track.id })
                        }
                    } else {
                        DispatchQueue.main.async {
                            completion([])
                        }
                    }
                }
            }
            #else
            completion([])
            #endif
        } else {
            completion([])
        }
    }
    
    public func play(track: SGDoxMusicTrack, completion: @escaping (Bool) -> Void) {
        if #available(iOS 15.0, *) {
            #if canImport(MusicKit)
            guard let appleMusicId = track.appleMusicId else {
                completion(false)
                return
            }
            Task {
                do {
                    let songId = MusicItemID(appleMusicId)
                    let songRequest = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: songId)
                    let songResponse = try await songRequest.response()
                    if let song = songResponse.items.first {
                        let player = ApplicationMusicPlayer.shared
                        player.queue = [song]
                        try await player.play()
                        DispatchQueue.main.async {
                            completion(true)
                        }
                        return
                    }
                } catch {
                    // Fallback to preview stream
                    if let preview = track.previewUrl, let url = URL(string: preview) {
                        self.playPreview(url: url, completion: completion)
                        return
                    }
                    DispatchQueue.main.async {
                        completion(false)
                    }
                }
            }
            #else
            if let preview = track.previewUrl, let url = URL(string: preview) {
                self.playPreview(url: url, completion: completion)
            } else {
                completion(false)
            }
            #endif
        } else if let preview = track.previewUrl, let url = URL(string: preview) {
            self.playPreview(url: url, completion: completion)
        } else {
            completion(false)
        }
    }
    
    private func playPreview(url: URL, completion: @escaping (Bool) -> Void) {
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
        if #available(iOS 15.0, *) {
            #if canImport(MusicKit)
            ApplicationMusicPlayer.shared.pause()
            #endif
        }
        self.avPlayer?.pause()
    }
    
    public func resume() {
        if #available(iOS 15.0, *) {
            #if canImport(MusicKit)
            Task {
                try? await ApplicationMusicPlayer.shared.play()
            }
            #endif
        }
        self.avPlayer?.play()
    }
}
