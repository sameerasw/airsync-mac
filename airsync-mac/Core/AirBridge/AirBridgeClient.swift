//
//  AirBridgeClient.swift
//  airsync-mac
//
//  Created by tornado-bunk and an AI Assistant.
//  WebSocket client that connects to a self-hosted AirBridge relay server.
//  When a direct LAN connection is unavailable, messages are tunneled through
//  the relay to reach the Android device.
//

import Foundation
import Combine
import CryptoKit

class AirBridgeClient: ObservableObject {
    static let shared = AirBridgeClient()

    // MARK: - Published State

    @Published var connectionState: AirBridgeConnectionState = .disconnected
    @Published var isPeerConnected: Bool = false

    // Ping mechanism
    private var pingTimer: Timer?
    private var lastPongReceived: Date = .distantPast
    private let pingInterval: TimeInterval = 8.0
    private let peerTimeout: TimeInterval = 20.0

    // MARK: - Configuration
    //
    // The secret is cached in memory after the first Keychain read so that
    // subsequent accesses never hit the Keychain again.

    private static let keychainKeySecret = "airBridgeSecret"

    // In-memory cache for the secret
    private var _cachedSecret: String?
    private var _secretLoaded = false

    /// Loads the secret from Keychain once
    private func loadSecretIfNeeded() {
        guard !_secretLoaded else { return }
        _secretLoaded = true

        // Current key
        if let s = KeychainStorage.string(for: Self.keychainKeySecret) {
            _cachedSecret = s
        }
    }

