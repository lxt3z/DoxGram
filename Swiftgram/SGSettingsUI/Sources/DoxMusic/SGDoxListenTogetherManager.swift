import Foundation
import TelegramCore
import AccountContext
import Display
import SGSimpleSettings

public struct SGDoxListenTogetherSessionInfo: Equatable, @unchecked Sendable {
    public let trackId: String
    public let title: String
    public let artist: String
    public let timestamp: Int64
    public let senderName: String?
    public let peerId: EnginePeer.Id
    public var artworkUrl: String?
    
    public init(trackId: String, title: String, artist: String, timestamp: Int64, senderName: String?, peerId: EnginePeer.Id, artworkUrl: String? = nil) {
        self.trackId = trackId
        self.title = title
        self.artist = artist
        self.timestamp = timestamp
        self.senderName = senderName
        self.peerId = peerId
        self.artworkUrl = artworkUrl
    }
}

public final class SGDoxListenTogetherManager: NSObject, @unchecked Sendable {
    public static let shared = SGDoxListenTogetherManager()
    
    public enum Role: Int, Sendable {
        case none = 0
        case host = 1
        case listener = 2
    }
    
    public private(set) var activeRole: Role = .none
    public private(set) var currentSessionPeerId: EnginePeer.Id?
    public private(set) var partnerName: String?
    public private(set) var latestInvitesByPeer: [EnginePeer.Id: SGDoxListenTogetherSessionInfo] = [:]
    
    public var isInSession: Bool {
        return self.activeRole != .none
    }
    
    private let lock = NSLock()
    private var lastProcessedTag: String?
    
    public func startHostSession(peerId: EnginePeer.Id?, partnerName: String? = nil) {
        self.lock.lock()
        self.activeRole = .host
        self.currentSessionPeerId = peerId
        self.partnerName = partnerName
        self.lock.unlock()
        NotificationCenter.default.post(name: NSNotification.Name("SGDoxListenTogetherSessionChanged"), object: nil)
    }
    
    public func joinSession(peerId: EnginePeer.Id, partnerName: String? = nil) {
        self.lock.lock()
        self.activeRole = .listener
        self.currentSessionPeerId = peerId
        self.partnerName = partnerName
        self.lock.unlock()
        NotificationCenter.default.post(name: NSNotification.Name("SGDoxListenTogetherSessionChanged"), object: nil)
    }
    
    public func leaveSession() {
        self.lock.lock()
        self.activeRole = .none
        self.currentSessionPeerId = nil
        self.partnerName = nil
        self.lastProcessedTag = nil
        self.lock.unlock()
        NotificationCenter.default.post(name: NSNotification.Name("SGDoxListenTogetherSessionChanged"), object: nil)
    }
    
    public func generateInviteText(for track: SGDoxMusicTrack, offset: Double = 0.0) -> String {
        let now = Int64(Date().timeIntervalSince1970) - Int64(max(0.0, offset))
        let cleanTitle = track.title.replacingOccurrences(of: ":", with: " ")
        let cleanArtist = track.artist.replacingOccurrences(of: ":", with: " ")
        let tag = "#doxlisten:\(track.id):\(now):\(cleanTitle):\(cleanArtist)"
        return "🎧 Совместное прослушивание\n🎵 «\(track.title)» — \(track.artist)\n\n▶️ Нажмите для подключения к эфиру:\n\(tag)"
    }
    
    public func parseSyncTag(text: String, peerId: EnginePeer.Id, senderName: String? = nil) -> SGDoxListenTogetherSessionInfo? {
        guard let range = text.range(of: "#doxlisten:") ?? text.range(of: "doxlisten:") else { return nil }
        let payload = String(text[range.upperBound...])
        
        let components = payload.components(separatedBy: ":")
        guard components.count >= 4 else {
            return nil
        }
        
        let trackId = components[0]
        let timestamp = Int64(components[1]) ?? Int64(Date().timeIntervalSince1970)
        let title = components[2]
        let artist = components[3]
        
        let existingArtwork = self.latestInvitesByPeer[peerId]?.artworkUrl
        let info = SGDoxListenTogetherSessionInfo(
            trackId: trackId,
            title: title,
            artist: artist,
            timestamp: timestamp,
            senderName: senderName ?? self.latestInvitesByPeer[peerId]?.senderName,
            peerId: peerId,
            artworkUrl: existingArtwork
        )
        
        self.latestInvitesByPeer[peerId] = info
        
        // Resolve artwork asynchronously if missing
        if info.artworkUrl == nil || info.artworkUrl?.isEmpty == true {
            let peerIdRaw = peerId.toInt64()
            AppleMusicService.shared.search(query: "\(title) \(artist)") { [weak self] tracks, _ in
                if let first = tracks.first(where: { $0.artworkUrl?.isEmpty == false }) {
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        let targetPeerId = EnginePeer.Id(peerIdRaw)
                        if var current = self.latestInvitesByPeer[targetPeerId], current.trackId == trackId {
                            current.artworkUrl = first.artworkUrl
                            self.latestInvitesByPeer[targetPeerId] = current
                            NotificationCenter.default.post(name: NSNotification.Name("SGDoxListenTogetherUpdated"), object: nil, userInfo: ["peerId": targetPeerId])
                        }
                    }
                }
            }
        }
        
