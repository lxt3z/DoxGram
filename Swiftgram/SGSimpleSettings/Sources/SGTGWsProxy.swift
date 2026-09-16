import Foundation
import Network
import SGLogging

@available(iOS 12.0, *)
public final class SGTGWsProxy {

    public static let shared = SGTGWsProxy()

    private let queue = DispatchQueue(label: "org.doxgram.tgwsproxy", qos: .userInitiated)
    private var listener: NWListener?
    private var activeSessions: [Int: SGTGWsSession] = [:]
    private var sessionCounter: Int = 0
    private var isRunning: Bool = false

    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 3600.0
        config.httpMaximumConnectionsPerHost = 64
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
        ]
        return URLSession(configuration: config)
    }()

    // Verified fallback domains from Flowseal tg-ws-proxy
    public static let defaultDomains: [String] = [
        "pclead.co.uk",
        "offshor.co.uk",
        "cakeisalie.co.uk",
        "noskomnadzor.co.uk",
        "lovetrue.co.uk",
        "sorokdva.co.uk",
        "pyatdesyatdva.co.uk",
        "kartoshka.co.uk",
        "sorokodin.co.uk",
        "pyatdesyatodin.co.uk",
        "notelega.co.uk",
        "ebally.co.uk",
        "nebally.co.uk",
        "havegreatday.co.uk",
        "pomogite.co.uk",
        "fixtelega.co.uk",
        "sadnews.co.uk",
        "onedaychamp.co.uk",
        "stopblocking.co.uk",
        "nothingthere.co.uk"
    ]

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.applicationWillEnterForeground),
            name: Notification.Name("UIApplicationWillEnterForegroundNotification"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.applicationDidEnterBackground),
            name: Notification.Name("UIApplicationDidEnterBackgroundNotification"),
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        self.stop()
    }

    @objc private func applicationWillEnterForeground() {
        self.queue.async {
            if SGSimpleSettings.shared.tgWsProxyEnabled && !self.isRunning {
                self.startInternal()
            }
        }
    }

    @objc private func applicationDidEnterBackground() {
        self.queue.async {
            // Close active proxy sessions on background to avoid draining battery with sockets
            for session in self.activeSessions.values {
                session.cancel()
            }
            self.activeSessions.removeAll()
        }
    }

    public func start() {
        self.queue.async {
            self.startInternal()
        }
    }

    public func stop() {
        self.queue.async {
            self.stopInternal()
        }
    }

    private func startInternal() {
        guard !self.isRunning else { return }
        let portValue = UInt16(SGSimpleSettings.shared.tgWsProxyPort > 0 ? SGSimpleSettings.shared.tgWsProxyPort : 10855)
        guard let port = NWEndpoint.Port(rawValue: portValue) else {
            SGLogger.shared.log("SGTGWsProxy", "Invalid port \(portValue)")
            return
        }

        do {
            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.noDelay = true
            tcpOptions.enableKeepalive = true
            tcpOptions.keepaliveIdle = 10
            tcpOptions.keepaliveInterval = 5
            tcpOptions.keepaliveCount = 3

            let params = NWParameters(tls: nil, tcp: tcpOptions)
            params.allowLocalEndpointReuse = true

            let newListener = try NWListener(using: params, on: port)
            newListener.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }
            newListener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    SGLogger.shared.log("SGTGWsProxy", "Proxy listener ready on 127.0.0.1:\(portValue)")
                case let .failed(error):
                    SGLogger.shared.log("SGTGWsProxy", "Proxy listener failed: \(error)")
                    self?.queue.async {
                        self?.stopInternal()
                    }
                case .cancelled:
                    SGLogger.shared.log("SGTGWsProxy", "Proxy listener cancelled")
                default:
                    break
                }
            }

            newListener.start(queue: self.queue)
            self.listener = newListener
            self.isRunning = true
            SGLogger.shared.log("SGTGWsProxy", "Started TG WS Proxy on port \(portValue)")
        } catch {
            SGLogger.shared.log("SGTGWsProxy", "Failed to start listener: \(error)")
        }
    }

    private func stopInternal() {
        self.isRunning = false
        self.listener?.cancel()
        self.listener = nil

        for session in self.activeSessions.values {
            session.cancel()
        }
        self.activeSessions.removeAll()
        SGLogger.shared.log("SGTGWsProxy", "Stopped TG WS Proxy")
    }

    private func handleNewConnection(_ connection: NWConnection) {
        self.sessionCounter += 1
        let sessionId = self.sessionCounter

        let sessionQueue = DispatchQueue(label: "org.doxgram.tgwsproxy.session.\(sessionId)", qos: .userInitiated)

        let session = SGTGWsSession(
            id: sessionId,
            connection: connection,
            urlSession: self.urlSession,
            queue: sessionQueue
        ) { [weak self] id in
            self?.queue.async {
                self?.activeSessions.removeValue(forKey: id)
            }
        }
        self.activeSessions[sessionId] = session
        session.start()
    }
}