    var relayServerURL: String {
        get { UserDefaults.standard.string(forKey: "airBridgeRelayURL") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "airBridgeRelayURL") }
    }

    var pairingId: String {
        get { UserDefaults.standard.string(forKey: "airBridgePairingId") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "airBridgePairingId") }
    }

    var secret: String {
        get { loadSecretIfNeeded(); return _cachedSecret ?? "" }
        set { _cachedSecret = newValue; _secretLoaded = true; KeychainStorage.set(newValue, for: Self.keychainKeySecret) }
    }

    /// Batch-update all three credentials.  Only the secret write touches Keychain
    func saveAllCredentials(url: String, pairingId: String, secret: String) {
        UserDefaults.standard.set(url, forKey: "airBridgeRelayURL")
        UserDefaults.standard.set(pairingId, forKey: "airBridgePairingId")
        _cachedSecret = secret
        _secretLoaded = true
        KeychainStorage.set(secret, for: Self.keychainKeySecret)
    }

    /// Ensures pairing credentials exist, generating them if empty.
    /// Call this only when AirBridge is actually being enabled/configured.
    func ensureCredentialsExist() {
        if pairingId.isEmpty {
            pairingId = Self.generateShortId()
        }
        if secret.isEmpty {
            let newSecret = Self.generateRandomSecret()
            _cachedSecret = newSecret
            _secretLoaded = true
            KeychainStorage.set(newSecret, for: Self.keychainKeySecret)
        }
    }

    // MARK: - Private State

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var reconnectAttempt: Int = 0
    private var maxReconnectDelay: TimeInterval = 30.0
    private var isManuallyDisconnected = false
    private var receiveLoopActive = false
    private let queue = DispatchQueue(label: "com.airsync.airbridge", qos: .userInitiated)

    private init() {}

    // MARK: - Public Interface

    /// Connects to the relay server. Does nothing if already connected or URL is empty.
    func connect() {
        queue.async { [weak self] in
            self?.connectInternal()
        }
    }

    /// Gracefully disconnects from the relay server. Disables auto-reconnect.
    func disconnect() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.isManuallyDisconnected = true
            self.tearDown(reason: "Manual disconnect")
            DispatchQueue.main.async {
                self.connectionState = .disconnected
            }
        }
    }

    /// Sends an already-encrypted text message to the relay for forwarding to Android.
    func sendText(_ text: String) {
        guard let task = webSocketTask else { return }
        task.send(.string(text)) { error in
            if let error = error {
                print("[airbridge] Send text error: \(error.localizedDescription)")
            }
        }
    }

    /// Sends raw binary data to the relay for forwarding to Android.
    func sendData(_ data: Data) {
        guard let task = webSocketTask else { return }
        task.send(.data(data)) { error in
            if let error = error {
                print("[airbridge] Send data error: \(error.localizedDescription)")
            }
        }
    }

    /// Tests connectivity to a relay server without affecting the live connection.
    ///
    /// Opens an isolated WebSocket, sends a registration frame, and considers success
    /// if both the WebSocket handshake and the send complete without error. The server
    /// does **not** reply to a registration when the peer is not yet connected, so we
    /// cannot wait for a response — a successful send is sufficient proof that the
    /// relay is reachable and accepting connections.
    ///
    /// - Parameters:
    ///   - url:       Raw relay URL (will be normalised, same as `relayServerURL`).
    ///   - pairingId: Pairing ID to register with.
    ///   - secret:    Plain-text secret (will be SHA-256 hashed before sending).
    ///   - timeout:   Maximum seconds to wait (default 8 s).
    ///   - completion: Called on the **main thread** with `.success(())` or `.failure(error)`.
    func testConnectivity(
        url: String,
        pairingId: String,
        secret: String,
        timeout: TimeInterval = 8,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let normalized = normalizeRelayURL(url)
        guard let wsURL = URL(string: normalized) else {
            DispatchQueue.main.async {
                completion(.failure(ConnectivityError.invalidURL(normalized)))
            }
            return
        }

        // SHA-256 hash the secret
        let secretHash: String = {
            let data = Data(secret.utf8)
            let hash = SHA256.hash(data: data)
            return hash.compactMap { String(format: "%02x", $0) }.joined()
        }()

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        let session = URLSession(configuration: config)
        let task = session.webSocketTask(with: wsURL)
        task.resume()

        // Timer to enforce the overall timeout
        var settled = false
        let lock = NSLock()

        func settle(_ result: Result<Void, Error>) {
            lock.lock()
            let alreadyDone = settled
            settled = true
            lock.unlock()
            guard !alreadyDone else { return }
            task.cancel(with: .normalClosure, reason: nil)
            session.invalidateAndCancel()
            DispatchQueue.main.async { completion(result) }
        }

        // Schedule timeout
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            settle(.failure(ConnectivityError.timeout))
        }

        // Build registration frame
        let regMessage = AirBridgeRegisterMessage(
            action: .register,
            role: "mac",
            pairingId: pairingId,
            secret: secretHash,
            localIp: "0.0.0.0",
            port: 0
        )

        guard let regData = try? JSONEncoder().encode(regMessage),
              let regJSON = String(data: regData, encoding: .utf8) else {
            settle(.failure(ConnectivityError.encodingFailed))
            return
        }

        // Send registration — the server silently accepts registrations without replying until a peer connects, so a successful send = server is alive.
        task.send(.string(regJSON)) { sendError in
            if let sendError = sendError {
                settle(.failure(sendError))
            } else {
                settle(.success(()))
            }
        }
    }

    // MARK: - Connectivity Error Types

    enum ConnectivityError: LocalizedError {
        case invalidURL(String)
        case timeout
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .invalidURL(let url): return "Invalid relay URL: \(url)"
            case .timeout:             return "Connection timed out. Check the server URL and your network."
            case .encodingFailed:      return "Failed to encode registration message."
            }
        }
    }

    /// Regenerates pairing credentials together so an ID and secret always stay in sync.
    /// PairingId goes to UserDefaults, secret to Keychain.
    func regeneratePairingCredentials() {
        pairingId = Self.generateShortId()
        let newSecret = Self.generateRandomSecret()
        _cachedSecret = newSecret
        _secretLoaded = true
        KeychainStorage.set(newSecret, for: Self.keychainKeySecret)
    }

    /// Returns a `airbridge://` URI containing all pairing config, suitable for QR encoding.
    func generateQRCodeData() -> String {
        let urlEncoded = relayServerURL.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? relayServerURL
        return "airbridge://\(urlEncoded)/\(pairingId)/\(secret)"
    }

    // MARK: - Connection Logic

    private func connectInternal() {
        guard !relayServerURL.isEmpty else {
            print("[airbridge] Relay URL is empty, skipping connection")
            DispatchQueue.main.async { self.connectionState = .disconnected }
            return
        }

        // Ensure credentials exist before connecting
        ensureCredentialsExist()

        // Normalize URL: ensure it ends with /ws and has wss:// or ws:// prefix
        let normalizedURL = normalizeRelayURL(relayServerURL)

        guard let url = URL(string: normalizedURL) else {
            print("[airbridge] Invalid relay URL: \(normalizedURL)")
            DispatchQueue.main.async { self.connectionState = .failed(error: "Invalid URL") }
            return
        }

        isManuallyDisconnected = false
        DispatchQueue.main.async { self.connectionState = .connecting }

        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 30

        urlSession = URLSession(configuration: config)
        webSocketTask = urlSession?.webSocketTask(with: url)
        webSocketTask?.resume()

        // Start receiving messages
        receiveLoopActive = true
        startReceiving()

        // Send registration
        sendRegistration()
    }

    /// Derives a SHA-256 hash of the raw secret so the plaintext never leaves the device.
    /// The relay server only ever sees (and stores) this hash.
    private func hashedSecret() -> String {
        let data = Data(secret.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func sendRegistration() {
        DispatchQueue.main.async { self.connectionState = .registering }

        let localIP = WebSocketServer.shared.getLocalIPAddress(
            adapterName: AppState.shared.selectedNetworkAdapterName
        ) ?? "unknown"
        let port = Int(WebSocketServer.shared.localPort ?? Defaults.serverPort)

        let regMessage = AirBridgeRegisterMessage(
            action: .register,
            role: "mac",
            pairingId: pairingId,
            secret: hashedSecret(),
            localIp: localIP,
            port: port
        )

        do {
            let data = try JSONEncoder().encode(regMessage)
            if let jsonString = String(data: data, encoding: .utf8) {
                webSocketTask?.send(.string(jsonString)) { [weak self] error in
                    if let error = error {
                        print("[airbridge] Registration send failed: \(error.localizedDescription)")
                        self?.scheduleReconnect()
                    } else {
                        print("[airbridge] Registration sent for pairingId: \(self?.pairingId ?? "?")")
                        DispatchQueue.main.async {
                            self?.connectionState = .waitingForPeer
                        }
                        self?.reconnectAttempt = 0
                    }
                }
            }
        } catch {
            print("[airbridge] Failed to encode registration: \(error)")
        }
    }

    // MARK: - Receive Loop

    private func startReceiving() {
        guard receiveLoopActive, let task = webSocketTask else { return }

        task.receive { [weak self] result in
            guard let self = self, self.receiveLoopActive else { return }

            switch result {
            case .success(let message):
                self.handleMessage(message)
                // Continue receiving
                self.startReceiving()

            case .failure(let error):
                print("[airbridge] Receive error: \(error.localizedDescription)")
                self.receiveLoopActive = false
                self.scheduleReconnect()
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            handleTextMessage(text)
        case .data(let data):
            handleBinaryMessage(data)
        @unknown default:
            print("[airbridge] Unknown message type received")
        }
    }

    private func handleTextMessage(_ text: String) {
        // First, try to parse as an AirBridge control message
        if let data = text.data(using: .utf8),
           let baseMsg = try? JSONDecoder().decode(AirBridgeBaseMessage.self, from: data) {

            switch baseMsg.action {
            case .relayStarted:
                print("[airbridge] Relay tunnel established!")
                DispatchQueue.main.async {
                    self.connectionState = .relayActive
                    self.startPingLoop()
                }
                return

            case .macInfo:
                // Server echoing our own info, ignore
                return

            case .error:
                if let errorMsg = try? JSONDecoder().decode(AirBridgeErrorMessage.self, from: data) {
                    print("[airbridge] Server error: \(errorMsg.message)")
                    DispatchQueue.main.async {
                        self.connectionState = .failed(error: errorMsg.message)
                    }
                }
                return

            default:
                break
            }
        }

        // If it's not a control message, it's a relayed message from Android.
        // Forward it to the local WebSocket handler as if it came from a LAN client.
        print("[airbridge] Relaying text message from Android (\(text.count) chars)")
        WebSocketServer.shared.handleRelayedMessage(text)
    }

    private func handleBinaryMessage(_ data: Data) {
        // Binary data from the relay is currently unused in the AirSync protocol
        print("[airbridge] Received binary message from Android (\(data.count) bytes) - Ignored")
    }

    private func startPingLoop() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.pingTimer?.invalidate()
            self.lastPongReceived = Date() // Assume alive on start
            
            self.pingTimer = Timer.scheduledTimer(withTimeInterval: self.pingInterval, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                
                // 1. Check for timeout
                let timeSinceLastPong = Date().timeIntervalSince(self.lastPongReceived)
                if self.isPeerConnected && timeSinceLastPong > self.peerTimeout {
                    print("[airbridge] Peer ping timeout (\(Int(timeSinceLastPong))s > \(Int(self.peerTimeout))s). Marking disconnected.")
                    self.isPeerConnected = false
                }
                
                // 2. Send Ping
                let pingJson = "{\"type\":\"ping\"}"
                self.sendText(pingJson)
            }
        }
    }
    
    func processPong() {
        DispatchQueue.main.async {
            if !self.isPeerConnected {
                print("[airbridge] Peer connected via relay (pong received).")
            }
            self.lastPongReceived = Date()
            self.isPeerConnected = true
        }
    }

    // MARK: - Reconnect

    private func scheduleReconnect() {
        guard !isManuallyDisconnected else { return }

        tearDown(reason: "Preparing reconnect")

        let delay = min(pow(2.0, Double(reconnectAttempt)), maxReconnectDelay)
        reconnectAttempt += 1

        print("[airbridge] Reconnecting in \(delay)s (attempt \(reconnectAttempt))")
        DispatchQueue.main.async {
            self.connectionState = .connecting
        }

        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, !self.isManuallyDisconnected else { return }
            self.connectInternal()
        }
    }

    private func tearDown(reason: String) {
        receiveLoopActive = false
        webSocketTask?.cancel(with: .goingAway, reason: reason.data(using: .utf8))
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        
        // Clean up ping timer
        DispatchQueue.main.async { [weak self] in
            self?.pingTimer?.invalidate()
            self?.pingTimer = nil
            self?.isPeerConnected = false
        }
        
        print("[airbridge] Torn down: \(reason)")
    }

    // MARK: - Helpers

    private func normalizeRelayURL(_ raw: String) -> String {
        var url = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        let host: String = {
            var h = url
            // Strip scheme if present
            if h.hasPrefix("wss://") { h = String(h.dropFirst(6)) }
            else if h.hasPrefix("ws://") { h = String(h.dropFirst(5)) }
            return h.components(separatedBy: ":").first?.components(separatedBy: "/").first ?? ""
        }()

        let isPrivate = isPrivateHost(host)

        // If user explicitly provided ws://, only allow it for private/localhost hosts.
        // Upgrade to wss:// for public hosts to prevent cleartext transport over the internet.
        if url.hasPrefix("ws://") && !url.hasPrefix("wss://") && !isPrivate {
            print("[airbridge] SECURITY: Upgrading ws:// to wss:// for public host: \(host)")
            url = "wss://" + String(url.dropFirst(5))
        }

        // Add scheme if missing
        if !url.hasPrefix("ws://") && !url.hasPrefix("wss://") {
            if isPrivate {
                url = "ws://\(url)"
            } else {
                url = "wss://\(url)"
            }
        }

        // Add /ws path if missing
        if !url.hasSuffix("/ws") {
            if url.hasSuffix("/") {
                url += "ws"
            } else {
                url += "/ws"
            }
        }

        return url
    }

    /// Returns true if the host is a loopback or RFC 1918 private address.
    private func isPrivateHost(_ host: String) -> Bool {
        if host == "localhost" || host == "127.0.0.1" || host == "::1" { return true }
        if host.hasPrefix("192.168.") || host.hasPrefix("10.") { return true }
        // RFC 1918: only 172.16.0.0 – 172.31.255.255 (NOT all of 172.*)
        if host.hasPrefix("172.") {
            let parts = host.components(separatedBy: ".")
            if parts.count >= 2, let second = Int(parts[1]), (16...31).contains(second) {
                return true
            }
        }
        return false
    }

    /// Generates a 32-char lowercase hex ID (128-bit entropy)
    static func generateShortId() -> String {
        var bytes = [UInt8](repeating: 0, count: 16) // 16 bytes = 128 bits
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Generates a cryptographically strong secret token (192-bit / 48 hex chars)
    /// formatted as 8 groups of 6 chars for readability (e.g. "a3f8b2-c1e9d0-471f8a-2b3c4d-5e6f78-90abcd-ef1234-567890")
    static func generateRandomSecret() -> String {
        var bytes = [UInt8](repeating: 0, count: 24) // 24 bytes = 192 bits
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        // Split into 8 groups of 6 chars for readability
        var groups: [String] = []
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let end = hex.index(idx, offsetBy: 6, limitedBy: hex.endIndex) ?? hex.endIndex
            groups.append(String(hex[idx..<end]))
            idx = end
        }
        return groups.joined(separator: "-")
    }
}
