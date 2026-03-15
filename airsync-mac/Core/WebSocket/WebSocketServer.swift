//
//  WebSocketServer.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-07-28.
//

import Foundation
import Swifter
import CryptoKit
import UserNotifications
import Combine

class WebSocketServer: ObservableObject {
    static let shared = WebSocketServer()
    
    internal var server = HttpServer()
    internal var activeSessions: [WebSocketSession] = []
    internal var primarySessionID: ObjectIdentifier?
    internal var pingTimer: Timer?
    internal let pingInterval: TimeInterval = 5.0
    internal var lastActivity: [ObjectIdentifier: Date] = [:]
    internal let activityTimeout: TimeInterval = 11.0
    
    @Published var symmetricKey: SymmetricKey?
    @Published var localPort: UInt16?
    @Published var localIPAddress: String?
    @Published var connectedDevice: Device?
    @Published var notifications: [Notification] = []
    @Published var deviceStatus: DeviceStatus?

    internal var lastKnownIP: String?
    internal var networkMonitorTimer: Timer?
    internal let networkCheckInterval: TimeInterval = 10.0
    internal let lock = NSRecursiveLock()
    internal let fileQueue = DispatchQueue(label: "com.airsync.fileio")
    
    internal var servers: [String: HttpServer] = [:]
    internal var isListeningOnAll = false

    internal var incomingFiles: [String: IncomingFileIO] = [:]
    internal var incomingFilesChecksum: [String: String] = [:]
    internal var incomingReceivedChunks: [String: Set<Int>] = [:]
    internal var outgoingAcks: [String: Set<Int>] = [:]

    internal let maxChunkRetries = 3
    internal let ackWaitMs: UInt16 = 2000
    internal let lifecycleQueue = DispatchQueue(label: "com.airsync.websocket.lifecycle", qos: .userInitiated)
    internal var pendingRestartWorkItem: DispatchWorkItem?

    internal var lastKnownAdapters: [(name: String, address: String)] = []
    internal var lastLoggedSelectedAdapter: (name: String, address: String)? = nil

    // LAN authentication: tracks which sessions have completed HMAC challenge-response
    internal var authenticatedSessions: Set<ObjectIdentifier> = []
    internal var pendingChallenges: [ObjectIdentifier: Data] = [:]

