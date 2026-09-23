import Foundation
import UIKit
import AVFoundation
import SwiftSignalKit
import TelegramCore
import Postbox
import AccountContext
import Display
import UndoUI

public final class SGDoxMusicManager: NSObject, @unchecked Sendable {
    public static let shared = SGDoxMusicManager()
    
    public private(set) var currentTrack: SGDoxMusicTrack?
    public private(set) var queue: [SGDoxMusicTrack] = []
    public private(set) var history: [SGDoxMusicTrack] = []
    public private(set) var isPlaying: Bool = false
    public private(set) var currentTime: Double = 0.0
    public private(set) var duration: Double = 0.0
    
    public var isWaveEnabled: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "dox_music_wave_enabled")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "dox_music_wave_enabled")
            self.notifyStateChanged()
        }
    }
    
    public enum RepeatMode: Int {
        case off = 0
        case all = 1
        case one = 2
    }
    
    public var repeatMode: RepeatMode {
        get {
            let raw = UserDefaults.standard.integer(forKey: "dox_music_repeat_mode")
            return RepeatMode(rawValue: raw) ?? .off
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "dox_music_repeat_mode")
            self.notifyStateChanged()
        }
    }
    
    @discardableResult
    public func toggleRepeatMode() -> RepeatMode {
        let next: RepeatMode
        switch self.repeatMode {
        case .off: next = .all
        case .all: next = .one
        case .one: next = .off
        }
        self.repeatMode = next
        return next
    }
    
    public var isShuffleEnabled: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "dox_music_shuffle_enabled")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "dox_music_shuffle_enabled")
            if newValue && !self.queue.isEmpty {
                self.queue.shuffle()
            }
            self.notifyStateChanged()
        }
    }
    
    public func toggleShuffle() {
        self.isShuffleEnabled.toggle()
    }
    
    public var isAutoplayEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: "dox_music_autoplay_enabled") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "dox_music_autoplay_enabled")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "dox_music_autoplay_enabled")
            self.notifyStateChanged()
        }
    }
    
    public func toggleAutoplay() {
        self.isAutoplayEnabled.toggle()
    }
    
    public private(set) var favorites: [SGDoxMusicTrack] = []
    
    private func loadFavorites() {
        guard let data = UserDefaults.standard.data(forKey: "dox_music_favorites"),
              let list = try? JSONDecoder().decode([SGDoxMusicTrack].self, from: data) else {
            return
        }
        self.favorites = list
    }
    
    private func saveFavorites() {
        if let data = try? JSONEncoder().encode(self.favorites) {
            UserDefaults.standard.set(data, forKey: "dox_music_favorites")
        }
    }
    
    public func dismissPlayer() {
        self.pause()
        self.stopCurrentAudio()
        UserDefaults.standard.set(true, forKey: "dox_music_is_dismissed")
        self.currentTrack = nil
        self.savePersistedState()
        self.notifyStateChanged()
    }
    
    private func loadPersistedState() {
        let isDismissed = UserDefaults.standard.bool(forKey: "dox_music_is_dismissed")
        guard !isDismissed else { return }
        
        if let trackData = UserDefaults.standard.data(forKey: "dox_music_current_track"),
           let track = try? JSONDecoder().decode(SGDoxMusicTrack.self, from: trackData) {
            self.currentTrack = track
            self.duration = track.duration > 0 ? track.duration : 30.0
            self.currentTime = UserDefaults.standard.double(forKey: "dox_music_current_time")
            self.isPlaying = false
            
            if let queueData = UserDefaults.standard.data(forKey: "dox_music_queue"),
               let q = try? JSONDecoder().decode([SGDoxMusicTrack].self, from: queueData) {
                self.queue = q
            }
        }
    }
    
    private func savePersistedState() {
        guard let track = self.currentTrack else {
            UserDefaults.standard.removeObject(forKey: "dox_music_current_track")
            UserDefaults.standard.removeObject(forKey: "dox_music_queue")
            UserDefaults.standard.removeObject(forKey: "dox_music_current_time")
            return
        }
        if let trackData = try? JSONEncoder().encode(track) {
            UserDefaults.standard.set(trackData, forKey: "dox_music_current_track")
        }
        if let queueData = try? JSONEncoder().encode(self.queue) {
            UserDefaults.standard.set(queueData, forKey: "dox_music_queue")
        }
        UserDefaults.standard.set(self.currentTime, forKey: "dox_music_current_time")
    }
    
    public func isFavorite(track: SGDoxMusicTrack) -> Bool {
        return self.favorites.contains(where: { $0.id == track.id || ($0.title == track.title && $0.artist == track.artist) })
    }
    
    public func toggleFavorite(track: SGDoxMusicTrack) {
        if let index = self.favorites.firstIndex(where: { $0.id == track.id || ($0.title == track.title && $0.artist == track.artist) }) {
            self.favorites.remove(at: index)
            self.saveFavorites()
            if track.source == .spotify {
                SpotifyService.shared.removeTrack(id: track.id) { _ in }
            }
        } else {
            self.favorites.insert(track, at: 0)
            self.saveFavorites()
            if track.source == .appleMusic {
                AppleMusicService.shared.addToLibrary(track: track) { _ in }
            } else if track.source == .spotify {
                SpotifyService.shared.saveTrack(id: track.id) { _ in }
            }
        }
        self.notifyStateChanged()
    }
    
    public func updateTrackArtwork(trackId: String, newArtworkUrl: String) {
        DispatchQueue.main.async {
            var changed = false
            if let idx = self.favorites.firstIndex(where: { $0.id == trackId }) {
                let old = self.favorites[idx]
                let updated = SGDoxMusicTrack(
                    id: old.id,
                    title: old.title,
                    artist: old.artist,
                    album: old.album,
                    artworkUrl: newArtworkUrl,
                    duration: old.duration,
                    previewUrl: old.previewUrl,
                    source: old.source,
                    spotifyUri: old.spotifyUri,
                    appleMusicId: old.appleMusicId,
                    telegramFile: old.telegramFile
                )
                self.favorites[idx] = updated
                changed = true
            }
            if let curr = self.currentTrack, curr.id == trackId {
                self.currentTrack = SGDoxMusicTrack(
                    id: curr.id,
                    title: curr.title,
                    artist: curr.artist,
                    album: curr.album,
                    artworkUrl: newArtworkUrl,
                    duration: curr.duration,
                    previewUrl: curr.previewUrl,
                    source: curr.source,
                    spotifyUri: curr.spotifyUri,
                    appleMusicId: curr.appleMusicId,
                    telegramFile: curr.telegramFile
                )
                changed = true
            }
            if changed {
                self.saveFavorites()
                self.notifyStateChanged()
            }
        }
    }
    
    public func syncFavoritesWithServices() {
        if AppleMusicService.shared.isAuthorized {
            AppleMusicService.shared.fetchLibrarySongs { [weak self] amTracks in
                guard let self = self, !amTracks.isEmpty else { return }
                var updated = self.favorites
                for t in amTracks {
                    if let existingIdx = updated.firstIndex(where: { $0.id == t.id || ($0.title == t.title && $0.artist == t.artist) }) {
                        let existing = updated[existingIdx]
                        if (existing.previewUrl == nil || existing.previewUrl?.isEmpty == true) && t.previewUrl != nil {
                            updated[existingIdx] = t
                        }
                    } else {
                        updated.append(t)
                    }
                }
                DispatchQueue.main.async {
                    self.favorites = updated
                    self.saveFavorites()
                    self.notifyStateChanged()
                }
            }
        }
        
        if SpotifyService.shared.isAuthorized {
            SpotifyService.shared.fetchLikedTracks { [weak self] spTracks in
                guard let self = self, !spTracks.isEmpty else { return }
                var updated = self.favorites
                for t in spTracks {
                    if let existingIdx = updated.firstIndex(where: { $0.id == t.id || ($0.title == t.title && $0.artist == t.artist) }) {
                        let existing = updated[existingIdx]
                        if (existing.previewUrl == nil || existing.previewUrl?.isEmpty == true) && t.previewUrl != nil {
                            updated[existingIdx] = t
                        }
                    } else {
                        updated.append(t)
                    }
                }
                DispatchQueue.main.async {
                    self.favorites = updated
                    self.saveFavorites()
                    self.notifyStateChanged()
                }
            }
        }
    }
    
    private var timeObserver: Any?
    private var avPlayer: AVPlayer?
    private var playbackTimer: Foundation.Timer?
    private var playbackStartTimestamp: Double = 0.0
    private var playbackStartOffset: Double = 0.0
    private var stateListeners: [UUID: () -> Void] = [:]
    private var timeListeners: [UUID: (Double, Double) -> Void] = [:]
    private var lastReportedTrackId: String?
    private var lastReportedIsPlaying: Bool?
    private var lastReportedDuration: Double = 0.0
    private var lastReportedArtworkUrl: String?
    private var hasSyncedAudioStart: Bool = false
    
    private override init() {
        super.init()
        self.setupAudioSession()
        self.loadFavorites()
        self.loadPersistedState()
        self.syncFavoritesWithServices()
        
        AppleMusicService.shared.onTrackDidFinish = { [weak self] in
            DispatchQueue.main.async {
                self?.next()
            }
        }
        AppleMusicService.shared.onPlaybackFailed = { [weak self] _ in
            DispatchQueue.main.async {
                self?.next()
            }
        }
    }
    
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            if session.category != .playAndRecord {
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try session.setActive(true)
            }
        } catch {
        }
    }
    
    @discardableResult
    public func addStateListener(_ listener: @escaping () -> Void) -> UUID {
        let id = UUID()
        self.stateListeners[id] = listener
        return id
    }
    
    public func removeStateListener(_ id: UUID) {
        self.stateListeners.removeValue(forKey: id)
    }
    
    @discardableResult
    public func addTimeListener(_ listener: @escaping (Double, Double) -> Void) -> UUID {
        let id = UUID()
        self.timeListeners[id] = listener
        return id
    }
    
    public func removeTimeListener(_ id: UUID) {
        self.timeListeners.removeValue(forKey: id)
    }
    
    private func notifyStateChanged() {
        DispatchQueue.main.async {
            let artworkUrl = self.currentTrack?.artworkUrl
            if self.lastReportedTrackId != self.currentTrack?.id || self.lastReportedIsPlaying != self.isPlaying || self.lastReportedArtworkUrl != artworkUrl {
                self.lastReportedTrackId = self.currentTrack?.id
                self.lastReportedIsPlaying = self.isPlaying
                self.lastReportedDuration = self.duration
                self.lastReportedArtworkUrl = artworkUrl
                
                // If starting a new track, wait for actual audio hardware start (>= 0.2s) in startTimeTracking
                // to avoid Discord timer starting 2 seconds before sound reaches headphones.
                // If paused, stopped, or already playing with valid audio time, update Discord immediately.
                if !self.isPlaying || self.currentTime > 0.1 || self.hasSyncedAudioStart {
                    DiscordRPCService.shared.updatePlayback(track: self.currentTrack, isPlaying: self.isPlaying, currentTime: self.currentTime, duration: self.duration)
                }
            }
            for listener in self.stateListeners.values {
                listener()
            }
        }
    }
    
    private func startTimeTracking() {
        self.stopTimeTracking()
        self.playbackStartTimestamp = CACurrentMediaTime()
        self.playbackStartOffset = self.currentTime
        self.hasSyncedAudioStart = false
        
        self.playbackTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, self.isPlaying else { return }
            
            var currentRealTime: Double?
            if let track = self.currentTrack {
                switch track.source {
                case .appleMusic:
                    // Both system player and 30s AVPlayer preview are handled accurately
                    let t = AppleMusicService.shared.currentPlaybackTime
                    if t.isFinite && !t.isNaN && t >= 0 {
                        currentRealTime = t
                    }
                    let dur = AppleMusicService.shared.playbackDuration
                    if dur > 0 && abs(self.duration - dur) > 1.0 {
                        self.duration = dur
                    }
                case .spotify:
                    break
                case .telegram:
                    if let p = self.avPlayer {
                        let t = p.currentTime().seconds
                        if t.isFinite && !t.isNaN && t >= 0 {
                            currentRealTime = t
                        }
                    }
                }
            }
            
            var current: Double
            if let real = currentRealTime, real > 0 {
                current = real
                self.playbackStartOffset = real
                self.playbackStartTimestamp = CACurrentMediaTime()
            } else {
                // If real audio output has not started yet (still buffering/loading),
                // do not accumulate elapsed time ahead of audio output!
                if currentRealTime == 0.0 && self.currentTime == 0.0 {
                    self.playbackStartTimestamp = CACurrentMediaTime()
                    current = 0.0
                } else {
                    let elapsed = CACurrentMediaTime() - self.playbackStartTimestamp
                    current = self.playbackStartOffset + elapsed
                }
            }
            
            let total = self.duration
            if current.isFinite && !current.isNaN {
                self.currentTime = current
            }
            
            // When real audio starts producing sound (>= 0.2s) and we haven't synced audio start,
            // re-sync Discord RPC so its timeline starts synchronously with headphones/speakers
            if current >= 0.2 && !self.hasSyncedAudioStart {
                self.hasSyncedAudioStart = true
                DiscordRPCService.shared.updatePlayback(track: self.currentTrack, isPlaying: self.isPlaying, currentTime: self.currentTime, duration: self.duration)
            }
            
            for listener in self.timeListeners.values {
                listener(self.currentTime, self.duration)
            }
            
            // Check if track ended
            if total > 0 && current >= total - 0.5 {
                self.next()
            }
        }
    }
    
    private func stopTimeTracking() {
        self.playbackTimer?.invalidate()
        self.playbackTimer = nil
    }
    
    // MARK: - Playback
    
    public func play(track: SGDoxMusicTrack, queue: [SGDoxMusicTrack] = []) {
        if let current = self.currentTrack, current.id != track.id {
            self.history.append(current)
        }
        self.currentTrack = track
        self.duration = track.duration > 0 ? track.duration : 30.0
        self.currentTime = 0.0
        self.playbackStartTimestamp = CACurrentMediaTime()
        self.playbackStartOffset = 0.0
        self.hasSyncedAudioStart = false
        
        if !queue.isEmpty {
            var q = queue.filter { $0.id != track.id }
            if self.isShuffleEnabled {
                q.shuffle()
            }
            self.queue = q
        } else if self.queue.isEmpty {
            var q = self.favorites.filter { $0.id != track.id }
            if self.isShuffleEnabled {
                q.shuffle()
            }
            self.queue = q
        }
        
        self.stopCurrentAudio()
        UserDefaults.standard.set(false, forKey: "dox_music_is_dismissed")
        self.savePersistedState()
        
        switch track.source {
        case .appleMusic:
            AppleMusicService.shared.play(track: track) { [weak self] success in
                guard let self = self else { return }
                self.isPlaying = success
                if success {
                    self.startTimeTracking()
                } else {
                    self.stopTimeTracking()
                }
                self.notifyStateChanged()
                self.checkWaveReplenishmentIfNeeded()
            }
        case .spotify:
            SpotifyService.shared.play(track: track) { [weak self] success in
                guard let self = self else { return }
                self.isPlaying = success
                if success {
                    self.startTimeTracking()
                } else {
                    self.stopTimeTracking()
                }
                self.notifyStateChanged()
                self.checkWaveReplenishmentIfNeeded()
            }
        case .telegram:
            self.playTelegramTrack(track: track)
        }
    }
    
    private func playTelegramTrack(track: SGDoxMusicTrack) {
        guard let preview = track.previewUrl, let url = URL(string: preview) else {
            self.isPlaying = false
            self.notifyStateChanged()
            return
        }
        
        let playerItem = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: playerItem)
        self.avPlayer = player
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.playerDidFinishPlaying), name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
        
        player.seek(to: .zero)
        player.play()
        self.isPlaying = true
        self.startTimeTracking()
        self.notifyStateChanged()
        self.checkWaveReplenishmentIfNeeded()
    }
    
    @objc private func playerDidFinishPlaying() {
        self.next()
    }
    
    public func togglePlay() {
        if self.isPlaying {
            self.pause()
        } else {
            self.resume()
        }
    }
    
    public func pause() {
        self.isPlaying = false
        self.stopTimeTracking()
        self.avPlayer?.pause()
        AppleMusicService.shared.pause()
        SpotifyService.shared.pause()
        self.savePersistedState()
        self.notifyStateChanged()
    }
    
    public func stop() {
        self.pause()
        self.stopCurrentAudio()
        self.currentTrack = nil
        self.savePersistedState()
        self.notifyStateChanged()
    }
    
    public func resume() {
        if let track = self.currentTrack {
            UserDefaults.standard.set(false, forKey: "dox_music_is_dismissed")
            if track.source == .telegram && self.avPlayer == nil {
                self.playTelegramTrack(track: track)
                if self.currentTime > 0 {
                    self.seek(to: self.currentTime)
                }
                return
            } else if track.source == .appleMusic && !AppleMusicService.shared.isAuthorized {
                self.play(track: track, queue: self.queue)
                return
            } else if track.source == .spotify && !SpotifyService.shared.isAuthorized {
                self.play(track: track, queue: self.queue)
                return
            }
            self.isPlaying = true
            self.playbackStartTimestamp = CACurrentMediaTime()
            self.playbackStartOffset = self.currentTime
            self.hasSyncedAudioStart = false
            switch track.source {
            case .appleMusic:
                AppleMusicService.shared.resume()
            case .spotify:
                SpotifyService.shared.resume()
            case .telegram:
                self.avPlayer?.play()
            }
            self.startTimeTracking()
            self.savePersistedState()
            self.notifyStateChanged()
        }
    }
    
    public func effectiveQueue() -> [SGDoxMusicTrack] {
        if !self.queue.isEmpty {
            return self.queue
        }
        guard let current = self.currentTrack else {
            return self.favorites
        }
        let favs = self.favorites.filter { $0.id != current.id }
        if !favs.isEmpty {
            return favs
        }
        return []
    }
    
    public func next() {
        if self.repeatMode == .one, self.currentTrack != nil {
            self.seek(to: 0.0)
            self.resume()
            return
        }
        
        if !self.queue.isEmpty {
            let nextTrack = self.queue.removeFirst()
            self.play(track: nextTrack, queue: self.queue)
            return
        }
        
        let eff = self.effectiveQueue()
        if !eff.isEmpty {
            var remaining = eff
            let nextTrack = remaining.removeFirst()
            self.play(track: nextTrack, queue: remaining)
            return
        }
        
        if self.repeatMode == .all, !self.history.isEmpty {
            var fullList = self.history
            if let current = self.currentTrack {
                fullList.append(current)
            }
            if self.isShuffleEnabled {
                fullList.shuffle()
            }
            self.history = []
            let first = fullList.removeFirst()
            self.play(track: first, queue: fullList)
        } else if self.isAutoplayEnabled || self.isWaveEnabled {
            self.fetchWaveAndPlayNext()
        } else {
            self.pause()
        }
    }
    
    public func previous() {
        if self.currentTime > 3.0 {
            self.seek(to: 0.0)
            return
        }
        if let previousTrack = self.history.popLast() {
            if let current = self.currentTrack {
                self.queue.insert(current, at: 0)
            }
            self.play(track: previousTrack, queue: self.queue)
        } else {
            self.seek(to: 0.0)
        }
    }
    
    public func seek(to seconds: Double) {
        self.currentTime = seconds
        self.playbackStartTimestamp = CACurrentMediaTime()
        self.playbackStartOffset = seconds
        self.hasSyncedAudioStart = true
        self.avPlayer?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        AppleMusicService.shared.seek(to: seconds)
        if self.isPlaying {
            DiscordRPCService.shared.updatePlayback(track: self.currentTrack, isPlaying: self.isPlaying, currentTime: seconds, duration: self.duration)
        }
        self.savePersistedState()
        self.notifyStateChanged()
    }
    
    private func stopCurrentAudio() {
        if let timeObserver = self.timeObserver {
            self.avPlayer?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        self.avPlayer?.pause()
        self.avPlayer = nil
        AppleMusicService.shared.pause()
        SpotifyService.shared.pause()
    }
    
    // MARK: - Wave Engine (Волна)
    
    public func startWave(seedTrack: SGDoxMusicTrack? = nil) {
        self.isWaveEnabled = true
        let track = seedTrack ?? self.currentTrack
        
        if SpotifyService.shared.isAuthorized {
            SpotifyService.shared.fetchWaveTracks(basedOn: track) { [weak self] tracks in
                guard let self = self else { return }
                if !tracks.isEmpty {
                    var list = tracks
                    let first = list.removeFirst()
                    self.play(track: first, queue: list)
                } else {
                    self.fallbackStartWaveWithPublicMusic(seedTrack: track)
                }
            }
        } else {
            self.fallbackStartWaveWithPublicMusic(seedTrack: track)
        }
    }
    
    private func fallbackStartWaveWithPublicMusic(seedTrack: SGDoxMusicTrack?) {
        AppleMusicService.shared.fetchWaveTracks(basedOn: seedTrack) { [weak self] tracks in
            guard let self = self else { return }
            var list = tracks
            if list.isEmpty {
                AppleMusicService.shared.searchITunesPublic(query: "Top Hits") { [weak self] fallbackTracks, _ in
                    guard let self = self, !fallbackTracks.isEmpty else { return }
                    var fallbackList = fallbackTracks
                    let first = fallbackList.removeFirst()
                    self.play(track: first, queue: fallbackList)
                }
                return
            }
            let first = list.removeFirst()
            self.play(track: first, queue: list)
        }
    }
    
    private func checkWaveReplenishmentIfNeeded() {
        guard self.isWaveEnabled && self.queue.count < 3 else { return }
        self.replenishWaveQueue()
    }
    
    private func replenishWaveQueue() {
        let track = self.currentTrack
        if SpotifyService.shared.isAuthorized {
            SpotifyService.shared.fetchWaveTracks(basedOn: track) { [weak self] tracks in
                guard let self = self else { return }
                let uniqueTracks = tracks.filter { t in !self.queue.contains(where: { $0.id == t.id }) && t.id != self.currentTrack?.id }
                if !uniqueTracks.isEmpty {
                    self.queue.append(contentsOf: uniqueTracks)
                    self.notifyStateChanged()
                } else {
                    self.replenishWaveQueueWithPublicMusic(track: track)
                }
            }
        } else {
            self.replenishWaveQueueWithPublicMusic(track: track)
        }
    }
    
    private func replenishWaveQueueWithPublicMusic(track: SGDoxMusicTrack?) {
        AppleMusicService.shared.fetchWaveTracks(basedOn: track) { [weak self] tracks in
            guard let self = self else { return }
            let uniqueTracks = tracks.filter { t in !self.queue.contains(where: { $0.id == t.id }) && t.id != self.currentTrack?.id }
            self.queue.append(contentsOf: uniqueTracks)
            self.notifyStateChanged()
        }
    }
    
    private func fetchWaveAndPlayNext() {
        let track = self.currentTrack
        if SpotifyService.shared.isAuthorized {
            SpotifyService.shared.fetchWaveTracks(basedOn: track) { [weak self] tracks in
                guard let self = self else { return }
                if let next = tracks.first {
                    self.queue = Array(tracks.dropFirst())
                    self.play(track: next, queue: self.queue)
                } else {
                    self.fetchWaveAndPlayNextPublic(track: track)
                }
            }
        } else {
            self.fetchWaveAndPlayNextPublic(track: track)
        }
    }
    
    private func fetchWaveAndPlayNextPublic(track: SGDoxMusicTrack?) {
        AppleMusicService.shared.fetchWaveTracks(basedOn: track) { [weak self] tracks in
            guard let self = self, let next = tracks.first else { return }
            self.queue = Array(tracks.dropFirst())
            self.play(track: next, queue: self.queue)
        }
    }
    
    // MARK: - Profile Music Pinning (account.saveMusic)
    
    public func pinCurrentTrackToProfile(context: AccountContext, completion: @escaping (Bool, String?) -> Void) {
        guard let track = self.currentTrack else {
            completion(false, "Нет активного трека")
            return
        }
        
        // 1. If it's already a native Telegram Media file
        if let file = track.telegramFile {
            let _ = (context.engine.peers.addSavedMusic(file: file) |> deliverOnMainQueue).start(error: { _ in
                completion(false, "Не удалось закрепить трек в профиле")
            }, completed: {
                completion(true, nil)
            })
            return
        }
        
        // 2. Scan user's Saved Messages (Избранное) locally
        let cleanTitle = track.title
            .replacingOccurrences(of: "\\(feat.*\\)", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\[feat.*\\]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let cleanArtist = track.artist
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            
        let _ = (context.account.postbox.transaction { transaction -> (FileMediaReference?, FileMediaReference?) in
            var matchedRef: FileMediaReference?
            var latestAudioRef: FileMediaReference?
            var count = 0
            
            transaction.withAllMessages(peerId: context.account.peerId, namespace: nil, reversed: true) { message in
                count += 1
                for media in message.media {
                    if let file = media as? TelegramMediaFile {
                        let isAudio = file.isMusic || file.mimeType.hasPrefix("audio/") || (file.fileName?.lowercased().hasSuffix(".mp3") == true) || (file.fileName?.lowercased().hasSuffix(".m4a") == true) || (file.fileName?.lowercased().hasSuffix(".flac") == true)
                        if isAudio {
                            let fileRef = FileMediaReference.message(message: MessageReference(message), media: file)
                            if latestAudioRef == nil {
                                latestAudioRef = fileRef
                            }
                            
                            var songTitle: String?
                            var songPerformer: String?
                            for attr in file.attributes {
                                if case let .Audio(_, _, title, performer, _) = attr {
                                    songTitle = title
                                    songPerformer = performer
                                    break
                                }
                            }
                            
                            let candTitle = (songTitle ?? file.fileName ?? "").lowercased()
                            let candPerformer = (songPerformer ?? "").lowercased()
                            let msgText = message.text.lowercased()
                            
                            let titleMatch = !cleanTitle.isEmpty && (candTitle.contains(cleanTitle) || cleanTitle.contains(candTitle) || msgText.contains(cleanTitle))
                            let artistMatch = !cleanArtist.isEmpty && (candPerformer.contains(cleanArtist) || cleanArtist.contains(candPerformer) || msgText.contains(cleanArtist))
                            
                            if (titleMatch && artistMatch) || titleMatch {
                                matchedRef = fileRef
                                return false
                            }
                        }
                    }
                }
                return count < 300
            }
            return (matchedRef, latestAudioRef)
        } |> deliverOnMainQueue).start(next: { (matchedRef, latestAudioRef) in
            if let targetRef = matchedRef {
                let _ = (context.engine.peers.addSavedMusic(file: targetRef) |> deliverOnMainQueue).start(error: { _ in
                    completion(false, "Не удалось закрепить трек в профиле")
                }, completed: {
                    completion(true, nil)
                })
                return
            }
            
            // 3. If not found in Saved Messages, search Telegram global messages
            let searchQuery = "\(track.artist) \(cleanTitle)"
            let searchLocation = SearchMessagesLocation.general(
                scope: .everywhere,
                groupId: nil,
                tags: nil,
                minDate: nil,
                maxDate: nil,
                folderId: nil,
                communityId: nil
            )
            let searchSignal = context.engine.messages.searchMessages(
                location: searchLocation,
                query: searchQuery,
                state: nil,
                limit: 25
            )
            
            let _ = (searchSignal |> deliverOnMainQueue).start(next: { (result: (SearchMessagesResult, SearchMessagesState)) in
                for message in result.0.messages {
                    for media in message.media {
                        if let file = media as? TelegramMediaFile, file.isMusic {
                            let fileRef = FileMediaReference.message(message: MessageReference(message), media: file)
                            let _ = (context.engine.peers.addSavedMusic(file: fileRef) |> deliverOnMainQueue).start(error: { _ in
                                completion(false, "Не удалось закрепить трек в профиле")
                            }, completed: {
                                completion(true, nil)
                            })
                            return
                        }
                    }
                }
                
                // Fallback: search clean title only
                let titleSignal = context.engine.messages.searchMessages(
                    location: searchLocation,
                    query: cleanTitle,
                    state: nil,
                    limit: 25
                )
                let _ = (titleSignal |> deliverOnMainQueue).start(next: { (tResult: (SearchMessagesResult, SearchMessagesState)) in
                    for message in tResult.0.messages {
                        for media in message.media {
                            if let file = media as? TelegramMediaFile, file.isMusic {
                                let fileRef = FileMediaReference.message(message: MessageReference(message), media: file)
                                let _ = (context.engine.peers.addSavedMusic(file: fileRef) |> deliverOnMainQueue).start(error: { _ in
                                    completion(false, "Не удалось закрепить трек в профиле")
                                }, completed: {
                                    completion(true, nil)
                                })
                                return
                            }
                        }
                    }
                    
                    if let fallback = latestAudioRef {
                        let _ = (context.engine.peers.addSavedMusic(file: fallback) |> deliverOnMainQueue).start(error: { _ in
                            completion(false, "Не удалось закрепить трек в профиле")
                        }, completed: {
                            completion(true, nil)
                        })
                    } else {
                        completion(false, "Трек не найден в Telegram. Отправьте аудиозапись в «Избранное» для закрепления в профиле.")
                    }
                })
            })
        })
    }
}
