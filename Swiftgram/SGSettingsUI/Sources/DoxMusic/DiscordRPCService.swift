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
    private var activeTrackId: String?
    private var activeStartTimestamp: Int64?
    private var isAudioSyncedForCurrentTrack = false
    private var externalAssetCache: [String: String] = [:]
    private var resolvingUrls: Set<String> = []
    private let doxgramIconUrl = "https://raw.githubusercontent.com/lxt3z/DoxGram/main/Telegram/Telegram-iOS/SGDefault.alticon/SGDefault%403x.png"
    
    private override init() {
        super.init()
        let config = URLSessionConfiguration.default
        self.urlSession = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue())
        
        if SGSimpleSettings.shared.discordRpcEnabled && !SGSimpleSettings.shared.discordRpcToken.isEmpty {
            self.resolveExternalAsset(imageUrl: self.doxgramIconUrl)
            self.connect()
        }
    }
    
    // MARK: - Connection Lifecycle
    
    public static func cleanToken(_ token: String) -> String {
        return token
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`“”«»"))
    }
    
    public func connect() {
        guard SGSimpleSettings.shared.discordRpcEnabled else {
            self.disconnect()
            return
        }
        
        let token = DiscordRPCService.cleanToken(SGSimpleSettings.shared.discordRpcToken)
        guard !token.isEmpty else {
            self.status = .error("Токен Discord не указан")
            return
        }
        
        self.resolveExternalAsset(imageUrl: self.doxgramIconUrl)
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
                
                // Pre-resolve DoxGram small icon right on connect
                self.resolveExternalAsset(imageUrl: self.doxgramIconUrl)
                
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
        let token = DiscordRPCService.cleanToken(SGSimpleSettings.shared.discordRpcToken)
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
                    "browser": "Discord iOS",
                    "device": "iPhone"
                ],
                "presence": [
                    "activities": activities,
                    "status": "online",
                    "since": 0,
                    "afk": false
                ],
                "intents": 0
            ]
        ]
        self.sendJson(payload)
    }
    
    // MARK: - Presence Update
    
    public func forceResync(track: SGDoxMusicTrack?, isPlaying: Bool, currentTime: Double, duration: Double) {
        self.activeStartTimestamp = nil
        self.isAudioSyncedForCurrentTrack = false
        self.updatePlayback(track: track, isPlaying: isPlaying, currentTime: currentTime, duration: duration)
    }
    
    public func updatePlayback(track: SGDoxMusicTrack?, isPlaying: Bool, currentTime: Double = 0.0, duration: Double = 0.0) {
        let dur = duration > 0 ? duration : (track?.duration ?? 0.0)
        let trackChanged = track?.id != self.activeTrackId
        if !isPlaying || trackChanged {
            self.activeTrackId = track?.id
            self.activeStartTimestamp = nil
            self.isAudioSyncedForCurrentTrack = false
        }
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
        let startTimestamp: Int64
        let expectedStart = now - self.currentPlaybackTime
        if self.activeTrackId == track.id, let existingStart = self.activeStartTimestamp, self.isAudioSyncedForCurrentTrack, abs(Double(existingStart) / 1000.0 - expectedStart) < 0.75 {
            // Keep the exact same established startTimestamp for this track so Discord client timer stays rock-steady and does not drift
            startTimestamp = existingStart
        } else {
            let computed = Int64(max(0.0, expectedStart) * 1000)
            startTimestamp = computed
            self.activeTrackId = track.id
            self.activeStartTimestamp = computed
            if self.currentPlaybackTime >= 0.15 {
                self.isAudioSyncedForCurrentTrack = true
            }
        }
        
        var timestamps: [String: Any] = [
            "start": startTimestamp
        ]
        if self.currentTrackDuration > 0 {
            let endTimestamp = startTimestamp + Int64(self.currentTrackDuration * 1000)
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
            } else if artwork.hasPrefix("mp:") {
                assets["large_image"] = artwork
            } else {
                self.resolveExternalAsset(imageUrl: artwork)
            }
        }
        
        if let cachedDox = self.externalAssetCache[self.doxgramIconUrl] {
            assets["small_image"] = cachedDox
            assets["small_text"] = "DoxGram iOS"
        } else {
            self.resolveExternalAsset(imageUrl: self.doxgramIconUrl)
        }
        
        if !assets.isEmpty {
            activity["assets"] = assets
        }
        
        activity["buttons"] = [
            "DoxGram GitHub"
        ]
        activity["metadata"] = [
            "button_urls": [
                "https://github.com/lxt3z/DoxGram"
            ]
        ]
        
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
            
            guard let data = data, error == nil else {
                return
            }
            
            var assetPath: String?
            if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                for item in array {
                    if let path = item["external_asset_path"] as? String {
                        assetPath = path
                        break
                    }
                }
            } else if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let path = dict["external_asset_path"] as? String {
                    assetPath = path
                } else if let items = dict["urls"] as? [[String: Any]] {
                    assetPath = items.first?["external_asset_path"] as? String
                }
            }
            
            guard let path = assetPath, !path.isEmpty else {
                return
            }
            
            let mpUrl = path.hasPrefix("mp:") ? path : "mp:\(path)"
            self.externalAssetCache[imageUrl] = mpUrl
            
            DispatchQueue.main.async {
                if self.currentIsPlaying, (self.currentPlayingTrack?.artworkUrl == imageUrl || imageUrl == self.doxgramIconUrl) {
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
    
    // MARK: - URLSessionWebSocketDelegate
    
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let reasonStr = reason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        SGLogger.shared.log("DiscordRPC", "WebSocket closed with code: \(closeCode.rawValue), reason: \(reasonStr)")
        let rawCode = closeCode.rawValue
        if rawCode == 4004 {
            self.status = .error("Неверный токен Discord (4004)")
            self.stopHeartbeat()
        } else if rawCode == 4013 {
            self.status = .error("Неверные intents (4013)")
            self.stopHeartbeat()
        } else if rawCode == 4014 {
            self.status = .error("Disallowed intent (4014)")
            self.stopHeartbeat()
        } else {
            self.scheduleReconnect()
        }
    }
    
    // MARK: - Validation REST API
    
    public func validateToken(_ token: String, completion: @escaping @MainActor (Bool, String?) -> Void) {
        let trimmed = DiscordRPCService.cleanToken(token)
        guard !trimmed.isEmpty, let url = URL(string: "https://discord.com/api/v10/users/@me") else {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    completion(false, "Токен не может быть пустым")
                }
            }
            return
        }
        
        let sendRequest: (String, Bool) -> Void = { [weak self] authHeader, canFallback in
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue(authHeader, forHTTPHeaderField: "Authorization")
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Discord/220.0", forHTTPHeaderField: "User-Agent")
            
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
                } else if httpResponse.statusCode == 401 && canFallback && !authHeader.hasPrefix("Bot ") {
                    // Try bot token format
                    var botRequest = URLRequest(url: url)
                    botRequest.httpMethod = "GET"
                    botRequest.setValue("Bot \(trimmed)", forHTTPHeaderField: "Authorization")
                    botRequest.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Discord/220.0", forHTTPHeaderField: "User-Agent")
                    URLSession.shared.dataTask(with: botRequest) { botData, botResp, _ in
                        if let botResp = botResp as? HTTPURLResponse, botResp.statusCode == 200,
                           let botData = botData,
                           let json = try? JSONSerialization.jsonObject(with: botData) as? [String: Any],
                           let username = json["username"] as? String {
                            DispatchQueue.main.async {
                                MainActor.assumeIsolated {
                                    completion(true, "Bot: \(username)")
                                }
                            }
                        } else {
                            DispatchQueue.main.async {
                                MainActor.assumeIsolated {
                                    completion(false, "Неверный токен Discord (401 Unauthorized)")
                                }
                            }
                        }
                    }.resume()
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
        
        sendRequest(trimmed, true)
    }
}