    init() {
        loadOrGenerateSymmetricKey()
        setupWebSocket(for: server)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let err = error {
                print("[websocket] Notification auth error: \(err)")
            } else {
                print("[websocket] Notification permission granted: \(granted)")
            }
        }
    }

    /// Starts the WebSocket server on the specified port.
    /// Handles binding to a specific network adapter or all available interfaces if "auto" is selected.
    func start(port: UInt16 = Defaults.serverPort) {
        DispatchQueue.main.async {
            AppState.shared.webSocketStatus = .starting
        }

        let adapterName = AppState.shared.selectedNetworkAdapterName
        let adapters = getAvailableNetworkAdapters()
        
        lifecycleQueue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                guard port > 0 && port <= 65_535 else {
                    let msg = "[websocket] Invalid port \(port)."
                    DispatchQueue.main.async { AppState.shared.webSocketStatus = .failed(error: msg) }
                    return
                }

                self.lock.lock()
                self.stopAllServers()
                
                if let specificAdapter = adapterName {
                    self.isListeningOnAll = false
                    let server = HttpServer()
                    self.setupWebSocket(for: server)
                    try self.startServerWithRetry(server, port: port)
                    self.servers[specificAdapter] = server
                    
                    let ip = self.getLocalIPAddress(adapterName: specificAdapter)
                    DispatchQueue.main.async {
                        self.localPort = port
                        self.localIPAddress = ip
                        AppState.shared.webSocketStatus = .started(port: port, ip: ip)
                        self.lastKnownIP = ip
                    }
                    print("[websocket] WebSocket server started at ws://\(ip ?? "unknown"):\(port)/socket on \(specificAdapter)")
                } else {
                    self.isListeningOnAll = true
                    var startedAny = false
                    for adapter in adapters {
                        do {
                            let server = HttpServer()
                            self.setupWebSocket(for: server)
                            if !startedAny {
                                try self.startServerWithRetry(server, port: port)
                                self.servers["any"] = server
                                startedAny = true
                            }
                        } catch {
                            print("[websocket] Failed to start on \(adapter.name): \(error)")
                        }
                    }
                    
                    if startedAny {
                        let ipList = self.getLocalIPAddress(adapterName: nil)
                        DispatchQueue.main.async {
                            self.localPort = port
                            self.localIPAddress = "Multiple"
                            AppState.shared.webSocketStatus = .started(port: port, ip: "Multiple")
                            self.lastKnownIP = ipList
                        }
                        print("[websocket] WebSocket server started on all available adapters at port \(port)")
                    }
                }
                self.lock.unlock()

                self.startNetworkMonitoring()
            } catch {
                self.lock.unlock()
                DispatchQueue.main.async { AppState.shared.webSocketStatus = .failed(error: "\(error)") }
            }
        }
    }

    internal func stopAllServers() {
        for (_, server) in servers {
            server.stop()
        }
        servers.removeAll()
    }

    private func startServerWithRetry(_ server: HttpServer, port: UInt16, maxAttempts: Int = 3) throws {
        var lastError: Error?
        for attempt in 1...maxAttempts {
            do {
                try server.start(in_port_t(port))
                if attempt > 1 {
                    print("[websocket] Bind succeeded on attempt \(attempt)/\(maxAttempts) for port \(port)")
                }
                return
            } catch {
                lastError = error
                let lowered = String(describing: error).lowercased()
                let isAddressInUse = lowered.contains("address already in use")
                    || lowered.contains("port in use")
                    || lowered.contains("bind")
                    || lowered.contains("in use")

                if !isAddressInUse || attempt == maxAttempts {
                    throw error
                }

                // A rapid restart may race the previous listener teardown.
                // Back off briefly and retry binding.
                let delaySeconds = Double(200 * attempt) / 1000.0
                print("[websocket] Port \(port) busy, retrying bind in \(Int(delaySeconds * 1000))ms (attempt \(attempt + 1)/\(maxAttempts))")
                Thread.sleep(forTimeInterval: delaySeconds)
            }
        }

        if let lastError {
            throw lastError
        }
    }

    func requestRestart(reason: String, delay: TimeInterval = 0.35, port: UInt16? = nil) {
        lock.lock()
        pendingRestartWorkItem?.cancel()
        let restartPort = port ?? localPort ?? Defaults.serverPort
        lock.unlock()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            print("[websocket] Restart requested: \(reason)")
            self.stop()
            self.start(port: restartPort)
        }

        lock.lock()
        pendingRestartWorkItem = workItem
        lock.unlock()

        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func stop() {
        lock.lock()
        pendingRestartWorkItem?.cancel()
        pendingRestartWorkItem = nil
        stopAllServers()
        activeSessions.removeAll()
        incomingReceivedChunks.removeAll()
        primarySessionID = nil
        authenticatedSessions.removeAll()
        pendingChallenges.removeAll()
        resetReplayGuard()
        stopPing()
        lock.unlock()
        DispatchQueue.main.async { AppState.shared.webSocketStatus = .stopped }
        stopNetworkMonitoring()
    }

    /// Returns true only when a primary LAN WebSocket session is currently active.
    func hasActiveLocalSession() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let pId = primarySessionID else { return false }
        return activeSessions.contains(where: { ObjectIdentifier($0) == pId })
    }

    /// Configures WebSocket routes and event callbacks.
    /// Handles message decryption before passing payload to the message router.
    private func setupWebSocket(for server: HttpServer) {
        server["/socket"] = websocket(
            text: { [weak self] session, text in
                guard let self = self else { return }
                let sessionId = ObjectIdentifier(session)
                let decryptedText: String
                if let key = self.symmetricKey {
                    decryptedText = decryptMessage(text, using: key) ?? ""
                } else {
                    decryptedText = text
                }

                if decryptedText.contains("\"type\":\"pong\"") {
                    self.lock.lock()
                    self.lastActivity[sessionId] = Date()
                    self.lock.unlock()
                    return
                }

                if let data = decryptedText.data(using: .utf8) {
                    do {
                        let message = try JSONDecoder().decode(Message.self, from: data)
                        self.lock.lock()
                        self.lastActivity[sessionId] = Date()
                        let isAuthenticated = self.authenticatedSessions.contains(sessionId)
                        self.lock.unlock()

                        // Gate: only authResponse is allowed before authentication completes
                        if !isAuthenticated {
                            if message.type == .authResponse {
                                self.handleAuthResponse(message, session: session)
                            } else {
                                print("[websocket] Dropping message type=\(message.type.rawValue) from unauthenticated session \(sessionId)")
                            }
                            return
                        }
                        
                        if message.type == .fileChunk || message.type == .fileChunkAck || message.type == .fileTransferComplete || message.type == .fileTransferInit {
                             self.handleMessage(message, session: session)
                        } else {
                            DispatchQueue.main.async { self.handleMessage(message, session: session) }
                        }
                    } catch {
                        print("[websocket] JSON decode failed: \(error)")
                    }
                }
            },
            binary: { [weak self] session, _ in
                self?.lock.lock()
                self?.lastActivity[ObjectIdentifier(session)] = Date()
                self?.lock.unlock()
            },
            connected: { [weak self] session in
                guard let self = self else { return }
                self.lock.lock()
                let sessionId = ObjectIdentifier(session)
                self.lastActivity[sessionId] = Date()
                self.activeSessions.append(session)
                let sessionCount = self.activeSessions.count
                self.lock.unlock()
                print("[websocket] Session \(sessionId) connected, sending auth challenge.")
                
                if self.primarySessionID == nil {
                    self.primarySessionID = sessionId
                }
                
                if sessionCount == 1 {
                    MacRemoteManager.shared.startVolumeMonitoring()
                    self.startPing()
                }

                // Send HMAC challenge for LAN authentication
                self.sendAuthChallenge(to: session)
            },
            disconnected: { [weak self] session in
                guard let self = self else { return }
                let sessionId = ObjectIdentifier(session)
                self.lock.lock()
                self.activeSessions.removeAll(where: { $0 === session })
                let sessionCount = self.activeSessions.count
                let wasPrimary = (sessionId == self.primarySessionID)
                if wasPrimary { self.primarySessionID = nil }
                self.authenticatedSessions.remove(sessionId)
                self.pendingChallenges.removeValue(forKey: sessionId)
                self.lock.unlock()
                
                if sessionCount == 0 {
                    MacRemoteManager.shared.stopVolumeMonitoring()
                    self.stopPing()
                }
                
                if wasPrimary {
                    DispatchQueue.main.async {
                        AppState.shared.disconnectDevice()
                        ADBConnector.disconnectADB()
                        AppState.shared.adbConnected = false
                        self.requestRestart(
                            reason: "Primary session disconnected",
                            delay: 0.35,
                            port: self.localPort ?? Defaults.serverPort
                        )
                    }
                }
            }
        )
    }

    // MARK: - AirBridge Relay Integration

    /// Handles a text message received from the AirBridge relay (Android → Relay → Mac).
    /// Decrypts and routes it through the same pipeline as local WebSocket messages.
    func handleRelayedMessage(_ text: String) {
        let decryptedText: String
        if let key = self.symmetricKey {
            if let dec = decryptMessage(text, using: key), !dec.isEmpty {
                decryptedText = dec
            } else {
                print("[transport] RX via RELAY dropped: decrypt failed or empty payload (len=\(text.count))")
                return
            }
        } else {
            // In normal operation this should not happen; relay payloads are expected encrypted.
            print("[transport] RX via RELAY: no symmetric key on Mac, attempting plaintext parse")
            decryptedText = text
        }

        guard let data = decryptedText.data(using: .utf8) else {
            print("[transport] RX via RELAY dropped: UTF-8 conversion failed")
            return
        }

        do {
            let message = try JSONDecoder().decode(Message.self, from: data)

            // File transfer messages are handled on background queue (like local messages)
            if message.type == .fileChunk || message.type == .fileChunkAck ||
               message.type == .fileTransferComplete || message.type == .fileTransferInit {
                self.handleRelayedMessageInternal(message)
            } else {
                DispatchQueue.main.async {
                    self.handleRelayedMessageInternal(message)
                }
            }
        } catch {
            print("[airbridge] Failed to decode relayed message: \(error)")
        }
    }

    /// Handles a binary message received from the AirBridge relay.
    func handleRelayedBinaryMessage(_ data: Data) {
        // Binary relay data — currently unused in the AirSync protocol
        // (file transfers use base64 JSON), but ready for future E2EE binary payloads
        print("[airbridge] Received binary relay data (\(data.count) bytes)")
    }

    /// Internal router for relayed messages.
    /// Uses an existing local session when available, otherwise handles messages directly.
    private func handleRelayedMessageInternal(_ message: Message) {
        // For the device handshake, we handle it entirely within the relay path
        if message.type == .device {
            if let dict = message.data.value as? [String: Any],
               let name = dict["name"] as? String,
               let ip = dict["ipAddress"] as? String,
               let port = dict["port"] as? Int {

                let version = dict["version"] as? String ?? "2.0.0"
                let adbPorts = dict["adbPorts"] as? [String] ?? []

                DispatchQueue.main.async {
                    AppState.shared.device = Device(
                        name: name,
                        ipAddress: ip,
                        port: port,
                        version: version,
                        adbPorts: adbPorts
                    )
                }

                if let base64 = dict["wallpaper"] as? String {
                    DispatchQueue.main.async {
                        AppState.shared.currentDeviceWallpaperBase64 = base64
                    }
                }

                sendMacInfoViaRelay()
            }
            return
        }

        // For all other messages, delegate to handleMessage only if a primary local session exists
        lock.lock()
        let pId = primarySessionID
        var session = pId != nil ? activeSessions.first(where: { ObjectIdentifier($0) == pId }) : nil
        var sessionCount = activeSessions.count
        if let s = session {
            let sid = ObjectIdentifier(s)
            let lastSeen = lastActivity[sid] ?? .distantPast
            let stale = Date().timeIntervalSince(lastSeen) > activityTimeout
            if stale {
                // Immediate stale eviction: avoids routing relay traffic to a dead local socket.
                activeSessions.removeAll(where: { ObjectIdentifier($0) == sid })
                lastActivity.removeValue(forKey: sid)
                if primarySessionID == sid {
                    primarySessionID = nil
                }
                session = nil
                sessionCount = activeSessions.count
                print("[transport] Primary LAN session stale during relay RX; switched to relay-only routing")
            }
        }
        lock.unlock()

        if sessionCount == 0 {
            MacRemoteManager.shared.stopVolumeMonitoring()
            stopPing()
        }

        if let session = session {
            print("[transport] RX via RELAY routed to primary LAN session type=\(message.type.rawValue)")
            handleMessage(message, session: session)
        } else {
            // No local session — dispatch directly to AppState for non-session-critical messages
            print("[transport] RX via RELAY handled in relay-only mode type=\(message.type.rawValue)")
            handleRelayedMessageWithoutSession(message)
        }
    }

    /// Handles relay messages when no local WebSocket session exists.
    /// This covers the cases where the Mac is connected ONLY via the relay.
    private func handleRelayedMessageWithoutSession(_ message: Message) {
        handleRelayOnlyMessage(message)
    }

    /// Sends macInfo response back through the relay instead of the local session.
    private func sendMacInfoViaRelay() {
        let macName = AppState.shared.myDevice?.name ?? (Host.current().localizedName ?? "My Mac")
        let isPlusSubscription = AppState.shared.isPlus
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.0"

        let messageDict: [String: Any] = [
            "type": "macInfo",
            "data": [
                "name": macName,
                "isPlus": isPlusSubscription,
                "version": appVersion
            ]
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: messageDict),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            if let key = symmetricKey, let encrypted = encryptMessage(jsonString, using: key) {
                AirBridgeClient.shared.sendText(encrypted)
            } else {
                AirBridgeClient.shared.sendText(jsonString)
            }
        }
    }

    // MARK: - Crypto Helpers
    
    func loadOrGenerateSymmetricKey() {
        let keychainKey = "encryptionKey"

        // 1. Try loading from Keychain first
        if let keyData = KeychainStorage.data(for: keychainKey) {
            symmetricKey = SymmetricKey(data: keyData)
            return
        }

        // 2. Migrate from UserDefaults if present (one-time migration)
        let defaults = UserDefaults.standard
        if let savedKey = defaults.string(forKey: keychainKey),
           let keyData = Data(base64Encoded: savedKey) {
            KeychainStorage.setData(keyData, for: keychainKey)
            defaults.removeObject(forKey: keychainKey)
            symmetricKey = SymmetricKey(data: keyData)
            print("[crypto] Migrated encryption key from UserDefaults to Keychain")
            return
        }

        // 3. Generate a new key and store in Keychain
        let base64Key = generateSymmetricKey()
        if let keyData = Data(base64Encoded: base64Key) {
            KeychainStorage.setData(keyData, for: keychainKey)
            symmetricKey = SymmetricKey(data: keyData)
        }
    }

    func resetSymmetricKey() {
        KeychainStorage.delete(key: "encryptionKey")
        resetReplayGuard()
        loadOrGenerateSymmetricKey()
    }

    func getSymmetricKeyBase64() -> String? {
        guard let key = symmetricKey else { return nil }
        return key.withUnsafeBytes { Data($0).base64EncodedString() }
    }

    func setEncryptionKey(base64Key: String) {
        if let data = Data(base64Encoded: base64Key) {
            symmetricKey = SymmetricKey(data: data)
        }
    }

    // MARK: - LAN Authentication (HMAC Challenge-Response)

    /// Generates a random 32-byte nonce and sends it as an authChallenge to the connecting session.
    func sendAuthChallenge(to session: WebSocketSession) {
        var nonceBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, nonceBytes.count, &nonceBytes)
        let nonceData = Data(nonceBytes)
        let nonceHex = nonceData.map { String(format: "%02x", $0) }.joined()

        let sessionId = ObjectIdentifier(session)
        lock.lock()
        pendingChallenges[sessionId] = nonceData
        lock.unlock()

        let challengeJson = """
        {"type":"authChallenge","data":{"nonce":"\(nonceHex)"}}
        """

        if let key = symmetricKey, let encrypted = encryptMessage(challengeJson, using: key) {
            session.writeText(encrypted)
        } else {
            session.writeText(challengeJson)
        }
        print("[auth] Sent challenge to session \(sessionId)")

        // Auto-close session after 10 seconds if not authenticated
        DispatchQueue.global().asyncAfter(deadline: .now() + 10.0) { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            let stillPending = self.pendingChallenges[sessionId] != nil
            let notAuthenticated = !self.authenticatedSessions.contains(sessionId)
            self.lock.unlock()
            if stillPending && notAuthenticated {
                print("[auth] Session \(sessionId) failed to authenticate in time, closing.")
                session.writeBinary([UInt8]()) // triggers disconnect
            }
        }
    }

    /// Verifies the authResponse HMAC from the client using constant-time comparison.
    func handleAuthResponse(_ message: Message, session: WebSocketSession) {
        let sessionId = ObjectIdentifier(session)

        guard let dict = message.data.value as? [String: Any],
              let hmacHex = dict["hmac"] as? String else {
            print("[auth] Invalid authResponse from \(sessionId)")
            sendAuthResult(to: session, success: false, reason: "Invalid response format")
            return
        }

        lock.lock()
        guard let nonceData = pendingChallenges.removeValue(forKey: sessionId) else {
            lock.unlock()
            print("[auth] No pending challenge for \(sessionId)")
            sendAuthResult(to: session, success: false, reason: "No pending challenge")
            return
        }
        lock.unlock()

        guard let key = symmetricKey else {
            print("[auth] No symmetric key available for verification")
            sendAuthResult(to: session, success: false, reason: "Server configuration error")
            return
        }

        // Compute expected HMAC-SHA256(symmetricKey, nonce)
        let hmacKey = SymmetricKey(data: key.withUnsafeBytes { Data($0) })
        let expectedHMAC = HMAC<SHA256>.authenticationCode(for: nonceData, using: hmacKey)
        let expectedHex = Data(expectedHMAC).map { String(format: "%02x", $0) }.joined()

        // Constant-time comparison
        let receivedBytes = Array(hmacHex.utf8)
        let expectedBytes = Array(expectedHex.utf8)
        let lengthMatch = receivedBytes.count == expectedBytes.count
        var diff: UInt8 = 0
        let count = min(receivedBytes.count, expectedBytes.count)
        for i in 0..<count {
            diff |= receivedBytes[i] ^ expectedBytes[i]
        }
        let isValid = lengthMatch && diff == 0

        if isValid {
            lock.lock()
            authenticatedSessions.insert(sessionId)
            lock.unlock()
            print("[auth] Session \(sessionId) authenticated successfully")
            sendAuthResult(to: session, success: true, reason: nil)
        } else {
            print("[auth] HMAC verification failed for session \(sessionId)")
            sendAuthResult(to: session, success: false, reason: "Authentication failed")
            // Close the connection after a brief delay
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                session.writeBinary([UInt8]())
            }
        }
    }

    /// Sends the authResult message back to the client.
    private func sendAuthResult(to session: WebSocketSession, success: Bool, reason: String?) {
        let resultDict: [String: Any] = [
            "type": "authResult",
            "data": [
                "success": success,
                "reason": reason ?? ""
            ]
        ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: resultDict),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            if let key = symmetricKey, let encrypted = encryptMessage(jsonString, using: key) {
                session.writeText(encrypted)
            } else {
                session.writeText(jsonString)
            }
        }
    }
    
    func wakeUpLastConnectedDevice() {
        QuickConnectManager.shared.wakeUpLastConnectedDevice()
    }
}
