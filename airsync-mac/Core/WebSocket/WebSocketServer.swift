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
internal import Combine

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

    func stop() {
        lock.lock()
        stopAllServers()
        activeSessions.removeAll()
        primarySessionID = nil
        stopPing()
        lock.unlock()
        DispatchQueue.main.async { AppState.shared.webSocketStatus = .stopped }
        stopNetworkMonitoring()
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
                self.lock.unlock()
                print("[websocket] Session \(sessionId) connected.")
                
                if sessionCount == 1 {
                    MacRemoteManager.shared.startVolumeMonitoring()
                    self.startPing()
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
                    DispatchQueue.main.async {
                        AppState.shared.disconnectDevice()
                        ADBConnector.disconnectADB()
                        AppState.shared.adbConnected = false
                        self.stop()
                        self.start(port: self.localPort ?? Defaults.serverPort)
                    }
                }
            }
        )
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
