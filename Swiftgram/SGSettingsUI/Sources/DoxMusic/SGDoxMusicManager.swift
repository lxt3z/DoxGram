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
    
    private var timeObserver: Any?
    private var avPlayer: AVPlayer?
    private var playbackTimer: Timer?
    private var stateListeners: [() -> Void] = []
    private var timeListeners: [(Double, Double) -> Void] = []
    private var lastReportedTrackId: String?
    private var lastReportedIsPlaying: Bool?
    private var lastReportedDuration: Double = 0.0
    
    private override init() {
        super.init()
        self.setupAudioSession()
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
    
    public func addStateListener(_ listener: @escaping () -> Void) {
        self.stateListeners.append(listener)
    }
    
    public func addTimeListener(_ listener: @escaping (Double, Double) -> Void) {
        self.timeListeners.append(listener)
    }
    
    private func notifyStateChanged() {
        DispatchQueue.main.async {
            if self.lastReportedTrackId != self.currentTrack?.id || self.lastReportedIsPlaying != self.isPlaying {
                self.lastReportedTrackId = self.currentTrack?.id
                self.lastReportedIsPlaying = self.isPlaying
                self.lastReportedDuration = self.duration
                DiscordRPCService.shared.updatePlayback(track: self.currentTrack, isPlaying: self.isPlaying, currentTime: self.currentTime, duration: self.duration)
            }
            for listener in self.stateListeners {
                listener()
            }
        }
    }
    
    private func startTimeTracking() {
        self.stopTimeTracking()
        self.playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, self.isPlaying else { return }
            var current = self.currentTime
            var total = self.duration
            
            if let track = self.currentTrack {
                switch track.source {
                case .appleMusic:
                    current = AppleMusicService.shared.currentPlaybackTime
                    let d = AppleMusicService.shared.playbackDuration
                    if d > 0 { total = d }
                case .spotify:
                    current += 0.5
                case .telegram:
                    if let p = self.avPlayer {
                        current = p.currentTime().seconds
                        if let d = p.currentItem?.duration.seconds, d > 0 { total = d }
                    }
                }
            }
            
            if current.isFinite && !current.isNaN {
                self.currentTime = current
            }
            if total.isFinite && !total.isNaN && total > 0 {
                self.duration = total
                if abs(total - self.lastReportedDuration) > 1.0 {
                    self.lastReportedDuration = total
                    if self.isPlaying {
                        DiscordRPCService.shared.updatePlayback(track: self.currentTrack, isPlaying: self.isPlaying, currentTime: current, duration: total)
                    }
                }
            }
            
            DispatchQueue.main.async {
                for listener in self.timeListeners {
                    listener(self.currentTime, self.duration)
                }
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
        
        if !queue.isEmpty {
            self.queue = queue.filter { $0.id != track.id }
        }
        
        self.stopCurrentAudio()
        
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
        self.notifyStateChanged()
    }
    
    public func resume() {
        if let track = self.currentTrack {
            self.isPlaying = true
            switch track.source {
            case .appleMusic:
                AppleMusicService.shared.resume()
            case .spotify:
                SpotifyService.shared.resume()
            case .telegram:
                self.avPlayer?.play()
            }
            self.startTimeTracking()
            self.notifyStateChanged()
        }
    }
    
    public func next() {
        if !self.queue.isEmpty {
            let nextTrack = self.queue.removeFirst()
            self.play(track: nextTrack, queue: self.queue)
        } else if self.isWaveEnabled {
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
        self.avPlayer?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        if self.isPlaying {
            DiscordRPCService.shared.updatePlayback(track: self.currentTrack, isPlaying: self.isPlaying, currentTime: seconds, duration: self.duration)
        }
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
            let _ = context.engine.peers.addSavedMusic(file: file).start(completed: {
                completion(true, nil)
            })
            return
        }
        
        // 2. Search Telegram audio library for matching track (Artist - Title)
        let searchQuery = "\(track.artist) \(track.title)"
        let searchLocation = SearchMessagesLocation.general(
            scope: .everywhere,
            groupId: nil,
            tags: .music,
            minDate: nil,
            maxDate: nil,
            folderId: nil,
            communityId: nil
        )
        let searchSignal = context.engine.messages.searchMessages(
            location: searchLocation,
            query: searchQuery,
            state: nil,
            limit: 10
        )
        
        let _ = (searchSignal |> deliverOnMainQueue).start(next: { (result: (SearchMessagesResult, SearchMessagesState)) in
            for message in result.0.messages {
                for media in message.media {
                    if let file = media as? TelegramMediaFile, file.isMusic {
                        let fileRef = FileMediaReference.message(message: MessageReference(message), media: file)
                        let _ = context.engine.peers.addSavedMusic(file: fileRef).start(completed: {
                            completion(true, nil)
                        })
                        return
                    }
                }
            }
            
            // If not found in global search, search in user's Saved Messages
            let savedSearchLocation = SearchMessagesLocation.peer(
                peerId: context.account.peerId,
                fromId: nil,
                tags: .music,
                reactions: nil,
                threadId: nil,
                minDate: nil,
                maxDate: nil
            )
            let savedSearchSignal = context.engine.messages.searchMessages(
                location: savedSearchLocation,
                query: track.title,
                state: nil,
                limit: 10
            )
            
            let _ = (savedSearchSignal |> deliverOnMainQueue).start(next: { (savedResult: (SearchMessagesResult, SearchMessagesState)) in
                for message in savedResult.0.messages {
                    for media in message.media {
                        if let file = media as? TelegramMediaFile, file.isMusic {
                            let fileRef = FileMediaReference.message(message: MessageReference(message), media: file)
                            let _ = context.engine.peers.addSavedMusic(file: fileRef).start(completed: {
                                completion(true, nil)
                            })
                            return
                        }
                    }
                }
                
                completion(false, "Трек не найден в Telegram. Отправьте аудиозапись в «Избранное» для закрепления в профиле.")
            })
        })
    }
}
