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
        self.lock.unlock()
        NotificationCenter.default.post(name: NSNotification.Name("SGDoxListenTogetherSessionChanged"), object: nil)
    }
    
    public func generateInviteText(for track: SGDoxMusicTrack) -> String {
        let now = Int64(Date().timeIntervalSince1970)
        let cleanTitle = track.title.replacingOccurrences(of: ":", with: " ")
        let cleanArtist = track.artist.replacingOccurrences(of: ":", with: " ")
        let tag = "#doxlisten:\(track.id):\(now):\(cleanTitle):\(cleanArtist)"
        return "🎧 Приглашение в «Прослушивание вместе» DoxGram!\n🎵 \(track.title) — \(track.artist)\n\nСлушать вместе: \(tag)"
    }
    
    public func handleIncomingSync(text: String, peerId: EnginePeer.Id, senderName: String? = nil) -> Bool {
        guard let range = text.range(of: "#doxlisten:") else { return false }
        let payload = String(text[range.upperBound...])
        let components = payload.components(separatedBy: ":")
        guard components.count >= 4 else { return false }
        
        let trackId = components[0]
        let timestamp = Int64(components[1]) ?? Int64(Date().timeIntervalSince1970)
        let title = components[2]
        let artist = components[3]
        
        let elapsed = max(0.0, Double(Int64(Date().timeIntervalSince1970) - timestamp))
        
        self.joinSession(peerId: peerId, partnerName: senderName)
        
        // Search and play track synchronized
        AppleMusicService.shared.search(query: "\(title) \(artist)") { tracks, _ in
            let match = tracks.first(where: { $0.id == trackId }) ?? tracks.first
            if let trackToPlay = match {
                SGDoxMusicManager.shared.play(track: trackToPlay)
                if elapsed > 1.0 && elapsed < (trackToPlay.duration > 0 ? trackToPlay.duration : 300.0) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        SGDoxMusicManager.shared.seek(to: elapsed)
                    }
                }
            }
        }
        return true
    }
}
