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
        
        // 1. If authorized with Apple Music, prioritize native MusicCatalogSearchRequest
        if self.isAuthorized {
            #if canImport(MusicKit)
            if #available(iOS 15.0, *) {
                Task {
                    do {
                        var request = MusicCatalogSearchRequest(term: trimmed, types: [Song.self, Artist.self])
                        request.limit = 25
                        let response = try await request.response()
                        
                        var musicKitTracks: [SGDoxMusicTrack] = []
                        
                        // If query matched an artist, surface their top songs at the top of the search!
                        if let artist = response.artists.first {
                            do {
                                let artistDetailed = try await artist.with([.topSongs])
                                if let topSongs = artistDetailed.topSongs {
                                    for song in topSongs {
                                        let artworkUrl = song.artwork?.url(width: 600, height: 600)?.absoluteString
                                        musicKitTracks.append(SGDoxMusicTrack(
                                            id: song.id.rawValue,
                                            title: song.title,
                                            artist: song.artistName,
                                            album: song.albumTitle ?? "",
                                            artworkUrl: artworkUrl,
                                            duration: song.duration ?? 0.0,
                                            previewUrl: song.previewAssets?.first?.url?.absoluteString,
                                            source: .appleMusic,
                                            appleMusicId: song.id.rawValue
                                        ))
                                    }
                                }
                            } catch {
                            }
                        }
                        
                        // Append matching songs (avoiding duplicates)
                        for song in response.songs {
                            if !musicKitTracks.contains(where: { $0.id == song.id.rawValue }) {
                                let artworkUrl = song.artwork?.url(width: 600, height: 600)?.absoluteString
                                musicKitTracks.append(SGDoxMusicTrack(
                                    id: song.id.rawValue,
                                    title: song.title,
                                    artist: song.artistName,
                                    album: song.albumTitle ?? "",
                                    artworkUrl: artworkUrl,
                                    duration: song.duration ?? 0.0,
                                    previewUrl: song.previewAssets?.first?.url?.absoluteString,
                                    source: .appleMusic,
                                    appleMusicId: song.id.rawValue
                                ))
                            }
                        }
                        
                        if !musicKitTracks.isEmpty {
                            DispatchQueue.main.async {
                                completion(musicKitTracks, nil)
                            }
                            return
                        }
                    } catch {
                    }
                    
                    // If MusicKit returned empty or failed, fallback to public iTunes search
                    self.searchITunesPublic(query: trimmed, completion: completion)
                }
                return
            }
            #endif
        }
        
        // 2. Fallback to public iTunes search
        self.searchITunesPublic(query: trimmed, completion: completion)
    }
    
    public func searchITunesPublic(query: String, completion: @escaping @Sendable ([SGDoxMusicTrack], String?) -> Void) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) else {
            completion([], "Invalid search query")
            return
        }
        
        let country = Locale.current.regionCode ?? "US"
        let songUrlString = "https://itunes.apple.com/search?term=\(encoded)&media=music&entity=song&limit=30&country=\(country)"
        let artistUrlString = "https://itunes.apple.com/search?term=\(encoded)&media=music&entity=musicArtist&limit=1&country=\(country)"
        
        guard let songUrl = URL(string: songUrlString) else {
            completion([], "Invalid URL")
            return
        }
        
        var songRequest = URLRequest(url: songUrl)
        songRequest.timeoutInterval = 10.0
        
        URLSession.shared.dataTask(with: songRequest) { [weak self] data, _, error in
            guard let self = self else { return }
            var songTracks: [SGDoxMusicTrack] = []
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let results = json["results"] as? [[String: Any]] {
                songTracks = self.parseITunesResults(results)
            }
            
            guard let artistUrl = URL(string: artistUrlString) else {
                DispatchQueue.main.async { completion(songTracks, error?.localizedDescription) }
                return
            }
            
            var artistRequest = URLRequest(url: artistUrl)
            artistRequest.timeoutInterval = 6.0
            URLSession.shared.dataTask(with: artistRequest) { aData, _, _ in
                if let aData = aData,
                   let aJson = try? JSONSerialization.jsonObject(with: aData) as? [String: Any],
                   let aResults = aJson["results"] as? [[String: Any]],
                   let firstArtist = aResults.first,
                   let artistId = (firstArtist["artistId"] as? Int64) ?? (firstArtist["artistId"] as? Int).map(Int64.init) {
                    
                    let lookupUrlString = "https://itunes.apple.com/lookup?id=\(artistId)&entity=song&limit=30&country=\(country)"
                    if let lookupUrl = URL(string: lookupUrlString) {
                        var lookupRequest = URLRequest(url: lookupUrl)
                        lookupRequest.timeoutInterval = 6.0
                        URLSession.shared.dataTask(with: lookupRequest) { lData, _, _ in
                            var artistTracks: [SGDoxMusicTrack] = []
                            if let lData = lData,
                               let lJson = try? JSONSerialization.jsonObject(with: lData) as? [String: Any],
                               let lResults = lJson["results"] as? [[String: Any]] {
                                let songResults = lResults.filter { ($0["wrapperType"] as? String) == "track" }
                                artistTracks = self.parseITunesResults(songResults)
                            }
                            
                            var combined = artistTracks
                            for t in songTracks {
                                if !combined.contains(where: { $0.id == t.id }) {
                                    combined.append(t)
                                }
                            }
                            
                            DispatchQueue.main.async {
                                completion(combined.isEmpty ? songTracks : combined, nil)
                            }
                        }.resume()
                        return
                    }
                }
                
                DispatchQueue.main.async {
                    completion(songTracks, nil)
                }
            }.resume()
        }.resume()
    }
    
    private func parseITunesResults(_ results: [[String: Any]]) -> [SGDoxMusicTrack] {
        return results.compactMap { item in
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
    }
    
    public func fetchUserPersonalMusic(completion: @escaping @Sendable ([SGDoxMusicTrack]) -> Void) {
        #if canImport(MusicKit)
        if #available(iOS 16.0, *) {
            if self.isAuthorized {
                Task {
                    do {
                        var recentRequest = MusicRecentlyPlayedRequest<Song>()
                        recentRequest.limit = 25
                        let recentResponse = try await recentRequest.response()
                        let recentSongs = recentResponse.items
                        
                        if !recentSongs.isEmpty {
                            let tracks: [SGDoxMusicTrack] = recentSongs.compactMap { song in
                                let artworkUrl = song.artwork?.url(width: 600, height: 600)?.absoluteString
                                return SGDoxMusicTrack(
                                    id: song.id.rawValue,
                                    title: song.title,
                                    artist: song.artistName,
                                    album: song.albumTitle ?? "",
                                    artworkUrl: artworkUrl,
                                    duration: song.duration ?? 0.0,
                                    previewUrl: song.previewAssets?.first?.url?.absoluteString,
                                    source: .appleMusic,
                                    appleMusicId: song.id.rawValue
                                )
                            }
                            DispatchQueue.main.async {
                                completion(tracks)
                            }
                            return
                        }
                        
                        var libraryRequest = MusicLibraryRequest<Song>()
                        libraryRequest.limit = 25
                        let libraryResponse = try await libraryRequest.response()
                        let librarySongs = libraryResponse.items
                        if !librarySongs.isEmpty {
                            let tracks: [SGDoxMusicTrack] = librarySongs.compactMap { song in
                                let artworkUrl = song.artwork?.url(width: 600, height: 600)?.absoluteString
                                return SGDoxMusicTrack(
                                    id: song.id.rawValue,
                                    title: song.title,
                                    artist: song.artistName,
                                    album: song.albumTitle ?? "",
                                    artworkUrl: artworkUrl,
                                    duration: song.duration ?? 0.0,
                                    previewUrl: song.previewAssets?.first?.url?.absoluteString,
                                    source: .appleMusic,
                                    appleMusicId: song.id.rawValue
                                )
                            }
                            DispatchQueue.main.async {
                                completion(tracks)
                            }
                            return
                        }
                    } catch {
                    }
                    DispatchQueue.main.async {
                        completion([])
                    }
                }
                return
            }
        }
        #endif
        DispatchQueue.main.async {
            completion([])
        }
    }
    
    public func fetchWaveTracks(basedOn track: SGDoxMusicTrack?, completion: @escaping @Sendable ([SGDoxMusicTrack]) -> Void) {
        if let track = track, !track.artist.isEmpty {
            self.search(query: track.artist) { tracks, _ in
                completion(tracks.filter { $0.id != track.id })
            }
        } else {
            self.fetchUserPersonalMusic { personalTracks in
                completion(personalTracks)
            }
        }
    }
    
    public func fetchLibrarySongs(limit: Int = 100, completion: @escaping @Sendable ([SGDoxMusicTrack]) -> Void) {
        #if canImport(MusicKit)
        if #available(iOS 16.0, *) {
            if self.isAuthorized {
                Task {
                    do {
                        var libraryRequest = MusicLibraryRequest<Song>()
                        libraryRequest.limit = min(limit, 100)
                        let libraryResponse = try await libraryRequest.response()
                        let librarySongs = libraryResponse.items
                        let tracks: [SGDoxMusicTrack] = librarySongs.compactMap { song in
                            let artworkUrl = song.artwork?.url(width: 600, height: 600)?.absoluteString
                            return SGDoxMusicTrack(
                                id: song.id.rawValue,
                                title: song.title,
                                artist: song.artistName,
                                album: song.albumTitle ?? "",
                                artworkUrl: artworkUrl,
                                duration: song.duration ?? 0.0,
                                previewUrl: song.previewAssets?.first?.url?.absoluteString,
                                source: .appleMusic,
                                appleMusicId: song.id.rawValue
                            )
                        }
                        if !tracks.isEmpty {
                            DispatchQueue.main.async {
                                completion(tracks)
                            }
                            return
                        }
                    } catch {
                    }
                }
            }
        }
        #endif
        
        DispatchQueue.global(qos: .userInitiated).async {
            let query = MPMediaQuery.songs()
            let items = query.items ?? []
            let tracks: [SGDoxMusicTrack] = Array(items.prefix(limit)).compactMap { item in
                guard let title = item.title, let artist = item.artist else { return nil }
                let album = item.albumTitle ?? ""
                let duration = item.playbackDuration
                let id = "\(item.persistentID)"
                return SGDoxMusicTrack(
                    id: "am_local_\(id)",
                    title: title,
                    artist: artist,
                    album: album,
                    artworkUrl: nil,
                    duration: duration,
                    previewUrl: nil,
                    source: .appleMusic,
                    appleMusicId: id
                )
            }
            DispatchQueue.main.async {
                completion(tracks)
            }
        }
    }
    
    public func addToLibrary(track: SGDoxMusicTrack, completion: @escaping @Sendable (Bool) -> Void) {
        guard let appleId = track.appleMusicId, !appleId.isEmpty else {
            completion(false)
            return
        }
        
        #if canImport(MusicKit)
        if #available(iOS 16.0, *) {
            Task {
                do {
                    let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(appleId))
                    let response = try await request.response()
                    if let song = response.items.first {
                        try await MusicLibrary.shared.add(song)
                        DispatchQueue.main.async { completion(true) }
                        return
                    }
                } catch {
                }
                
                MPMediaLibrary.default().addItem(withProductID: appleId) { _, error in
                    DispatchQueue.main.async { completion(error == nil) }
                }
            }
            return
        }
        #endif
        
        MPMediaLibrary.default().addItem(withProductID: appleId) { _, error in
            DispatchQueue.main.async { completion(error == nil) }
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
                player.setQueue(with: [appleMusicId])
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