/// Handles a single SOCKS5 connection from Telegram and bridges to a WebSocket
@available(iOS 12.0, *)
private final class SGTGWsSession {
    let id: Int
    let connection: NWConnection
    let urlSession: URLSession
    let queue: DispatchQueue
    let onClose: (Int) -> Void

    private var webSocketTask: URLSessionWebSocketTask?
    private var pingTimer: DispatchSourceTimer?
    private var targetDc: Int = 4
    private var targetIp: String?
    private var isClosed: Bool = false
    private var candidateDomains: [String] = []
    private var currentDomainIndex: Int = 0
    private var attemptCount: Int = 0
    private var pendingClientData: [Data] = []
    private var hasReceivedWsData: Bool = false

    // Pipelining and backpressure controls
    private var isReadingClient: Bool = false
    private var isReadingWebSocket: Bool = false
    private var pendingSocketSends: Int = 0
    private let maxPendingSocketSends: Int = 16
    private var pendingWsSends: Int = 0
    private let maxPendingWsSends: Int = 8

    init(id: Int, connection: NWConnection, urlSession: URLSession, queue: DispatchQueue, onClose: @escaping (Int) -> Void) {
        self.id = id
        self.connection = connection
        self.urlSession = urlSession
        self.queue = queue
        self.onClose = onClose

        let domains = SGTGWsProxy.defaultDomains
        let startIndex = abs(id) % domains.count
        self.candidateDomains = (startIndex..<domains.count).map { domains[$0] } + (0..<startIndex).map { domains[$0] }
    }

