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
            tcpOptions.enableKeepalive = true
            tcpOptions.keepaliveIdle = 10

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

        let session = SGTGWsSession(
            id: sessionId,
            connection: connection,
            urlSession: self.urlSession,
            queue: self.queue
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
    private var targetDc: Int = 4
    private var isClosed: Bool = false

    init(id: Int, connection: NWConnection, urlSession: URLSession, queue: DispatchQueue, onClose: @escaping (Int) -> Void) {
        self.id = id
        self.connection = connection
        self.urlSession = urlSession
        self.queue = queue
        self.onClose = onClose
    }

    func start() {
        self.connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.readSocksGreeting()
            case .failed, .cancelled:
                self.close()
            default:
                break
            }
        }
        self.connection.start(queue: self.queue)
    }

    private func readSocksGreeting() {
        self.connection.receive(minimumIncompleteLength: 2, maximumLength: 257) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
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
                if sendError != nil {
                    self?.close()
                } else {
                    self?.readSocksConnect()
                }
            })
        }
    }

    private func readSocksConnect() {
        self.connection.receive(minimumIncompleteLength: 4, maximumLength: 512) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if isComplete || error != nil || data == nil {
                self.close()
                return
            }
            guard let data = data, data.count >= 4, data[0] == 0x05, data[1] == 0x01 else {
                self.close()
                return
            }

            // Extract DC if IPv4 address or domain name
            let atyp = data[3]
            if atyp == 0x01 && data.count >= 10 {
                let b0 = data[4]
                let b1 = data[5]
                let b2 = data[6]
                let b3 = data[7]
                if b0 == 149 && b1 == 154 && b2 == 175 {
                    self.targetDc = 1
                } else if b0 == 149 && b1 == 154 && b2 == 167 {
                    self.targetDc = (b3 >= 150) ? 4 : 2
                } else if b0 == 149 && b1 == 154 && b2 == 171 {
                    self.targetDc = 3
                } else if b0 == 91 && b1 == 108 && (b2 == 56 || b2 == 57 || b2 == 58 || b2 == 59) {
                    self.targetDc = 5
                } else if b0 == 91 && b1 == 108 {
                    self.targetDc = 4
                }
            } else if atyp == 0x03 && data.count >= 5 {
                let domainLength = Int(data[4])
                if data.count >= 5 + domainLength {
                    let domainData = data.subdata(in: 5..<(5 + domainLength))
                    if let domainStr = String(data: domainData, encoding: .utf8)?.lowercased() {
                        if domainStr.contains("venus") || domainStr.contains("dc1") {
                            self.targetDc = 1
                        } else if domainStr.contains("aurora") || domainStr.contains("dc2") {
                            self.targetDc = 2
                        } else if domainStr.contains("vesta") || domainStr.contains("dc3") {
                            self.targetDc = 3
                        } else if domainStr.contains("pluto") || domainStr.contains("dc4") {
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
                if sendError != nil {
                    self?.close()
                } else {
                    self?.connectWebSocket()
                }
            })
        }
    }

    private func connectWebSocket() {
        let customWorker = SGSimpleSettings.shared.tgWsProxyCustomWorker.trimmingCharacters(in: .whitespacesAndNewlines)
        let wsUrlString: String

        if !customWorker.isEmpty {
            let cleaned = customWorker
                .replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "")
                .replacingOccurrences(of: "wss://", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if cleaned.contains("/") {
                wsUrlString = "wss://\(cleaned)"
            } else {
                wsUrlString = "wss://\(cleaned)/apiws"
            }
        } else {
            let domains = SGTGWsProxy.defaultDomains
            let selectedDomain = domains[abs(self.id) % domains.count]
            wsUrlString = "wss://kws\(self.targetDc).\(selectedDomain)/apiws"
        }

        guard let url = URL(string: wsUrlString) else {
            SGLogger.shared.log("SGTGWsProxy", "Invalid WS URL: \(wsUrlString)")
            self.close()
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15.0
        request.setValue("binary", forHTTPHeaderField: "Sec-WebSocket-Protocol")

        let task = self.urlSession.webSocketTask(with: request)
        self.webSocketTask = task
        task.resume()

        self.startBridge()
    }

    private func startBridge() {
        self.readFromClient()
        self.readFromWebSocket()
    }

    private func readFromClient() {
        self.connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self, !self.isClosed else { return }
            if let data = data, !data.isEmpty {
                self.webSocketTask?.send(.data(data)) { [weak self] sendError in
                    if sendError != nil {
                        self?.close()
                    }
                }
            }
            if isComplete || error != nil {
                self.close()
                return
            }
            self.readFromClient()
        }
    }

    private func readFromWebSocket() {
        self.webSocketTask?.receive { [weak self] result in
            guard let self = self, !self.isClosed else { return }
            switch result {
            case let .success(message):
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
                    self.connection.send(content: data, completion: .contentProcessed { [weak self] sendError in
                        if sendError != nil {
                            self?.close()
                        }
                    })
                }
                self.readFromWebSocket()
            case .failure:
                self.close()
            }
        }
    }

    func cancel() {
        self.close()
    }

    private func close() {
        guard !self.isClosed else { return }
        self.isClosed = true

        self.connection.cancel()
        self.webSocketTask?.cancel(with: .goingAway, reason: nil)
        self.webSocketTask = nil

        self.onClose(self.id)
    }
}
