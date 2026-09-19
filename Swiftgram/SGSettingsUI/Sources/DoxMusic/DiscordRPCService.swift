import Foundation
import SGSimpleSettings
import SGLogging

public final class DiscordRPCService: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    public static let shared = DiscordRPCService()
    
    public enum ConnectionStatus: Equatable {
        case disconnected
        case connecting
        case connected(username: String)
        case error(String)
    }
    
    public private(set) var status: ConnectionStatus = .disconnected {
        didSet {
            DispatchQueue.main.async {
                self.onStatusChanged?(self.status)
            }
        }
    }
    
    public var onStatusChanged: ((ConnectionStatus) -> Void)?
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var heartbeatTimer: DispatchSourceTimer?
    private var lastSequenceNumber: Int?
    private var isReconnecting = false
    private var reconnectAttempts = 0
    
    private var currentPlayingTrack: SGDoxMusicTrack?
    private var currentIsPlaying: Bool = false
    private var currentPlaybackTime: Double = 0.0
    private var currentTrackDuration: Double = 0.0
    private var externalAssetCache: [String: String] = [:]
    private var resolvingUrls: Set<String> = []
    
    private override init() {
        super.init()
        let config = URLSessionConfiguration.default
        self.urlSession = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue())
        
        if SGSimpleSettings.shared.discordRpcEnabled && !SGSimpleSettings.shared.discordRpcToken.isEmpty {
            self.connect()
        }
    }
    
    // MARK: - Connection Lifecycle
    
    public func connect() {
        guard SGSimpleSettings.shared.discordRpcEnabled else {
            self.disconnect()
            return
        }
        
        let token = SGSimpleSettings.shared.discordRpcToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            self.status = .error("Токен Discord не указан")
            return
        }
        
        self.disconnect(cleanStatus: false)
        self.status = .connecting
        
        guard let url = URL(string: "wss://gateway.discord.gg/?v=10&encoding=json") else { return }
        
        let task = self.urlSession?.webSocketTask(with: url)
        self.webSocketTask = task
        task?.resume()
        
        self.listenMessages()
    }
    
    public func disconnect(cleanStatus: Bool = true) {
        self.stopHeartbeat()
        self.webSocketTask?.cancel(with: .normalClosure, reason: nil)
        self.webSocketTask = nil
        self.lastSequenceNumber = nil
        if cleanStatus {
            self.status = .disconnected
        }
    }
    
    private func scheduleReconnect() {
        guard SGSimpleSettings.shared.discordRpcEnabled, !self.isReconnecting else { return }
        self.isReconnecting = true
        self.stopHeartbeat()
        
        self.reconnectAttempts += 1
        let delay = min(30.0, Double(self.reconnectAttempts) * 3.0)
        
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            self.isReconnecting = false
            if SGSimpleSettings.shared.discordRpcEnabled {
                self.connect()
            }
        }
    }
    
    // MARK: - WebSocket Receiving
    
    private func listenMessages() {
        self.webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .failure(let error):
                SGLogger.shared.log("DiscordRPC", "WebSocket receive error: \(error.localizedDescription)")
                self.status = .error("Ошибка соединения")
                self.scheduleReconnect()
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleGatewayPayload(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleGatewayPayload(text)
                    }
                @unknown default:
                    break
                }
                self.listenMessages()
            }
        }
    }
    
    // MARK: - Gateway Protocol
    
    private func handleGatewayPayload(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let op = json["op"] as? Int else {
            return
        }
        
        if let s = json["s"] as? Int {
            self.lastSequenceNumber = s
        }
        
        switch op {
        case 10: // Hello
            if let d = json["d"] as? [String: Any],
               let interval = d["heartbeat_interval"] as? Double {
                self.startHeartbeat(intervalMs: interval)
                self.sendIdentify()
            }
        case 11: // Heartbeat ACK
            break
        case 0: // Dispatch Event
            let event = json["t"] as? String ?? ""
            if event == "READY" {
                self.reconnectAttempts = 0
                var username = "Discord"
                if let d = json["d"] as? [String: Any],
                   let user = d["user"] as? [String: Any],
                   let name = user["username"] as? String {
                    username = name
                    if let globalName = user["global_name"] as? String, !globalName.isEmpty {
                        username = "\(globalName) (@\(name))"
                    }
                }
                self.status = .connected(username: username)
                
                // Immediately send current presence if already playing
                self.sendPresenceUpdate(track: self.currentPlayingTrack, isPlaying: self.currentIsPlaying)
            }
        case 7, 9: // Reconnect / Invalid Session
            self.scheduleReconnect()
        default:
            break
        }
    }
    
    private func startHeartbeat(intervalMs: Double) {
        self.stopHeartbeat()
        
        let queue = DispatchQueue(label: "org.doxgram.discord.heartbeat")
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let intervalSeconds = max(5.0, (intervalMs * 0.9) / 1000.0)
        
        timer.schedule(deadline: .now() + intervalSeconds, repeating: intervalSeconds)
        timer.setEventHandler { [weak self] in
            self?.sendHeartbeat()
        }
        timer.resume()
        self.heartbeatTimer = timer
    }
    
    private func stopHeartbeat() {
        self.heartbeatTimer?.cancel()
        self.heartbeatTimer = nil
    }
    
    private func sendHeartbeat() {
        let payload: [String: Any] = [
            "op": 1,
            "d": self.lastSequenceNumber as Any
        ]
        self.sendJson(payload)
    }
    
    private func sendIdentify() {
        let token = SGSimpleSettings.shared.discordRpcToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        
        let activity = self.buildActivity(track: self.currentPlayingTrack, isPlaying: self.currentIsPlaying)
        var activities: [[String: Any]] = []
        if let activity = activity {
            activities.append(activity)
        }
        
        let payload: [String: Any] = [
            "op": 2,
            "d": [
                "token": token,
                "properties": [
                    "os": "iOS",
                    "browser": "DoxGram iOS",
                    "device": "iPhone"
                ],
                "presence": [
                    "activities": activities,
                    "status": "online",
                    "since": 0,
                    "afk": false
                ]
            ]
        ]
        self.sendJson(payload)
    }
    
    // MARK: - Presence Update
    
    public func updatePlayback(track: SGDoxMusicTrack?, isPlaying: Bool, currentTime: Double = 0.0, duration: Double = 0.0) {
        let dur = duration > 0 ? duration : (track?.duration ?? 0.0)
        self.currentPlayingTrack = track
        self.currentIsPlaying = isPlaying
        self.currentPlaybackTime = currentTime
        self.currentTrackDuration = dur
        
        guard SGSimpleSettings.shared.discordRpcEnabled else { return }
        
        switch self.status {
        case .connected:
            self.sendPresenceUpdate(track: track, isPlaying: isPlaying)
        case .disconnected, .error:
            if isPlaying && !SGSimpleSettings.shared.discordRpcToken.isEmpty {
                self.connect()
            }
        case .connecting:
            break
        }
    }
    
    private func sendPresenceUpdate(track: SGDoxMusicTrack?, isPlaying: Bool) {
        var activities: [[String: Any]] = []
        if isPlaying, let activity = self.buildActivity(track: track, isPlaying: isPlaying) {
            activities.append(activity)
        }
        
        let payload: [String: Any] = [
            "op": 3,
            "d": [
                "since": NSNull(),
                "activities": activities,
                "status": "online",
                "afk": false
            ]
        ]
        self.sendJson(payload)
    }
    
    private func buildActivity(track: SGDoxMusicTrack?, isPlaying: Bool) -> [String: Any]? {
        guard isPlaying, let track = track else { return nil }
        
        let appName: String
        let appId: String?
        switch track.source {
        case .appleMusic:
            appName = "Apple Music"
            appId = "773825528921849856"
        case .spotify:
            appName = "Spotify"
            appId = nil
        case .telegram:
            appName = "DoxGram Music"
            appId = nil
        }
        
        var activity: [String: Any] = [
            "name": appName,
            "type": 2, // 2 = Listening to
            "details": track.title,
            "state": track.artist
        ]
        
        if let appId = appId {
            activity["application_id"] = appId
        }
        
        let now = Date().timeIntervalSince1970
        let startTimestamp = Int64(max(0.0, now - self.currentPlaybackTime) * 1000)
        var timestamps: [String: Any] = [
            "start": startTimestamp
        ]
        if self.currentTrackDuration > 0 {
            let endTimestamp = Int64((max(0.0, now - self.currentPlaybackTime) + self.currentTrackDuration) * 1000)
            if endTimestamp > startTimestamp {
                timestamps["end"] = endTimestamp
            }
        }
        activity["timestamps"] = timestamps
        
        var assets: [String: String] = [:]
        
        let trimmedAlbum = track.album.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAlbum.isEmpty {
            assets["large_text"] = trimmedAlbum
        }
        
        if let artwork = track.artworkUrl, !artwork.isEmpty {
            if let cachedMp = self.externalAssetCache[artwork] {
                assets["large_image"] = cachedMp
            } else if track.source == .spotify && artwork.contains("i.scdn.co/image/") {
                let id = artwork.components(separatedBy: "/").last ?? ""
                if !id.isEmpty {
                    assets["large_image"] = "spotify:\(id)"
                }
                self.resolveExternalAsset(imageUrl: artwork)
            } else if track.source == .appleMusic {
                // Use official appicon as placeholder so question mark icon is never displayed
                assets["large_image"] = "appicon"
                self.resolveExternalAsset(imageUrl: artwork)
            } else {
                self.resolveExternalAsset(imageUrl: artwork)
            }
        } else if track.source == .appleMusic {
            assets["large_image"] = "appicon"
        }
        
        switch track.source {
        case .appleMusic:
            assets["small_image"] = "appicon"
            assets["small_text"] = "Apple Music"
        case .spotify:
            assets["small_image"] = "spotify"
            assets["small_text"] = "Spotify"
        case .telegram:
            break
        }
        
        if !assets.isEmpty {
            activity["assets"] = assets
        }
        
        return activity
    }
    
    private func resolveExternalAsset(imageUrl: String) {
        guard !imageUrl.isEmpty, !imageUrl.hasPrefix("mp:"), self.externalAssetCache[imageUrl] == nil, !self.resolvingUrls.contains(imageUrl) else {
            return
        }
        
        let token = SGSimpleSettings.shared.discordRpcToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        
        self.resolvingUrls.insert(imageUrl)
        
        let appId = "773825528921849856"
        guard let url = URL(string: "https://discord.com/api/v9/applications/\(appId)/external-assets") else {
            self.resolvingUrls.remove(imageUrl)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = ["urls": [imageUrl]]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            self.resolvingUrls.remove(imageUrl)
            return
        }
        request.httpBody = body
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            self.resolvingUrls.remove(imageUrl)
            
            guard let data = data, error == nil,
                  let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let first = array.first,
                  let path = first["external_asset_path"] as? String else {
                return
            }
            
            let mpUrl = path.hasPrefix("mp:") ? path : "mp:\(path)"
            self.externalAssetCache[imageUrl] = mpUrl
            
            DispatchQueue.main.async {
                if self.currentIsPlaying, self.currentPlayingTrack?.artworkUrl == imageUrl {
                    self.sendPresenceUpdate(track: self.currentPlayingTrack, isPlaying: self.currentIsPlaying)
                }
            }
        }.resume()
    }
    
    private func sendJson(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let string = String(data: data, encoding: .utf8) else {
            return
        }
        
        self.webSocketTask?.send(.string(string)) { error in
            if let error = error {
                SGLogger.shared.log("DiscordRPC", "Send error: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Validation REST API
    
    public func validateToken(_ token: String, completion: @escaping @MainActor (Bool, String?) -> Void) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: "https://discord.com/api/v10/users/@me") else {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    completion(false, "Токен не может быть пустым")
                }
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(trimmed, forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        completion(false, error.localizedDescription)
                    }
                }
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        completion(false, "Нет ответа от сервера")
                    }
                }
                return
            }
            
            if httpResponse.statusCode == 200, let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let username = json["username"] as? String {
                let globalName = json["global_name"] as? String
                let displayName = (globalName != nil && !globalName!.isEmpty) ? "\(globalName!) (@\(username))" : username
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        completion(true, displayName)
                    }
                }
            } else if httpResponse.statusCode == 401 {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        completion(false, "Неверный токен Discord (401 Unauthorized)")
                    }
                }
            } else {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        completion(false, "Ошибка сервера (Код: \(httpResponse.statusCode))")
                    }
                }
            }
        }.resume()
    }
}