    func start() {
        self.connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            self.queue.async {
                guard !self.isClosed else { return }
                switch state {
                case .ready:
                    self.readSocksGreeting()
                case .failed, .cancelled:
                    self.close()
                default:
                    break
                }
            }
        }
        self.connection.start(queue: self.queue)
    }

    private func readSocksGreeting() {
        self.connection.receive(minimumIncompleteLength: 2, maximumLength: 257) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            self.queue.async {
                guard !self.isClosed else { return }
                if isComplete || error != nil || data == nil {
                    self.close()
                    return
                }
                guard let data = data, data.count >= 2, data[0] == 0x05 else {
                    self.close()
                    return
                }

                // Reply with SOCKS5 greeting response (No authentication required: 0x05, 0x00)
                let response = Data([0x05, 0x00])
                self.connection.send(content: response, completion: .contentProcessed { [weak self] sendError in
                    guard let self = self else { return }
                    self.queue.async {
                        guard !self.isClosed else { return }
                        if sendError != nil {
                            self.close()
                        } else {
                            self.readSocksConnect()
                        }
                    }
                })
            }
        }
    }

    private func readSocksConnect() {
        self.connection.receive(minimumIncompleteLength: 4, maximumLength: 512) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            self.queue.async {
                guard !self.isClosed else { return }
                if isComplete || error != nil || data == nil {
                    self.close()
                    return
                }
                guard let data = data, data.count >= 4, data[0] == 0x05, data[1] == 0x01 else {
                    self.close()
                    return
                }

                // Extract DC and target IP if IPv4 address, IPv6, or domain name
                let atyp = data[3]
                if atyp == 0x01 && data.count >= 10 {
                    let b0 = data[4]
                    let b1 = data[5]
                    let b2 = data[6]
                    let b3 = data[7]
                    let ipStr = "\(b0).\(b1).\(b2).\(b3)"
                    self.targetIp = ipStr

                    if b0 == 149 && b1 == 154 {
                        // Telegram ASN AS44907: 149.154.160.0/20
                        if b2 >= 160 && b2 <= 164 {
                            self.targetDc = 2 // DC 2 (Amsterdam)
                        } else if b2 == 165 || b2 == 166 {
                            self.targetDc = 4 // DC 4 (Amsterdam)
                        } else if b2 == 167 {
                            // 149.154.167.0/24: DC 2 (40..51) vs DC 4 (.91, .150..220 media)
                            if b3 == 91 || b3 >= 150 {
                                self.targetDc = 4 // DC 4 media & primary
                            } else {
                                self.targetDc = 2 // DC 2
                            }
                        } else if b2 >= 168 && b2 <= 170 {
                            self.targetDc = 4 // DC 4
                        } else if b2 == 171 {
                            self.targetDc = 5 // DC 5 (Singapore)
                        } else if b2 >= 172 && b2 <= 174 {
                            self.targetDc = 1 // DC 1 (Miami)
                        } else if b2 == 175 {
                            if b3 >= 100 && b3 <= 120 {
                                self.targetDc = 3 // DC 3 (Miami)
                            } else {
                                self.targetDc = 1 // DC 1 (Miami)
                            }
                        }
                    } else if b0 == 91 && b1 == 108 {
                        // Telegram ASN AS62041: 91.108.0.0/16
                        if b2 >= 4 && b2 <= 7 {
                            self.targetDc = 2 // 91.108.4.0/22 (DC 2)
                        } else if b2 >= 8 && b2 <= 11 {
                            self.targetDc = 4 // 91.108.8.0/22 (DC 4)
                        } else if b2 >= 12 && b2 <= 15 {
                            self.targetDc = 4 // 91.108.12.0/22 (DC 4)
                        } else if b2 >= 16 && b2 <= 19 {
                            self.targetDc = 2 // 91.108.16.0/22 (DC 2)
                        } else if b2 >= 20 && b2 <= 23 {
                            self.targetDc = 4 // 91.108.20.0/22 (DC 4)
                        } else if b2 >= 56 && b2 <= 59 {
                            self.targetDc = 5 // 91.108.56.0/22 (DC 5)
                        } else {
                            self.targetDc = 4
                        }
                    } else if b0 == 95 && b1 == 161 && b2 == 76 {
                        self.targetDc = 2 // 95.161.76.100 is DC 2
                    } else if b0 == 91 && b1 == 105 && (b2 == 192 || b2 == 193) {
                        self.targetDc = 2 // 91.105.192.0/23 is DC 2
                    } else if b0 == 185 && b1 == 76 && b2 == 151 {
                        self.targetDc = 2 // 185.76.151.0/24 is DC 2
                    }
                } else if atyp == 0x04 && data.count >= 20 {
                    // IPv6: Telegram uses 2001:b28:f23d:f00X:: / 2001:67c:4e8:f00X::
                    for i in 4..<19 {
                        if data[i] == 0xf0 {
                            let next = data[i + 1]
                            if next >= 1 && next <= 5 {
                                self.targetDc = Int(next)
                                break
                            }
                        }
                    }
                } else if atyp == 0x03 && data.count >= 5 {
                    let domainLength = Int(data[4])
                    if data.count >= 5 + domainLength {
                        let domainData = data.subdata(in: 5..<(5 + domainLength))
                        if let domainStr = String(data: domainData, encoding: .utf8)?.lowercased() {
                            if domainStr.contains("pluto") || domainStr.contains("dc1") {
                                self.targetDc = 1
                            } else if domainStr.contains("venus") || domainStr.contains("dc2") {
                                self.targetDc = 2
                            } else if domainStr.contains("aurora") || domainStr.contains("dc3") {
                                self.targetDc = 3
                            } else if domainStr.contains("vesta") || domainStr.contains("dc4") {
                                self.targetDc = 4
                            } else if domainStr.contains("flora") || domainStr.contains("dc5") {
                                self.targetDc = 5
                            }
                        }
                    }
                }

                // SOCKS5 success reply: 05 00 00 01 (127.0.0.1:port)
                let port = UInt16(SGSimpleSettings.shared.tgWsProxyPort > 0 ? SGSimpleSettings.shared.tgWsProxyPort : 10855)
                let reply = Data([
                    0x05, 0x00, 0x00, 0x01,
                    127, 0, 0, 1,
                    UInt8(port >> 8), UInt8(port & 0xFF)
                ])
                self.connection.send(content: reply, completion: .contentProcessed { [weak self] sendError in
                    guard let self = self else { return }
                    self.queue.async {
                        guard !self.isClosed else { return }
                        if sendError != nil {
                            self.close()
                        } else {
                            self.readFromClient()
                            self.connectWebSocket()
                        }
                    }
                })
            }
        }
    }

    private func connectWebSocket() {
        guard !self.isClosed else { return }
        guard self.currentDomainIndex < self.candidateDomains.count else {
            SGLogger.shared.log("SGTGWsProxy", "Session \(self.id): all candidate domains exhausted")
            self.close()
            return
        }

        let customWorker = SGSimpleSettings.shared.tgWsProxyCustomWorker.trimmingCharacters(in: .whitespacesAndNewlines)
        let wsUrlString: String

        let defaultDcIps: [Int: String] = [
            1: "149.154.175.50",
            2: "149.154.167.51",
            3: "149.154.175.100",
            4: "149.154.167.91",
            5: "149.154.171.5"
        ]
        let dst = self.targetIp ?? defaultDcIps[self.targetDc] ?? "149.154.167.91"

        if !customWorker.isEmpty {
            let cleaned = customWorker
                .replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "")
                .replacingOccurrences(of: "wss://", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if cleaned.contains("?") {
                wsUrlString = "wss://\(cleaned)&dst=\(dst)&dc=\(self.targetDc)"
            } else if cleaned.contains("/") {
                wsUrlString = "wss://\(cleaned)?dst=\(dst)&dc=\(self.targetDc)"
            } else {
                wsUrlString = "wss://\(cleaned)/apiws?dst=\(dst)&dc=\(self.targetDc)"
            }
        } else {
            let domain = self.candidateDomains[self.currentDomainIndex]
            if let targetIp = self.targetIp {
                wsUrlString = "wss://kws\(self.targetDc).\(domain)/apiws?dst=\(targetIp)&dc=\(self.targetDc)"
            } else {
                wsUrlString = "wss://kws\(self.targetDc).\(domain)/apiws"
            }
        }

        guard let url = URL(string: wsUrlString) else {
            SGLogger.shared.log("SGTGWsProxy", "Invalid WS URL: \(wsUrlString)")
            self.close()
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        let isFakeTLS = SGSimpleSettings.shared.tgWsProxyFakeTLS
        if isFakeTLS {
            let hostDomain = url.host ?? "cloudflare.com"
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
            request.setValue("https://\(hostDomain)", forHTTPHeaderField: "Origin")
            request.setValue("ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7", forHTTPHeaderField: "Accept-Language")
            request.setValue("permessage-deflate; client_max_window_bits", forHTTPHeaderField: "Sec-WebSocket-Extensions")
            request.setValue("websocket", forHTTPHeaderField: "Sec-Fetch-Dest")
            request.setValue("websocket", forHTTPHeaderField: "Sec-Fetch-Mode")
            request.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
            request.setValue("no-cache", forHTTPHeaderField: "Pragma")
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        } else {
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
            request.setValue("https://web.telegram.org", forHTTPHeaderField: "Origin")
            request.setValue("binary", forHTTPHeaderField: "Sec-WebSocket-Protocol")
            request.setValue("no-cache", forHTTPHeaderField: "Pragma")
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        }

        if #available(iOS 13.0, *) {
            let task = self.urlSession.webSocketTask(with: request)
            task.maximumMessageSize = 64 * 1024 * 1024
            self.webSocketTask = task
            task.resume()

            for chunk in self.pendingClientData {
                task.send(.data(chunk)) { _ in }
            }

            self.startPingTimer()
            self.readFromWebSocket()
        } else {
            self.close()
        }
    }

    private func startPingTimer() {
        self.stopPingTimer()
        let timer = DispatchSource.makeTimerSource(queue: self.queue)
        timer.schedule(deadline: .now() + 50.0, repeating: 50.0)
        timer.setEventHandler { [weak self] in
            guard let self = self, !self.isClosed else { return }
            if #available(iOS 13.0, *) {
                self.webSocketTask?.sendPing { [weak self] error in
                    if let error = error {
                        SGLogger.shared.log("SGTGWsProxy", "Session \(self?.id ?? 0): WS ping error: \(error)")
                    }
                }
            }
        }
        timer.resume()
        self.pingTimer = timer
    }

    private func stopPingTimer() {
        self.pingTimer?.cancel()
        self.pingTimer = nil
    }

    private func readFromClient() {
        guard !self.isClosed, !self.isReadingClient else { return }
        guard self.pendingWsSends < self.maxPendingWsSends else { return }
        self.isReadingClient = true

        self.connection.receive(minimumIncompleteLength: 1, maximumLength: 131072) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            self.queue.async {
                self.isReadingClient = false
                guard !self.isClosed else { return }

                if isComplete || error != nil {
                    self.close()
                    return
                }
                guard let data = data, !data.isEmpty else {
                    self.readFromClient()
                    return
                }

                if !self.hasReceivedWsData {
                    let totalBuffered = self.pendingClientData.reduce(0) { $0 + $1.count }
                    if totalBuffered < 524288 {
                        self.pendingClientData.append(data)
                    }
                }

                if #available(iOS 13.0, *) {
                    guard let task = self.webSocketTask else {
                        self.close()
                        return
                    }
                    self.pendingWsSends += 1
                    task.send(.data(data)) { [weak self] sendError in
                        guard let self = self else { return }
                        self.queue.async {
                            guard !self.isClosed else { return }
                            if let sendError = sendError {
                                SGLogger.shared.log("SGTGWsProxy", "Session \(self.id): WS send error: \(sendError)")
                                self.close()
                                return
                            }
                            self.pendingWsSends = max(0, self.pendingWsSends - 1)
                            if !self.isReadingClient && self.pendingWsSends < self.maxPendingWsSends {
                                self.readFromClient()
                            }
                        }
                    }

                    // Pipelining: read next socket chunk immediately if below backpressure limit!
                    if self.pendingWsSends < self.maxPendingWsSends {
                        self.readFromClient()
                    }
                } else {
                    self.close()
                }
            }
        }
    }

    private func readFromWebSocket() {
        guard #available(iOS 13.0, *), let task = self.webSocketTask else { return }
        guard !self.isClosed, !self.isReadingWebSocket else { return }
        guard self.pendingSocketSends < self.maxPendingSocketSends else { return }
        self.isReadingWebSocket = true

        task.receive { [weak self] result in
            guard let self = self else { return }
            self.queue.async {
                self.isReadingWebSocket = false
                guard !self.isClosed else { return }

                switch result {
                case let .success(message):
                    self.hasReceivedWsData = true
                    self.pendingClientData.removeAll(keepingCapacity: false)

                    let dataToSend: Data?
                    switch message {
                    case let .data(data):
                        dataToSend = data
                    case let .string(text):
                        dataToSend = text.data(using: .utf8)
                    @unknown default:
                        dataToSend = nil
                    }

                    if let data = dataToSend, !data.isEmpty {
                        self.pendingSocketSends += 1
                        self.connection.send(content: data, completion: .contentProcessed { [weak self] sendError in
                            guard let self = self else { return }
                            self.queue.async {
                                guard !self.isClosed else { return }
                                if sendError != nil {
                                    self.close()
                                    return
                                }
                                self.pendingSocketSends = max(0, self.pendingSocketSends - 1)
                                if !self.isReadingWebSocket && self.pendingSocketSends < self.maxPendingSocketSends {
                                    self.readFromWebSocket()
                                }
                            }
                        })
                    }

                    // Pipelining: request next WS frame immediately if below backpressure limit!
                    if self.pendingSocketSends < self.maxPendingSocketSends {
                        self.readFromWebSocket()
                    }

                case let .failure(error):
                    let isCustom = !SGSimpleSettings.shared.tgWsProxyCustomWorker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    if !self.hasReceivedWsData && self.attemptCount < 3 && !isCustom {
                        self.attemptCount += 1
                        self.currentDomainIndex += 1
                        SGLogger.shared.log("SGTGWsProxy", "Session \(self.id): WS connect failed (\(error)), failing over to next domain (\(self.attemptCount)/3)...")
                        self.stopPingTimer()
                        self.webSocketTask?.cancel(with: .goingAway, reason: nil)
                        self.webSocketTask = nil
                        self.connectWebSocket()
                    } else {
                        self.close()
                    }
                }
            }
        }
    }

    func cancel() {
        self.queue.async {
            self.close()
        }
    }

    private func close() {
        guard !self.isClosed else { return }
        self.isClosed = true

        self.stopPingTimer()
        self.connection.cancel()
        if #available(iOS 13.0, *) {
            self.webSocketTask?.cancel(with: .goingAway, reason: nil)
            self.webSocketTask = nil
        }

        self.onClose(self.id)
    }
}