        return info
    }
    
    public func joinAndPlay(session: SGDoxListenTogetherSessionInfo) {
        self.joinSession(peerId: session.peerId, partnerName: session.senderName)
        let elapsed = max(0.0, Double(Int64(Date().timeIntervalSince1970) - session.timestamp))
        
        AppleMusicService.shared.search(query: "\(session.title) \(session.artist)") { tracks, _ in
            let cleanTargetTitle = session.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanTargetArtist = session.artist.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            
            // 1. Direct ID match
            var match = tracks.first(where: { $0.id == session.trackId })
            
            // 2. Both title and artist match closely
            if match == nil {
                match = tracks.first(where: { t in
                    let tTitle = t.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    let tArtist = t.artist.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    let titleMatches = tTitle == cleanTargetTitle || tTitle.contains(cleanTargetTitle) || cleanTargetTitle.contains(tTitle)
                    let artistMatches = tArtist == cleanTargetArtist || tArtist.contains(cleanTargetArtist) || cleanTargetArtist.contains(tArtist)
                    return titleMatches && artistMatches
                })
            }
            
            // 3. Exact title match
            if match == nil {
                match = tracks.first(where: { t in
                    let tTitle = t.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    return tTitle == cleanTargetTitle
                })
            }
            
            // 4. Fallback first track
            if match == nil {
                match = tracks.first
            }
            
            if let trackToPlay = match {
                SGDoxMusicManager.shared.play(track: trackToPlay)
                if elapsed > 0.5 && elapsed < (trackToPlay.duration > 0 ? trackToPlay.duration : 300.0) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        SGDoxMusicManager.shared.seek(to: elapsed)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        if abs(SGDoxMusicManager.shared.currentTime - elapsed) > 3.0 {
                            SGDoxMusicManager.shared.seek(to: elapsed + 1.0)
                        }
                    }
                }
            }
        }
    }
    
    public func handleIncomingSync(text: String, peerId: EnginePeer.Id, senderName: String? = nil, forceJoin: Bool = false) -> Bool {
        guard let info = self.parseSyncTag(text: text, peerId: peerId, senderName: senderName) else {
            return false
        }
        
        // Record peer's music status in SGDoxPeerMusicManager so note icon displays on their avatar & profile
        SGDoxPeerMusicManager.shared.updateMusicStatus(peerId: peerId.toInt64(), title: info.title, artist: info.artist)
        
        // Notify any active invite UI about track updates
        NotificationCenter.default.post(name: NSNotification.Name("SGDoxListenTogetherUpdated"), object: nil, userInfo: ["peerId": peerId])
        
        let elapsed = max(0.0, Double(Int64(Date().timeIntervalSince1970) - info.timestamp))
        let isCurrentSession = self.isInSession && self.currentSessionPeerId == peerId
        
        // NEVER auto-play on passive open; playback only starts if already in active session or explicitly tapped (forceJoin)
        if !isCurrentSession && !forceJoin {
            return false
        }
        
        let payload = "\(info.trackId):\(info.timestamp):\(info.title):\(info.artist)"
        self.lock.lock()
        if self.lastProcessedTag == payload && !forceJoin {
            self.lock.unlock()
            return false
        }
        
        if elapsed > 600.0 && !forceJoin {
            self.lock.unlock()
            return false
        }
        
        self.lastProcessedTag = payload
        self.lock.unlock()
        
        self.joinAndPlay(session: info)
        return true
    }
}
