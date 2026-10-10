import Foundation
import TelegramCore
import AccountContext
import Display

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
        return "🎧 Приглашение в «Прослушивание вместе» DoxGram!\n🎵 \(track.title) — \(track.artist)\n\nСлушать вместе: \(tag)"
    }
    
    public func handleIncomingSync(text: String, peerId: EnginePeer.Id, senderName: String? = nil, forceJoin: Bool = false) -> Bool {
        guard let range = text.range(of: "#doxlisten:") else { return false }
        let payload = String(text[range.upperBound...])
        
        let components = payload.components(separatedBy: ":")
        guard components.count >= 4 else {
            return false
        }
        
        let trackId = components[0]
        let timestamp = Int64(components[1]) ?? Int64(Date().timeIntervalSince1970)
        let title = components[2]
        let artist = components[3]
        
        // Record peer's music status in SGDoxPeerMusicManager so note icon displays on their avatar & profile
        SGDoxPeerMusicManager.shared.updateMusicStatus(peerId: peerId.toInt64(), title: title, artist: artist)
        
        let elapsed = max(0.0, Double(Int64(Date().timeIntervalSince1970) - timestamp))
        
        // Safeguard against auto-playing old messages when merely opening chat
        if !forceJoin {
            let isCurrentSession = self.isInSession && self.currentSessionPeerId == peerId
            let isFreshInvite = elapsed < 15.0
            if !isCurrentSession && !isFreshInvite {
                return false
            }
        }
        
        self.lock.lock()
        if self.lastProcessedTag == payload && !forceJoin {
            self.lock.unlock()
            return false
        }
        
        if elapsed > 360.0 {
            self.lock.unlock()
            return false
        }
        
        self.lastProcessedTag = payload
        self.lock.unlock()
        
        self.joinSession(peerId: peerId, partnerName: senderName)
        
        // Search and play track synchronized with strict matching
        AppleMusicService.shared.search(query: "\(title) \(artist)") { tracks, _ in
            let cleanTargetTitle = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanTargetArtist = artist.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            
            // 1. Direct ID match
            var match = tracks.first(where: { $0.id == trackId })
            
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
            
            // 4. Exact artist match with partial title
            if match == nil {
                match = tracks.first(where: { t in
                    let tArtist = t.artist.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    return tArtist == cleanTargetArtist
                })
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
        return true
    }
}
