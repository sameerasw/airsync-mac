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
    internal var outgoingAcks: [String: Set<Int>] = [:]

    internal let maxChunkRetries = 3
    internal let ackWaitMs: UInt16 = 2000

    internal var lastKnownAdapters: [(name: String, address: String)] = []
    internal var lastLoggedSelectedAdapter: (name: String, address: String)? = nil

    // Emits immediate events when the primary LAN WebSocket session starts or ends.
    // Used by AppState/UI to update LAN vs relay indicators without polling.
    internal let lanSessionEvents = PassthroughSubject<Bool, Never>() // true = started, false = ended
    internal var lastPublishedLanState: Bool?

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
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
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
                    try server.start(in_port_t(port))
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
                                try server.start(in_port_t(port))
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

    func requestRestart(reason: String, delay: TimeInterval = 0.35, port: UInt16? = nil) {
        lock.lock()
        let restartPort = port ?? localPort ?? Defaults.serverPort
        lock.unlock()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            print("[websocket] Restart requested: \(reason)")
            self.stop()
            self.start(port: restartPort)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func stop() {
        lock.lock()
        stopAllServers()
        activeSessions.removeAll()
        primarySessionID = nil
        stopPing()
        lock.unlock()
        publishLanTransportState(isActive: false, reason: "server_stop")
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

    /// Publishes LAN transport state changes in one place to keep UI and routing hints consistent.
    internal func publishLanTransportState(isActive: Bool, reason: String) {
        lock.lock()
        let previous = lastPublishedLanState
        if previous == isActive {
            lock.unlock()
            return
        }
        lastPublishedLanState = isActive
        lock.unlock()

        print("[transport_sync] direction=mac_local lan_state_old=\(previous.map(String.init) ?? "nil") lan_state_new=\(isActive) reason=\(reason)")
        DispatchQueue.main.async {
            self.lanSessionEvents.send(isActive)
            AppState.shared.updatePeerTransportHint(isActive ? "wifi" : "relay")
        }
        sendPeerTransportStatus(isActive ? "wifi" : "relay")
    }

    /// Configures WebSocket routes and event callbacks.
    /// Handles message decryption before passing payload to the message router.
    private func setupWebSocket(for server: HttpServer) {
        server["/socket"] = websocket(
            text: { [weak self] session, text in
                guard let self = self else { return }
                let decryptedText: String
                if let key = self.symmetricKey {
                    decryptedText = decryptMessage(text, using: key) ?? ""
                } else {
                    decryptedText = text
                }

                if decryptedText.contains("\"type\":\"pong\"") {
                    self.lock.lock()
                    self.lastActivity[ObjectIdentifier(session)] = Date()
                    self.lock.unlock()
                    return
                }

                if let data = decryptedText.data(using: .utf8) {
                    do {
                        let message = try JSONDecoder().decode(Message.self, from: data)
                        self.lock.lock()
                        self.lastActivity[ObjectIdentifier(session)] = Date()
                        self.lock.unlock()
                        
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
                let becamePrimary: Bool
                self.lock.unlock()
                print("[websocket] Session \(sessionId) connected.")
                
                if self.primarySessionID == nil {
                    self.primarySessionID = sessionId
                    becamePrimary = true
                } else {
                    becamePrimary = false
                }
                
                if sessionCount == 1 {
                    MacRemoteManager.shared.startVolumeMonitoring()
                    self.startPing()
                }

                 if becamePrimary {
                     self.publishLanTransportState(isActive: true, reason: "connected_primary_session")
                 }
            },
            disconnected: { [weak self] session in
                guard let self = self else { return }
                self.lock.lock()
                self.activeSessions.removeAll(where: { $0 === session })
                let sessionCount = self.activeSessions.count
                let wasPrimary = (ObjectIdentifier(session) == self.primarySessionID)
                if wasPrimary { self.primarySessionID = nil }
                self.lock.unlock()
                
                if sessionCount == 0 {
                    MacRemoteManager.shared.stopVolumeMonitoring()
                    self.stopPing()
                }
                
                if wasPrimary {
                    self.publishLanTransportState(isActive: false, reason: "disconnected_primary_session")
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
                // Fallback: If decryption fails, check if it's valid plaintext JSON.
                // This handles cases where keys are out of sync or the client sends plaintext via the secure relay tunnel.
                if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
                     print("[transport] RX via RELAY: Decryption failed, attempting plaintext fallback.")
                     decryptedText = text
                } else {
                     print("[transport] RX via RELAY dropped: decrypt failed or empty payload (len=\(text.count))")
                     return
                }
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

        // Accept keepalive packets that omit "data" (e.g. {"type":"pong"}).
        if let jsonObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let type = jsonObj["type"] as? String {
            if type == MessageType.pong.rawValue {
                AirBridgeClient.shared.processPong()
                return
            }
            if type == MessageType.ping.rawValue {
                let pongPayload = #"{"type":"pong"}"#
                if let key = symmetricKey, let encrypted = encryptMessage(pongPayload, using: key) {
                    AirBridgeClient.shared.sendText(encrypted)
                } else {
                    AirBridgeClient.shared.sendText(pongPayload)
                }
                return
            }
        }

        do {
            let message = try JSONDecoder().decode(Message.self, from: data)

            // Handle Pong for AirBridge keepalive
            if message.type == .pong {
                AirBridgeClient.shared.processPong()
                return
            }

            DispatchQueue.main.async {
                self.handleRelayedMessageInternal(message)
            }
        } catch {
            print("[airbridge] Failed to decode relayed message: \(error)")
        }
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
        var evictedPrimaryAsStale = false
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
                    evictedPrimaryAsStale = true
                }
                session = nil
                sessionCount = activeSessions.count
                print("[transport] Primary LAN session stale during relay RX; switched to relay-only routing")
            }
        }
        lock.unlock()

        if evictedPrimaryAsStale {
            publishLanTransportState(isActive: false, reason: "stale_primary_evicted_during_relay_rx")
        }

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

        // Enhanced device info matching standard LAN handshake
        let modelId = DeviceTypeUtil.modelIdentifier()
        let categoryTypeRaw = DeviceTypeUtil.deviceTypeDescription()
        let exactDeviceNameRaw = DeviceTypeUtil.deviceFullDescription()
        let categoryType = categoryTypeRaw.isEmpty ? "Mac" : categoryTypeRaw
        let exactDeviceName = exactDeviceNameRaw.isEmpty ? categoryType : exactDeviceNameRaw
        let savedAppPackages = Array(AppState.shared.androidApps.keys)

        let messageDict: [String: Any] = [
            "type": "macInfo",
            "data": [
                "name": macName,
                "isPlus": isPlusSubscription,
                "isPlusSubscription": isPlusSubscription, // Essential for Android check
                "version": appVersion,
                "model": modelId,
                "type": categoryType,
                "categoryType": categoryType,
                "exactDeviceName": exactDeviceName,
                "savedAppPackages": savedAppPackages
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

    /// Sends a wake signal through the relay so Android can attempt a LAN reconnect.
    func sendWakeViaRelay() {
        // Include current LAN endpoint hints so Android can reconnect without requiring a manual pair.
        // getLocalIPAddress(adapterName:nil) returns a comma-separated list in auto-mode.
        let adapter = AppState.shared.selectedNetworkAdapterName
        let ipList = getLocalIPAddress(adapterName: adapter) ?? getLocalIPAddress(adapterName: nil) ?? ""
        let port = Int(localPort ?? Defaults.serverPort)

        let messageDict: [String: Any] = [
            "type": "macWake",
            "data": [
                "ips": ipList,
                "port": port,
                "adapter": adapter as Any
            ]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: messageDict),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            print("[airbridge] Failed to encode macWake message")
            return
        }

        print("[transport_sync] direction=mac->android type=macWake ips=\(ipList) port=\(port) adapter=\(adapter ?? "auto")")

        if let key = symmetricKey, let encrypted = encryptMessage(jsonString, using: key) {
            AirBridgeClient.shared.sendText(encrypted)
        } else {
            AirBridgeClient.shared.sendText(jsonString)
        }
    }

    // MARK: - Crypto Helpers
    
    func loadOrGenerateSymmetricKey() {
        let defaults = UserDefaults.standard
        if let savedKey = defaults.string(forKey: "encryptionKey"),
           let keyData = Data(base64Encoded: savedKey) {
            symmetricKey = SymmetricKey(data: keyData)
        } else {
            let base64Key = generateSymmetricKey()
            defaults.set(base64Key, forKey: "encryptionKey")
            if let keyData = Data(base64Encoded: base64Key) {
                symmetricKey = SymmetricKey(data: keyData)
            }
        }
    }

    func resetSymmetricKey() {
        UserDefaults.standard.removeObject(forKey: "encryptionKey")
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

    func wakeUpLastConnectedDevice() {
        QuickConnectManager.shared.wakeUpLastConnectedDevice()
    }
}
