import Foundation
import SGSimpleSettings
import SGLogging

public final class DiscordRPCService: NSObject, URLSessionWebSocketDelegate {
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
    
    public func updatePlayback(track: SGDoxMusicTrack?, isPlaying: Bool) {
        self.currentPlayingTrack = track
        self.currentIsPlaying = isPlaying
        
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
        
        var activity: [String: Any] = [
            "name": "DoxGram Music",
            "type": 2, // 2 = Listening to
            "details": track.title,
            "state": "by \(track.artist)",
            "timestamps": [
                "start": Int64(Date().timeIntervalSince1970 * 1000)
            ]
        ]
        
        var assets: [String: String] = [
            "large_text": "\(track.title) — \(track.artist)"
        ]
        
        if let artwork = track.artworkUrl, !artwork.isEmpty {
            assets["large_image"] = artwork
        }
        
        let sourceName = track.source == .appleMusic ? "Apple Music" : (track.source == .spotify ? "Spotify" : "Telegram")
        assets["small_text"] = "via \(sourceName)"
        
        activity["assets"] = assets
        return activity
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
    
    public func validateToken(_ token: String, completion: @escaping (Bool, String?) -> Void) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: "https://discord.com/api/v10/users/@me") else {
            completion(false, "Токен не может быть пустым")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(trimmed, forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(false, error.localizedDescription) }
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                DispatchQueue.main.async { completion(false, "Нет ответа от сервера") }
                return
            }
            
            if httpResponse.statusCode == 200, let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let username = json["username"] as? String {
                let globalName = json["global_name"] as? String
                let displayName = (globalName != nil && !globalName!.isEmpty) ? "\(globalName!) (@\(username))" : username
                DispatchQueue.main.async { completion(true, displayName) }
            } else if httpResponse.statusCode == 401 {
                DispatchQueue.main.async { completion(false, "Неверный токен Discord (401 Unauthorized)") }
            } else {
                DispatchQueue.main.async { completion(false, "Ошибка сервера (Код: \(httpResponse.statusCode))") }
            }
        }.resume()
    }
}
