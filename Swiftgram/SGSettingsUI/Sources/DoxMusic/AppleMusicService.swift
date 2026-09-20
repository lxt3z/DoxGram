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
    private let player = MPMusicPlayerController.applicationMusicPlayer
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
        let cleanQuery = query
            .replacingOccurrences(of: " — ", with: " ")
            .replacingOccurrences(of: " – ", with: " ")
            .replacingOccurrences(of: " - ", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else {
            completion([], nil)
            return
        }
        
        // 1. If authorized with Apple Music, prioritize native MusicCatalogSearchRequest
        if self.isAuthorized {
            #if canImport(MusicKit)
            if #available(iOS 15.0, *) {
                Task {
                    do {
                        var request = MusicCatalogSearchRequest(term: cleanQuery, types: [Song.self, Artist.self, Album.self])
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
                        
                        // If query matched an album, add album tracks!
                        if let album = response.albums.first {
                            do {
                                let albumDetailed = try await album.with([.tracks])
                                if let tracks = albumDetailed.tracks {
                                    for song in tracks {
                                        if !musicKitTracks.contains(where: { $0.id == song.id.rawValue }) {
                                            let artworkUrl = song.artwork?.url(width: 600, height: 600)?.absoluteString
                                            musicKitTracks.append(SGDoxMusicTrack(
                                                id: song.id.rawValue,
                                                title: song.title,
                                                artist: song.artistName,
                                                album: albumDetailed.title,
                                                artworkUrl: artworkUrl,
                                                duration: song.duration ?? 0.0,
                                                previewUrl: song.previewAssets?.first?.url?.absoluteString,
                                                source: .appleMusic,
                                                appleMusicId: song.id.rawValue
                                            ))
                                        }
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
                    self.searchITunesPublic(query: cleanQuery, completion: completion)
                }
                return
            }
            #endif
        }
        
        // 2. Fallback to public iTunes search
        self.searchITunesPublic(query: cleanQuery, completion: completion)
    }
    
    public func searchITunesPublic(query: String, completion: @escaping @Sendable ([SGDoxMusicTrack], String?) -> Void) {
        let cleanQuery = query
            .replacingOccurrences(of: " — ", with: " ")
            .replacingOccurrences(of: " – ", with: " ")
            .replacingOccurrences(of: " - ", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let encoded = cleanQuery.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed), !encoded.isEmpty else {
            completion([], "Invalid search query")
            return
        }
        
        // Prioritize Russian storefront (RU) as requested, with fallback to device region
        let primaryCountry = "RU"
        self.performITunesSearch(term: encoded, country: primaryCountry) { [weak self] primaryResults, error in
            guard let self = self else { return }
            if !primaryResults.isEmpty {
                completion(primaryResults, nil)
                return
            }
            
            // If primary RU search yielded no results, fallback to device locale
            let deviceCountry: String
            if #available(iOS 16, *) {
                deviceCountry = Locale.current.region?.identifier ?? "US"
            } else {
                deviceCountry = Locale.current.regionCode ?? "US"
            }
            
            if deviceCountry != primaryCountry {
                self.performITunesSearch(term: encoded, country: deviceCountry) { fallbackResults, fallbackError in
                    completion(fallbackResults, fallbackError ?? error)
                }
            } else {
                completion([], error)
            }
        }
    }
    
    private func performITunesSearch(term: String, country: String, completion: @escaping @Sendable ([SGDoxMusicTrack], String?) -> Void) {
        let songUrlString = "https://itunes.apple.com/search?term=\(term)&media=music&entity=song&limit=40&country=\(country)"
        let artistUrlString = "https://itunes.apple.com/search?term=\(term)&media=music&entity=musicArtist&limit=1&country=\(country)"
        let albumUrlString = "https://itunes.apple.com/search?term=\(term)&media=music&entity=album&limit=1&country=\(country)"
        
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
            
            // Check album lookup if song results are sparse or album query was matched
            let checkAlbum: (@escaping @Sendable ([SGDoxMusicTrack]) -> Void) -> Void = { next in
                guard let albumUrl = URL(string: albumUrlString) else {
                    next([])
                    return
                }
                var albumRequest = URLRequest(url: albumUrl)
                albumRequest.timeoutInterval = 6.0
                URLSession.shared.dataTask(with: albumRequest) { albData, _, _ in
                    if let albData = albData,
                       let albJson = try? JSONSerialization.jsonObject(with: albData) as? [String: Any],
                       let albResults = albJson["results"] as? [[String: Any]],
                       let firstAlbum = albResults.first,
                       let collectionId = (firstAlbum["collectionId"] as? Int64) ?? (firstAlbum["collectionId"] as? Int).map(Int64.init),
                       let lookupUrl = URL(string: "https://itunes.apple.com/lookup?id=\(collectionId)&entity=song&limit=40&country=\(country)") {
                        var lookupRequest = URLRequest(url: lookupUrl)
                        lookupRequest.timeoutInterval = 6.0
                        URLSession.shared.dataTask(with: lookupRequest) { lData, _, _ in
                            var albumTracks: [SGDoxMusicTrack] = []
                            if let lData = lData,
                               let lJson = try? JSONSerialization.jsonObject(with: lData) as? [String: Any],
                               let lResults = lJson["results"] as? [[String: Any]] {
                                let tracksOnly = lResults.filter { ($0["wrapperType"] as? String) == "track" }
                                albumTracks = self.parseITunesResults(tracksOnly)
                            }
                            next(albumTracks)
                        }.resume()
                        return
                    }
                    next([])
                }.resume()
            }
            
            checkAlbum { [weak self] albumTracks in
                guard let self = self else { return }
                var merged = songTracks
                for at in albumTracks {
                    if !merged.contains(where: { $0.id == at.id }) {
                        merged.append(at)
                    }
                }
                
                guard let artistUrl = URL(string: artistUrlString) else {
                    DispatchQueue.main.async { completion(merged, error?.localizedDescription) }
                    return
                }
                
                var artistRequest = URLRequest(url: artistUrl)
                artistRequest.timeoutInterval = 6.0
                URLSession.shared.dataTask(with: artistRequest) { aData, _, _ in
                    if let aData = aData,
                       let aJson = try? JSONSerialization.jsonObject(with: aData) as? [String: Any],
                       let aResults = aJson["results"] as? [[String: Any]],
                       let firstArtist = aResults.first,
                       let artistId = (firstArtist["artistId"] as? Int64) ?? (firstArtist["artistId"] as? Int).map(Int64.init),
                       let lookupUrl = URL(string: "https://itunes.apple.com/lookup?id=\(artistId)&entity=song&limit=30&country=\(country)") {
                        var lookupRequest = URLRequest(url: lookupUrl)
                        lookupRequest.timeoutInterval = 6.0
                        URLSession.shared.dataTask(with: lookupRequest) { lData, _, _ in
                            var artistTracks: [SGDoxMusicTrack] = []
                            if let lData = lData,
                               let lJson = try? JSONSerialization.jsonObject(with: lData) as? [String: Any],
                               let lResults = lJson["results"] as? [[String: Any]] {
                                let tracksOnly = lResults.filter { ($0["wrapperType"] as? String) == "track" }
                                artistTracks = self.parseITunesResults(tracksOnly)
                            }
                            
                            var finalTracks = merged
                            for t in artistTracks {
                                if !finalTracks.contains(where: { $0.id == t.id }) {
                                    finalTracks.append(t)
                                }
                            }
                            
                            DispatchQueue.main.async {
                                completion(finalTracks.isEmpty ? merged : finalTracks, nil)
                            }
                        }.resume()
                        return
                    }
                    
                    DispatchQueue.main.async {
                        completion(merged, nil)
                    }
                }.resume()
            }
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
            let rawArtwork = (item["artworkUrl100"] as? String) ?? (item["artworkUrl60"] as? String)
            let artworkUrl = rawArtwork?.replacingOccurrences(of: "100x100bb", with: "600x600bb") ?? rawArtwork
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
                let localKey = "am_local_\(id)"
                
                if let art = item.artwork?.image(at: CGSize(width: 300, height: 300)) {
                    SGDoxImageLoader.shared.storeImage(art, for: localKey)
                }
                
                let storeId = item.playbackStoreID
                let effectiveId = (!storeId.isEmpty && storeId != "0") ? storeId : "local_\(id)"
                
                return SGDoxMusicTrack(
                    id: localKey,
                    title: title,
                    artist: artist,
                    album: album,
                    artworkUrl: localKey,
                    duration: duration,
                    previewUrl: nil,
                    source: .appleMusic,
                    appleMusicId: effectiveId
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
                self?.avPlayer?.pause()
                self?.avPlayer = nil
            }
            
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                
                let player = self.player
                if appleMusicId.hasPrefix("local_"), let pid = UInt64(appleMusicId.replacingOccurrences(of: "local_", with: "")) {
                    let query = MPMediaQuery.songs()
                    query.addFilterPredicate(MPMediaPropertyPredicate(value: pid, forProperty: MPMediaItemPropertyPersistentID))
                    player.setQueue(with: query)
                } else {
                    player.setQueue(with: [appleMusicId])
                }
                
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
        self.player.stop()
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
            self.player.pause()
        }
        self.avPlayer?.pause()
    }
    
    public func resume() {
        if self.isUsingSystemPlayer {
            self.player.play()
        } else {
            self.avPlayer?.play()
        }
    }
    
    public func seek(to seconds: Double) {
        if self.isUsingSystemPlayer {
            self.player.currentPlaybackTime = seconds
        } else {
            self.avPlayer?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        }
    }
    
    public var currentPlaybackTime: Double {
        if self.isUsingSystemPlayer {
            let time = self.player.currentPlaybackTime
            return (time.isFinite && !time.isNaN && time >= 0) ? time : 0.0
        }
        let seconds = self.avPlayer?.currentTime().seconds ?? 0.0
        return (seconds.isFinite && !seconds.isNaN && seconds >= 0) ? seconds : 0.0
    }
    
    public var playbackDuration: Double {
        if !self.isUsingSystemPlayer {
            let seconds = self.avPlayer?.currentItem?.duration.seconds ?? 0.0
            return (seconds.isFinite && !seconds.isNaN && seconds > 0) ? seconds : 0.0
        }
        return 0.0
    }
}
