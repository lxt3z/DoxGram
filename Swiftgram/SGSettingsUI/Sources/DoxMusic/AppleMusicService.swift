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
    public private(set) var currentTrack: SGDoxMusicTrack?
    public var onTrackDidFinish: (() -> Void)?
    public var onPlaybackFailed: ((SGDoxMusicTrack) -> Void)?

    private var canPlayCatalogContent: Bool?
    private var playbackStartWatchdogTimer: Foundation.Timer?
    private var isObservingPlayerState = false
    private var isDeezerPreviewActive = false
    private var isPreparing = false
    private var lastSeekTime: Double?
    private var lastSeekTimestamp: Double = 0.0
    private var activePlayGeneration: Int = 0

    private init() {
        self.setupPlayerNotifications()
        self.setupLibraryNotifications()
        self.checkCatalogSubscription()
    }

    private func checkCatalogSubscription() {
        SKCloudServiceController().requestCapabilities { [weak self] capabilities, error in
            let canPlay = (error == nil) && capabilities.contains(.musicCatalogPlayback)
            self?.canPlayCatalogContent = canPlay
        }
    }

    private func setupPlayerNotifications() {
        guard !self.isObservingPlayerState else { return }
        self.isObservingPlayerState = true
        self.player.beginGeneratingPlaybackNotifications()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.playerStateDidChange),
            name: .MPMusicPlayerControllerPlaybackStateDidChange,
            object: self.player
        )
    }

    private func setupLibraryNotifications() {
        MPMediaLibrary.default().beginGeneratingLibraryChangeNotifications()
        NotificationCenter.default.addObserver(
            forName: .MPMediaLibraryDidChange,
            object: nil,
            queue: .main
        ) { _ in
            SGDoxMusicManager.shared.syncFavoritesWithServices()
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            SGDoxMusicManager.shared.syncFavoritesWithServices()
        }
    }

    @objc private func playerStateDidChange() {
        // Track state observation if needed, without false-positive fallbacks
    }
    
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
                completion(AppleMusicService.deduplicateTracks(primaryResults), nil)
                return
            }
            
            // If primary RU search yielded no results, fallback to KZ (complete CIS catalog for Russian artists like PHARAOH)
            self.performITunesSearch(term: encoded, country: "KZ") { [weak self] kzResults, _ in
                guard let self = self else { return }
                if !kzResults.isEmpty {
                    completion(AppleMusicService.deduplicateTracks(kzResults), nil)
                    return
                }
                
                // Fallback to device locale / US
                let deviceCountry: String
                if #available(iOS 16, *) {
                    deviceCountry = Locale.current.region?.identifier ?? "US"
                } else {
                    deviceCountry = Locale.current.regionCode ?? "US"
                }
                
                if deviceCountry != primaryCountry && deviceCountry != "KZ" {
                    self.performITunesSearch(term: encoded, country: deviceCountry) { fallbackResults, fallbackError in
                        completion(AppleMusicService.deduplicateTracks(fallbackResults), fallbackError ?? error)
                    }
                } else {
                    completion([], error)
                }
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
            let initialSongTracks: [SGDoxMusicTrack]
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let results = json["results"] as? [[String: Any]] {
                initialSongTracks = self.parseITunesResults(results)
            } else {
                initialSongTracks = []
            }
            let songTracks = initialSongTracks
            
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
                                completion(AppleMusicService.deduplicateTracks(finalTracks.isEmpty ? merged : finalTracks), nil)
                            }
                        }.resume()
                        return
                    }
                    
                    DispatchQueue.main.async {
                        completion(AppleMusicService.deduplicateTracks(merged), nil)
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
                
                var artUrlString = localKey
                if let art = item.artwork?.image(at: CGSize(width: 300, height: 300)) {
                    if let diskUrl = SGDoxImageLoader.shared.saveImageToDisk(art, name: "am_art_\(id).jpg") {
                        artUrlString = diskUrl.absoluteString
                    } else {
                        SGDoxImageLoader.shared.storeImage(art, for: localKey)
                    }
                }
                
                let storeId = item.playbackStoreID
                let effectiveId = (!storeId.isEmpty && storeId != "0") ? storeId : "local_\(id)"
                let assetUrl = item.value(forProperty: MPMediaItemPropertyAssetURL) as? URL
                
                return SGDoxMusicTrack(
                    id: localKey,
                    title: title,
                    artist: artist,
                    album: album,
                    artworkUrl: artUrlString,
                    duration: duration,
                    previewUrl: assetUrl?.absoluteString,
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
            }
        }
        #endif
        
        MPMediaLibrary.default().addItem(withProductID: appleId) { _, error in
            DispatchQueue.main.async { completion(error == nil) }
        }
    }
    
    public static func deduplicateTracks(_ tracks: [SGDoxMusicTrack]) -> [SGDoxMusicTrack] {
        var seenIds = Set<String>()
        var seenKeys = Set<String>()
        var result: [SGDoxMusicTrack] = []
        
        for t in tracks {
            if seenIds.contains(t.id) { continue }
            
            let normTitle = t.title.lowercased()
                .replacingOccurrences(of: "\\(feat.*\\)", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\[feat.*\\]", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\(bonus.*\\)", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\[bonus.*\\]", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\(remaster.*\\)", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\(deluxe.*\\)", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let normArtist = t.artist.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let key = "\(normArtist) - \(normTitle)"
            
            if seenKeys.contains(key) { continue }
            
            seenIds.insert(t.id)
            seenKeys.insert(key)
            result.append(t)
        }
        return result
    }
    
    // MARK: - Playback (Full Songs via MPMusicPlayerController or Preview)
    
    public func play(track: SGDoxMusicTrack, completion: @escaping @Sendable (Bool) -> Void) {
        self.activePlayGeneration += 1
        let generation = self.activePlayGeneration
        
        self.currentTrack = track
        self.isDeezerPreviewActive = false
        self.isPreparing = true
        self.lastSeekTime = nil
        self.playbackStartWatchdogTimer?.invalidate()
        self.playbackStartWatchdogTimer = nil
        
        // Fully stop and tear down previous audio session before starting a new track
        self.player.stop()
        self.isUsingSystemPlayer = false
        
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemPlaybackStalled, object: nil)
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: nil)
        
        self.avPlayer?.pause()
        self.avPlayer?.replaceCurrentItem(with: nil)
        self.avPlayer = nil

        // 1. If it has a local asset URL (ipod-library://)
        if let preview = track.previewUrl, let url = URL(string: preview), url.scheme == "ipod-library" {
            self.playPreview(url: url, generation: generation, completion: completion)
            return
        }
        
        // 2. If it's a local track by persistent ID (local_ or am_local_)
        let rawPidStr = (track.appleMusicId ?? track.id).replacingOccurrences(of: "am_local_", with: "").replacingOccurrences(of: "local_", with: "")
        if let pid = UInt64(rawPidStr), (track.appleMusicId?.hasPrefix("local_") == true || track.appleMusicId?.hasPrefix("am_local_") == true || track.id.hasPrefix("am_local_")) {
            let query = MPMediaQuery.songs()
            query.addFilterPredicate(MPMediaPropertyPredicate(value: NSNumber(value: pid), forProperty: MPMediaItemPropertyPersistentID))
            
            // Check direct asset url
            if let item = query.items?.first, let assetUrl = item.value(forProperty: MPMediaItemPropertyAssetURL) as? URL {
                self.isUsingSystemPlayer = false
                self.playPreview(url: assetUrl, generation: generation, completion: completion)
                return
            }
            
            // Play through media player query
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                let player = self.player
                player.setQueue(with: query)
                player.prepareToPlay { [weak self] error in
                    DispatchQueue.main.async {
                        guard let self = self, self.activePlayGeneration == generation, self.currentTrack?.id == track.id else { return }
                        if error == nil {
                            self.isPreparing = false
                            player.currentPlaybackTime = 0.0
                            player.play()
                            self.isUsingSystemPlayer = true
                            completion(true)
                        } else {
                            self.fallbackPlayPreviewOrSearch(track: track, generation: generation, completion: completion)
                        }
                    }
                }
            }
            return
        }
        
        // 3. Attempt system player if valid store ID AND user has catalog streaming rights
        if let appleMusicId = track.appleMusicId,
           !appleMusicId.isEmpty && !appleMusicId.hasPrefix("local_") && !appleMusicId.hasPrefix("am_local_"),
           self.canPlayCatalogContent != false {
            
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                
                let player = self.player
                player.setQueue(with: [appleMusicId])
                player.prepareToPlay { [weak self] error in
                    DispatchQueue.main.async {
                        guard let self = self, self.activePlayGeneration == generation, self.currentTrack?.id == track.id else { return }
                        if error == nil {
                            self.isPreparing = false
                            player.play()
                            player.currentPlaybackTime = 0.0
                            self.isUsingSystemPlayer = true
                            completion(true)
                        } else {
                            // Fallback to preview stream or search
                            self.fallbackPlayPreviewOrSearch(track: track, generation: generation, completion: completion)
                        }
                    }
                }
            }
            return
        }
        
        // 4. Fallback to Deezer preview, iTunes preview, or online search
        self.fallbackPlayPreviewOrSearch(track: track, generation: generation, completion: completion)
    }

    public func fetchDeezerPreview(artist: String, title: String, completion: @escaping @Sendable (URL?, String?) -> Void) {
        let cleanTitle = title
            .replacingOccurrences(of: "\\(feat.*\\)", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\[feat.*\\]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\(bonus.*\\)", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\(remaster.*\\)", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\(deluxe.*\\)", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let query = "\(artist) \(cleanTitle)"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.deezer.com/search?q=\(encoded)&limit=5") else {
            completion(nil, nil)
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 5.0
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = json["data"] as? [[String: Any]] else {
                completion(nil, nil)
                return
            }
            for item in list {
                if let previewStr = item["preview"] as? String, !previewStr.isEmpty, let previewUrl = URL(string: previewStr) {
                    let albumArt = (item["album"] as? [String: Any])?["cover_big"] as? String
                    completion(previewUrl, albumArt)
                    return
                }
            }
            completion(nil, nil)
        }.resume()
    }
    
    private func fallbackPlayPreviewOrSearch(track: SGDoxMusicTrack, generation: Int, completion: @escaping @Sendable (Bool) -> Void) {
        guard self.activePlayGeneration == generation, self.currentTrack?.id == track.id else { return }
        
        // Priority 1: High-speed, unthrottled Deezer MP3 preview (DRM-free and works reliably across CIS / Rostelecom)
        self.fetchDeezerPreview(artist: track.artist, title: track.title) { [weak self] deezerUrl, albumArt in
            guard let self = self else { return }
            DispatchQueue.main.async {
                guard self.activePlayGeneration == generation, self.currentTrack?.id == track.id else { return }
                
                if let deezerUrl = deezerUrl {
                    if let art = albumArt, !art.isEmpty {
                        SGDoxImageLoader.shared.loadImage(urlString: art) { img in
                            if let img = img {
                                SGDoxImageLoader.shared.storeImage(img, for: track.id)
                                if let old = track.artworkUrl { SGDoxImageLoader.shared.storeImage(img, for: old) }
                            }
                        }
                    }
                    self.isDeezerPreviewActive = true
                    self.isUsingSystemPlayer = false
                    self.playPreview(url: deezerUrl, generation: generation, completion: completion)
                    return
                }

                // Priority 2: Pre-existing track preview URL
                if let preview = track.previewUrl, let url = URL(string: preview) {
                    self.isUsingSystemPlayer = false
                    self.playPreview(url: url, generation: generation, completion: completion)
                    return
                }
                
                // Priority 3: iTunes public catalog search
                let cleanTitle = track.title
                    .replacingOccurrences(of: "\\(feat.*\\)", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "\\[feat.*\\]", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let query = "\(track.artist) \(cleanTitle)"
                self.searchITunesPublic(query: query) { [weak self] results, _ in
                    guard let self = self else {
                        DispatchQueue.main.async { completion(false) }
                        return
                    }
                    DispatchQueue.main.async {
                        guard self.activePlayGeneration == generation, self.currentTrack?.id == track.id else { return }
                        
                        if let first = results.first(where: { $0.previewUrl != nil }) ?? results.first, let preview = first.previewUrl, let url = URL(string: preview) {
                            if let art = first.artworkUrl, !art.isEmpty {
                                SGDoxImageLoader.shared.loadImage(urlString: art) { img in
                                    if let img = img {
                                        SGDoxImageLoader.shared.storeImage(img, for: track.id)
                                        if let old = track.artworkUrl { SGDoxImageLoader.shared.storeImage(img, for: old) }
                                    }
                                }
                            }
                            self.isUsingSystemPlayer = false
                            self.playPreview(url: url, generation: generation, completion: completion)
                        } else {
                            // Secondary fallback: search just the title
                            self.searchITunesPublic(query: cleanTitle) { [weak self] tResults, _ in
                                guard let self = self else {
                                    DispatchQueue.main.async { completion(false) }
                                    return
                                }
                                DispatchQueue.main.async {
                                    guard self.activePlayGeneration == generation, self.currentTrack?.id == track.id else { return }
                                    guard let first = tResults.first(where: { $0.previewUrl != nil }) ?? tResults.first, let preview = first.previewUrl, let url = URL(string: preview) else {
                                        completion(false)
                                        return
                                    }
                                    self.isUsingSystemPlayer = false
                                    self.playPreview(url: url, generation: generation, completion: completion)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func playPreview(url: URL, generation: Int, completion: @escaping @Sendable (Bool) -> Void) {
        guard self.activePlayGeneration == generation else { return }
        
        self.player.stop()
        self.isUsingSystemPlayer = false
        
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemPlaybackStalled, object: nil)
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: nil)
        
        self.avPlayer?.pause()
        self.avPlayer?.replaceCurrentItem(with: nil)
        self.avPlayer = nil
        
        let playerItem = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: playerItem)
        player.automaticallyWaitsToMinimizeStalling = true
        self.avPlayer = player
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.avPlayerDidFinishPlaying(_:)), name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
        NotificationCenter.default.addObserver(self, selector: #selector(self.avPlayerDidFail(_:)), name: .AVPlayerItemFailedToPlayToEndTime, object: playerItem)
        
        self.isPreparing = false
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
        DispatchQueue.main.async {
            guard self.activePlayGeneration == generation else {
                player.pause()
                player.replaceCurrentItem(with: nil)
                return
            }
            completion(true)
        }
    }

    @objc private func avPlayerDidFinishPlaying(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let finishedItem = notification.object as? AVPlayerItem,
                  finishedItem === self.avPlayer?.currentItem,
                  SGDoxMusicManager.shared.isPlaying else { return }
            self.onTrackDidFinish?()
        }
    }

    @objc private func avPlayerDidFail(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let failedItem = notification.object as? AVPlayerItem,
                  failedItem === self.avPlayer?.currentItem,
                  SGDoxMusicManager.shared.isPlaying else { return }
            if let track = self.currentTrack {
                self.onPlaybackFailed?(track)
            }
        }
    }
    
    public func pause() {
        if self.isUsingSystemPlayer {
            self.player.pause()
        }
        self.avPlayer?.pause()
    }

    public func stop() {
        self.activePlayGeneration += 1
        self.playbackStartWatchdogTimer?.invalidate()
        self.playbackStartWatchdogTimer = nil
        self.player.stop()
        self.isUsingSystemPlayer = false
        self.isPreparing = false
        self.lastSeekTime = nil
        
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemPlaybackStalled, object: nil)
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: nil)
        
        self.avPlayer?.pause()
        self.avPlayer?.replaceCurrentItem(with: nil)
        self.avPlayer = nil
        self.currentTrack = nil
    }
    
    public func resume() {
        if self.isUsingSystemPlayer {
            self.player.play()
        } else {
            self.avPlayer?.play()
        }
    }
    
    public func seek(to seconds: Double) {
        self.lastSeekTime = seconds
        self.lastSeekTimestamp = CACurrentMediaTime()
        if self.isUsingSystemPlayer {
            self.player.currentPlaybackTime = seconds
        } else {
            self.avPlayer?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }
    
    public var currentPlaybackTime: Double {
        if self.isPreparing {
            return 0.0
        }
        if let seekTarget = self.lastSeekTime {
            let elapsed = CACurrentMediaTime() - self.lastSeekTimestamp
            if elapsed < 1.2 {
                return max(0.0, seekTarget + elapsed)
            } else {
                self.lastSeekTime = nil
            }
        }
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
