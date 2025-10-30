//
//  WebSocketServer.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-07-28.
//

import Foundation
import UniformTypeIdentifiers
#if canImport(MobileCoreServices)
import MobileCoreServices
#endif
import UserNotifications
import Swifter
internal import Combine
import CryptoKit
import AppKit
#if canImport(SwiftUI)
import SwiftUI
#endif

#if canImport(SwiftUI)
struct MirrorFallbackView: View {
    @ObservedObject private var appState = AppState.shared
    var body: some View {
        ZStack {
            if let image = appState.latestMirrorFrame {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .background(Color.black)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Waiting for mirror frames…")
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
        }
        .frame(minWidth: 320, minHeight: 600)
    }
}
#endif

enum WebSocketStatus {
    case stopped
    case starting
    case started(port: UInt16, ip: String?)
    case failed(error: String)
}

class WebSocketServer: ObservableObject {
    static let shared = WebSocketServer()

    private var server = HttpServer()
    private var activeSessions: [WebSocketSession] = []
    @Published var symmetricKey: SymmetricKey?

    @Published var localPort: UInt16?
    @Published var localIPAddress: String?

    @Published var connectedDevice: Device?
    @Published var notifications: [Notification] = []
    @Published var deviceStatus: DeviceStatus?

    private var lastKnownIP: String?
    private var networkMonitorTimer: Timer?
    private let networkCheckInterval: TimeInterval = 10.0 // seconds

    // Incoming file transfers (Android -> Mac) — keep only IO here; state lives in AppState
    private struct IncomingFileIO {
        var tempUrl: URL
        var fileHandle: FileHandle?
    }
    private var incomingFiles: [String: IncomingFileIO] = [:]
    private var incomingFilesChecksum: [String: String] = [:]
    // Outgoing transfer ack tracking
    private var outgoingAcks: [String: Set<Int>] = [:]

    private let maxChunkRetries = 3
    private let ackWaitMs: UInt16 = 2000 // 2s

    private var lastKnownAdapters: [(name: String, address: String)] = []
    // Track last adapter selection we logged to avoid repetitive logs
    private var lastLoggedSelectedAdapter: (name: String, address: String)? = nil

    private var h264Decoder = H264Decoder()

    #if os(macOS)
    private var mirrorWindow: NSWindow?
    #endif

    init() {
        loadOrGenerateSymmetricKey()
        setupWebSocket()
        // Request notification permission so we can show incoming file alerts
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let err = error {
                print("[websocket] Notification auth error: \(err)")
            } else {
                print("[websocket] Notification permission granted: \(granted)")
            }
        }
        h264Decoder.onDecodedFrame = { [weak self] image in
            DispatchQueue.main.async {
                guard let self = self else { return }
                AppState.shared.latestMirrorFrame = image
                if !AppState.shared.isMirrorActive {
                    AppState.shared.isMirrorActive = true
                    #if os(macOS)
                    self.presentMirrorWindowIfNeeded()
                    #endif
                    print("[mirror] First decoded frame -> presenting UI now")
                }
            }
        }
    }

    deinit {
        h264Decoder.onDecodedFrame = nil
    }

    func start(port: UInt16 = Defaults.serverPort) {
        // Prevent concurrent starts
        if case .starting = AppState.shared.webSocketStatus {
            print("[websocket] start() called while status is starting; ignoring")
            return
        }
        if case .started = AppState.shared.webSocketStatus {
            print("[websocket] start() called while status is started; ignoring")
            return
        }

        DispatchQueue.main.async {
            AppState.shared.webSocketStatus = .starting
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            do {
                guard port > 0 && port <= 65_535 else {
                    let msg = "[websocket] Invalid port \(port). Must be in 1...65535."
                    DispatchQueue.main.async {
                        AppState.shared.webSocketStatus = .failed(error: msg)
                    }
                    print(msg)
                    return
                }

                try self.server.start(in_port_t(port), forceIPv4: true, priority: .default)
                let ip = self.getLocalIPAddress(adapterName: AppState.shared.selectedNetworkAdapterName)

                DispatchQueue.main.async {
                    self.localPort = port
                    self.localIPAddress = ip
                    AppState.shared.webSocketStatus = .started(port: port, ip: ip)

                    self.lastKnownIP = ip
                }
                print("[websocket] WebSocket server started at ws://\(ip ?? "unknown"):\(port)/socket)")

                self.startNetworkMonitoring()
            } catch {
                DispatchQueue.main.async {
                    AppState.shared.webSocketStatus = .failed(error: "\(error)")
                }
                print("[websocket] Failed to start WebSocket server: \(error)")
            }
        }
    }





    func stop() {
        server.stop()
        activeSessions.removeAll()
        // Clear any active mirror state when server stops
        DispatchQueue.main.async {
            AppState.shared.isMirrorActive = false
            AppState.shared.latestMirrorFrame = nil
            AppState.shared.isMirroring = false
            AppState.shared.isMirrorRequestPending = false
        }
        DispatchQueue.main.async {
            AppState.shared.webSocketStatus = .stopped
        }
        stopNetworkMonitoring()
    }



    func sendDisconnectRequest() {
        let message = """
    {
        "type": "disconnectRequest",
        "data": {}
    }
    """
        sendToFirstAvailable(message: message)
    }


    private func setupWebSocket() {
        server["/socket"] = websocket(
            text: { [weak self] session, text in
                guard let self = self else { return }

                print("[websocket] [raw] incoming text length=\(text.count)")
                // Step 1: Decrypt the message
                let decryptedText: String
                if let key = self.symmetricKey {
                    decryptedText = decryptMessage(text, using: key) ?? ""
                } else {
                    decryptedText = text
                }
                let usedEncryption = (self.symmetricKey != nil)
                print("[websocket] [decrypt] used=\(usedEncryption) decryptedLen=\(decryptedText.count)")

                let truncated = decryptedText.count > 300
                ? decryptedText.prefix(300) + "..."
                : decryptedText
                print("[websocket] [received] \n\(truncated)")


                // Step 2: Decode JSON and handle
                if let data = decryptedText.data(using: .utf8) {
                    do {
                        // Use JSONSerialization instead of Codable for flexible parsing
                        guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                            print("[websocket] Failed to parse JSON as dictionary")
                            return
                        }
                        
                        // Extract type and data manually
                        guard let typeString = jsonObject["type"] as? String,
                              let messageType = MessageType(rawValue: typeString) else {
                            print("[websocket] Invalid or missing message type")
                            return
                        }
                        
                        let messageData = jsonObject["data"] as? [String: Any] ?? [:]
                        print("[websocket] ✅ Parsed JSON - type: \(typeString), data keys: \(messageData.keys.joined(separator: ", "))")
                        
                        // Create message with raw dictionary data
                        let message = FlexibleMessage(type: messageType, data: messageData)
                        DispatchQueue.main.async {
                                self.handleFlexibleMessage(message)
                        }
                    } catch {
                        let snippet = String(decryptedText.prefix(200))
                        print("[websocket] WebSocket JSON decode failed: \(error) | snippet=\(snippet)")
                    }
                }
            },

            connected: { [weak self] session in
                guard let self = self else { return }
                print("[websocket] Device connected")
                // Enforce single active session to avoid reconnect loops
                if !self.activeSessions.isEmpty {
                    // Keep only the newest session; drop references to older ones
                    self.activeSessions.removeAll()
                }
                self.activeSessions.append(session)
                print("[websocket] Active sessions: \(self.activeSessions.count)")
            },
            disconnected: { [weak self] session in
                guard let self = self else { return }
                print("[websocket] Device disconnected")

                self.activeSessions.removeAll(where: { $0 === session })

                // Only call disconnectDevice if no other sessions remain
                if self.activeSessions.isEmpty {
                    DispatchQueue.main.async {
                        AppState.shared.disconnectDevice()
                    }
                }
                // Also clear mirror state when the last session disconnects
                if self.activeSessions.isEmpty {
                    DispatchQueue.main.async {
                        AppState.shared.isMirrorActive = false
                        AppState.shared.latestMirrorFrame = nil
                    }
                }
                print("[websocket] Active sessions: \(self.activeSessions.count)")
            }
        )
    }


    // MARK: - Local IP handling

    func getLocalIPAddress(adapterName: String?) -> String? {
        let adapters = getAvailableNetworkAdapters()

        if let adapterName = adapterName {
            if let exact = adapters.first(where: { $0.name == adapterName }) {
                // Log only when selection changes
                if lastLoggedSelectedAdapter?.name != exact.name || lastLoggedSelectedAdapter?.address != exact.address {
                    print("[websocket] Selected adapter match: \(exact.name) -> \(exact.address)")
                    lastLoggedSelectedAdapter = (exact.name, exact.address)
                }
                return exact.address
            }
            // [quiet] adapter not found can be noisy; keep for debugging
            // print("[websocket] Adapter \(adapterName) not found, falling back")
        }

        // Auto mode
        if adapterName == nil {
            // Priority 1: Wi-Fi/Ethernet (en0, en1, en2…)
            if let primary = adapters.first(where: { $0.name.hasPrefix("en") }) {
                // Log only when selection changes
                if lastLoggedSelectedAdapter?.name != primary.name || lastLoggedSelectedAdapter?.address != primary.address {
                    print("[websocket] Auto-selected network adapter: \(primary.name) -> \(primary.address)")
                    lastLoggedSelectedAdapter = (primary.name, primary.address)
                }
                return primary.address
            }
            // Priority 2: Standard private ranges (192.168, 10.x, 172.16–31)
            if let privateIP = adapters.first(where: { ipIsPrivatePreferred($0.address) }) {
                if lastLoggedSelectedAdapter?.name != privateIP.name || lastLoggedSelectedAdapter?.address != privateIP.address {
                    print("[websocket] Auto-selected private adapter: \(privateIP.name) -> \(privateIP.address)")
                    lastLoggedSelectedAdapter = (privateIP.name, privateIP.address)
                }
                return privateIP.address
            }
            // Priority 3: Any other adapter
            if let any = adapters.first {
                if lastLoggedSelectedAdapter?.name != any.name || lastLoggedSelectedAdapter?.address != any.address {
                    print("[websocket] Auto-selected fallback adapter: \(any.name) -> \(any.address)")
                    lastLoggedSelectedAdapter = (any.name, any.address)
                }
                return any.address
            }
        }

        return nil
    }

    func getAvailableNetworkAdapters() -> [(name: String, address: String)] {
        var adapters: [(String, String)] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil

        if getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr {
            for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
                let interface = ptr.pointee
                let addrFamily = interface.ifa_addr.pointee.sa_family

                if addrFamily == UInt8(AF_INET),
                   let name = String(validatingUTF8: interface.ifa_name) {
                    var addr = interface.ifa_addr.pointee
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    let result = getnameinfo(&addr,
                                             socklen_t(interface.ifa_addr.pointee.sa_len),
                                             &hostname,
                                             socklen_t(hostname.count),
                                             nil,
                                             socklen_t(0),
                                             NI_NUMERICHOST)
                    if result == 0 {
                        let address = String(cString: hostname)
                        if address != "127.0.0.1" {
                            adapters.append((name, address))
                        }
                    }
                }
            }
            freeifaddrs(ifaddr)
        }

        return adapters
    }

    private func ipIsPrivatePreferred(_ ip: String) -> Bool {
        if ip.hasPrefix("192.168.") { return true }
        if ip.hasPrefix("10.") { return true }
        if ip.hasPrefix("172.") {
            let parts = ip.split(separator: ".")
            if parts.count > 1, let second = Int(parts[1]), (16...31).contains(second) {
                return true
            }
        }
        return false
    }



    // MARK: - Message Handling

    func handleMessage(_ message: Message) {
        switch message.type {
        case .device:
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
                        version: version
                    )
                }

                if let base64 = dict["wallpaper"] as? String, !base64.isEmpty {
                    print("[websocket] 📱 Received wallpaper in device info (\(base64.count) chars)")
                    DispatchQueue.global(qos: .utility).async {
                        DispatchQueue.main.async {
                            AppState.shared.currentDeviceWallpaperBase64 = base64
                        }
                    }
                }

                if (!AppState.shared.adbConnected && AppState.shared.adbEnabled && AppState.shared.isPlus) {
                    ADBConnector.connectToADB(ip: ip)
                }

                // mark first-time pairing
                if UserDefaults.standard.hasPairedDeviceOnce == false {
                    UserDefaults.standard.hasPairedDeviceOnce = true
                }
                
                // Send Mac info response to Android
                sendMacInfoResponse()
                
                // Android now proactively syncs data on connection
                // Only request data if not received within 3 seconds (fallback)
                print("[websocket] 📊 Waiting for Android to proactively sync data...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    // Only request if we haven't received data yet
                    if LiveNotificationManager.shared.callLogs.isEmpty {
                        print("[websocket] 📊 Requesting call logs (fallback)")
                        self.requestCallLogs()
                    }
                    if LiveNotificationManager.shared.smsThreads.isEmpty {
                        print("[websocket] 📊 Requesting SMS threads (fallback)")
                        self.requestSmsThreads()
                    }
                    if LiveNotificationManager.shared.healthSummary == nil {
                        print("[websocket] 📊 Requesting health summary (fallback)")
                        self.requestHealthSummary()
                    }
                }
                
                // Mirroring is user-initiated from the UI; do not auto-start here.
               }


        case .notification:
            if let dict = message.data.value as? [String: Any],
               let nid = dict["id"] as? String,
               let title = dict["title"] as? String,
               let body = dict["body"] as? String,
               let app = dict["app"] as? String,
               let package = dict["package"] as? String {
                var actions: [NotificationAction] = []
                if let arr = dict["actions"] as? [[String: Any]] {
                    for a in arr {
                        if let name = a["name"] as? String, let typeStr = a["type"] as? String,
                           let t = NotificationAction.ActionType(rawValue: typeStr) {
                            actions.append(NotificationAction(name: name, type: t))
                        }
                    }
                }
                let notif = Notification(title: title, body: body, app: app, nid: nid, package: package, actions: actions)
                print("[websocket] notification: id=\(nid) title=\(title) app=\(app)")
                DispatchQueue.main.async {
                    AppState.shared.addNotification(notif)
                }
            }
        
        case .callEvent:
            if let dict = message.data.value as? [String: Any],
               let eventId = dict["eventId"] as? String,
               let number = dict["number"] as? String,
               let normalizedNumber = dict["normalizedNumber"] as? String,
               let directionStr = dict["direction"] as? String,
               let direction = CallDirection(rawValue: directionStr),
               let stateStr = dict["state"] as? String,
               let state = CallState(rawValue: stateStr) {
                
                // contactName is optional - fallback to normalizedNumber if missing
                let contactName = (dict["contactName"] as? String) ?? normalizedNumber
                
                // Handle timestamp as either Int or Int64
                var timestamp: Int64 = 0
                if let ts = dict["timestamp"] as? Int64 {
                    timestamp = ts
                } else if let ts = dict["timestamp"] as? Int {
                    timestamp = Int64(ts)
                } else if let ts = dict["timestamp"] as? NSNumber {
                    timestamp = ts.int64Value
                }
                
                let deviceId = dict["deviceId"] as? String ?? ""
                let contactPhoto = dict["contactPhoto"] as? String
                
                print("[websocket] Raw normalizedNumber: '\(normalizedNumber)' (length: \(normalizedNumber.count))")
                print("[websocket] Raw number: '\(number)' (length: \(number.count))")
                print("[websocket] Decoded call event - name: \(contactName), state: \(state), phone: \(normalizedNumber)")
                
                let callEvent = CallEvent(
                    eventId: eventId,
                    contactName: contactName,
                    number: number,
                    normalizedNumber: normalizedNumber,
                    direction: direction,
                    state: state,
                    timestamp: timestamp,
                    deviceId: deviceId,
                    contactPhoto: contactPhoto
                )
                print("[websocket] CallEvent created - normalizedNumber: '\(callEvent.normalizedNumber)' (length: \(callEvent.normalizedNumber.count))")
                print("[websocket] Call event: \(contactName) - \(state.rawValue)")
                DispatchQueue.main.async {
                    AppState.shared.updateCallEvent(callEvent)
                }
            } else {
                print("[websocket] Failed to decode call event - missing or invalid fields")
                if let dict = message.data.value as? [String: Any] {
                    print("[websocket] Available fields: \(dict.keys.joined(separator: ", "))")
                }
            }
        
        case .notificationActionResponse:
            if let dict = message.data.value as? [String: Any],
               let id = dict["id"] as? String,
               let action = dict["action"] as? String,
               let success = dict["success"] as? Bool {
                let msg = dict["message"] as? String ?? ""
                print("[websocket] Notification action response id=\(id) action=\(action) success=\(success) message=\(msg)")
            }
        case .notificationAction:
            print("[websocket] Warning: received 'notificationAction' from remote (ignored).")
        case .notificationUpdate:
            if let dict = message.data.value as? [String: Any],
               let nid = dict["id"] as? String {
                if let action = dict["action"] as? String, action.lowercased() == "dismiss" || dict["dismissed"] as? Bool == true {
                    DispatchQueue.main.async {
                        // Remove from in-memory list if present; ignore if not found.
                        let existed = AppState.shared.notifications.contains { $0.nid == nid }
                        if existed {
                            AppState.shared.removeNotificationById(nid)
                        }
                        // Ensure system notification also removed.
                        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [nid])
                    }
                }
            }

        case .status:
            if let dict = message.data.value as? [String: Any],
               let battery = dict["battery"] as? [String: Any],
               let level = battery["level"] as? Int,
               let isCharging = battery["isCharging"] as? Bool,
               let paired = dict["isPaired"] as? Bool,
               let music = dict["music"] as? [String: Any],
               let playing = music["isPlaying"] as? Bool,
               let title = music["title"] as? String,
               let artist = music["artist"] as? String,
               let volume = music["volume"] as? Int,
               let isMuted = music["isMuted"] as? Bool
            {
                let albumArt = (music["albumArt"] as? String) ?? ""
                let likeStatus = (music["likeStatus"] as? String) ?? "none"

                DispatchQueue.main.async {
                    AppState.shared.status = DeviceStatus(
                        battery: .init(level: level, isCharging: isCharging),
                        isPaired: paired,
                        music: .init(
                            isPlaying: playing,
                            title: title,
                            artist: artist,
                            volume: volume,
                            isMuted: isMuted,
                            albumArt: albumArt,
                            likeStatus: likeStatus
                        )
                    )
                }
                print("[websocket] status: battery=\(level)% charging=\(isCharging) music=\(title) playing=\(playing)")
            }


        case .dismissalResponse:
            if let dict = message.data.value as? [String: Any],
               let id = dict["id"] as? String,
               let success = dict["success"] as? Bool {
                print("[websocket] Dismissal \(success ? "succeeded" : "failed") for notification id: \(id)")
            }

        case .mediaControlRequest:
            // Mac sends this to Android, shouldn't receive it
            print("[websocket] Warning: received 'mediaControlRequest' from remote (ignored).")
            
        case .macMediaControl:
            // Mac sends this to Android, shouldn't receive it
            print("[websocket] Warning: received 'macMediaControl' from remote (ignored).")
            
        case .macInfo:
            // Mac sends this to Android, shouldn't receive it
            print("[websocket] Warning: received 'macInfo' from remote (ignored).")
            
        case .macMediaControlResponse:
            if let dict = message.data.value as? [String: Any],
               let action = dict["action"] as? String,
               let success = dict["success"] as? Bool {
                print("[websocket] 🎵 Mac media control \(action) \(success ? "succeeded" : "failed")")
            }
            
        case .mediaControlResponse:
            if let dict = message.data.value as? [String: Any],
               let action = dict["action"] as? String,
               let success = dict["success"] as? Bool {
                print("[websocket] Media control \(action) \(success ? "succeeded" : "failed")")
            }

        case .appIcons:
            if let dict = message.data.value as? [String: [String: Any]] {
                print("[websocket] appIcons: incoming=\(dict.count)")
                DispatchQueue.global(qos: .userInitiated).async {
                    let incomingPackages = Set(dict.keys)
                    let existingPackages = Set(AppState.shared.androidApps.keys)
                    var updates: [(String, AndroidApp)] = []
                    var toRemove: [String] = []

                    // Decode & write/update icons
                    for (package, details) in dict {
                        guard let name = details["name"] as? String,
                              let iconBase64 = details["icon"] as? String,
                              let systemApp = details["systemApp"] as? Bool,
                              let listening = details["listening"] as? Bool else { continue }

                        var cleaned = iconBase64
                        if let range = cleaned.range(of: "base64,") { cleaned = String(cleaned[range.upperBound...]) }

                        var iconPath: String? = nil
                        if let data = Data(base64Encoded: cleaned) {
                            let fileURL = appIconsDirectory().appendingPathComponent("\(package).png")
                            do {
                                try data.write(to: fileURL, options: .atomic)
                                iconPath = fileURL.path
                            } catch {
                                print("[websocket] Failed to write icon for \(package): \(error)")
                            }
                        }

                        let app = AndroidApp(
                            packageName: package,
                            name: name,
                            iconUrl: iconPath,
                            listening: listening,
                            systemApp: systemApp
                        )
                        updates.append((package, app))
                    }

                    // Determine apps to remove
                    toRemove = Array(existingPackages.subtracting(incomingPackages))

                    DispatchQueue.main.async {
                        for (pkg, app) in updates {
                            AppState.shared.androidApps[pkg] = app
                            if let iconPath = app.iconUrl { AppState.shared.androidApps[pkg]?.iconUrl = iconPath }
                        }
                        for pkg in toRemove {
                            if let iconPath = AppState.shared.androidApps[pkg]?.iconUrl {
                                try? FileManager.default.removeItem(atPath: iconPath)
                            }
                            AppState.shared.androidApps.removeValue(forKey: pkg)
                        }
                        AppState.shared.saveAppsToDisk()
                    }
                }
            }


        case .clipboardUpdate:
            if let dict = message.data.value as? [String: Any],
               let text = dict["text"] as? String {
                print("[websocket] clipboardUpdate len=\(text.count)")
                DispatchQueue.main.async {
                    AppState.shared.updateClipboardFromAndroid(text)
                }
            }

        // File transfer messages (Android -> Mac)
        case .fileTransferInit:
            if let dict = message.data.value as? [String: Any] {
                // Support both old and new format
                let id = (dict["transferId"] as? String) ?? (dict["id"] as? String)
                let name = (dict["fileName"] as? String) ?? (dict["name"] as? String)
                let size = (dict["fileSize"] as? Int) ?? (dict["size"] as? Int)
                let mime = dict["mime"] as? String ?? "application/octet-stream"
                let checksum = dict["checksum"] as? String
                
                guard let transferId = id, let fileName = name, let fileSize = size else {
                    print("[websocket] (file-transfer) init: missing required fields")
                    return
                }
                
                print("[websocket] (file-transfer) init id=\(transferId) name=\(fileName) size=\(fileSize) mime=\(mime) checksum=\(checksum ?? "nil")")

                let tempDir = FileManager.default.temporaryDirectory
                let safeName = fileName.replacingOccurrences(of: "/", with: "_")
                let tempFile = tempDir.appendingPathComponent("incoming_\(transferId)_\(safeName)")
                FileManager.default.createFile(atPath: tempFile.path, contents: nil, attributes: nil)
                let handle = try? FileHandle(forWritingTo: tempFile)

                let io = IncomingFileIO(tempUrl: tempFile, fileHandle: handle)
                incomingFiles[transferId] = io
                if let checksum = checksum {
                    incomingFilesChecksum[transferId] = checksum
                }
                // Start tracking incoming transfer in AppState
                DispatchQueue.main.async {
                    AppState.shared.startIncomingTransfer(id: transferId, name: fileName, size: fileSize, mime: mime)
                }
            }

        case .fileChunk:
            if let dict = message.data.value as? [String: Any] {
                // Support both old and new format
                let id = (dict["transferId"] as? String) ?? (dict["id"] as? String)
                let chunkBase64 = (dict["data"] as? String) ?? (dict["chunk"] as? String)
                
                guard let transferId = id, let chunkData = chunkBase64,
                      let io = incomingFiles[transferId],
                      let data = Data(base64Encoded: chunkData) else {
                    return
                }
                
                io.fileHandle?.seekToEndOfFile()
                io.fileHandle?.write(data)
                // Update incoming progress in AppState (increment)
                DispatchQueue.main.async {
                    let prev = AppState.shared.transfers[transferId]?.bytesTransferred ?? 0
                    let newBytes = prev + data.count
                    AppState.shared.updateIncomingProgress(id: transferId, receivedBytes: newBytes)
                    print("[websocket] (file-transfer) chunk id=\(transferId) size=\(data.count) receivedBytes=\(newBytes)")
                }
            }

        case .fileChunkAck:
            if let dict = message.data.value as? [String: Any],
               let id = dict["id"] as? String,
               let index = dict["index"] as? Int {
                var set = outgoingAcks[id] ?? []
                set.insert(index)
                outgoingAcks[id] = set
                print("[websocket] (file-transfer) Received ack for id=\(id) index=\(index) totalAcked=\(set.count)")
            }

        case .fileTransferComplete:
                if let dict = message.data.value as? [String: Any] {
                    // Support both old and new format
                    let id = (dict["transferId"] as? String) ?? (dict["id"] as? String)
                    
                    guard let transferId = id, let state = incomingFiles[transferId] else {
                        print("[websocket] (file-transfer) complete: transfer not found")
                        return
                    }
                    
                    state.fileHandle?.closeFile()
                    print("[websocket] (file-transfer) complete id=\(transferId) temp=\(state.tempUrl.path)")

                    // Resolve a name for notifications and final filename. Prefer AppState metadata; fall back to temp filename.
                    let resolvedName = AppState.shared.transfers[transferId]?.name ?? state.tempUrl.lastPathComponent

                    // Verify checksum if present
                    if let expected = incomingFilesChecksum[transferId] {
                        if let fileData = try? Data(contentsOf: state.tempUrl) {
                            // Compute SHA256 checksum
                            let computed = SHA256.hash(data: fileData).compactMap { String(format: "%02x", $0) }.joined()
                            print("[websocket] (file-transfer) Checksum verification: expected=\(expected.prefix(16))... computed=\(computed.prefix(16))...")
                            print("[websocket] (file-transfer) Expected length: \(expected.count), Computed length: \(computed.count)")
                            
                            // Check if Android sent MD5 (32 chars) instead of SHA256 (64 chars)
                            if expected.count == 32 && computed.count == 64 {
                                print("[websocket] (file-transfer) ⚠️ MISMATCH: Android sent MD5 (32 chars) but Mac computed SHA256 (64 chars)")
                                print("[websocket] (file-transfer) 💡 Android needs to use SHA256 instead of MD5 for checksums")
                                DispatchQueue.main.async {
                                    AppState.shared.postNativeNotification(
                                        id: "incoming_file_\(transferId)_mismatch",
                                        appName: "AirSync",
                                        title: "Received: \(resolvedName)",
                                        body: "Saved to Downloads (checksum algorithm mismatch: MD5 vs SHA256)"
                                    )
                                }
                            } else if computed != expected {
                                print("[websocket] (file-transfer) ❌ Checksum mismatch for incoming file id=\(transferId)")
                                DispatchQueue.main.async {
                                    AppState.shared.postNativeNotification(
                                        id: "incoming_file_\(transferId)_mismatch",
                                        appName: "AirSync",
                                        title: "Received: \(resolvedName)",
                                        body: "Saved to Downloads (checksum mismatch)"
                                    )
                                }
                            } else {
                                print("[websocket] (file-transfer) ✅ Checksum verified successfully")
                            }
                        }
                        incomingFilesChecksum.removeValue(forKey: transferId)
                    }

                    // Move to Downloads
                    if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
                        do {
                            let finalDest = downloads.appendingPathComponent(resolvedName)
                            if FileManager.default.fileExists(atPath: finalDest.path) {
                                try FileManager.default.removeItem(at: finalDest)
                            }
                            try FileManager.default.moveItem(at: state.tempUrl, to: finalDest)

                            // Optionally: show a user notification (simple print for now)
                            print("[websocket] (file-transfer) ✅ Saved incoming file to \(finalDest.path)")

                            // Mark as completed in AppState and post notification via AppState util
                            DispatchQueue.main.async {
                                AppState.shared.completeIncoming(id: transferId, verified: nil)
                                AppState.shared.postNativeNotification(
                                    id: "incoming_file_\(transferId)",
                                    appName: "AirSync",
                                    title: "Received: \(resolvedName)",
                                    body: "Saved to Downloads"
                                )
                            }
                            
                            // Send verification back to Android
                            let verifyMessage = """
                            {
                                "type": "transferVerified",
                                "data": {
                                    "id": "\(transferId)",
                                    "verified": true
                                }
                            }
                            """
                            sendToFirstAvailable(message: verifyMessage)
                        } catch {
                            print("[websocket] (file-transfer) ❌ Failed to move incoming file: \(error)")
                        }
                    }

                    incomingFiles.removeValue(forKey: transferId)
            }
        case .transferVerified:
            if let dict = message.data.value as? [String: Any],
               let id = dict["id"] as? String,
               let verified = dict["verified"] as? Bool {
                print("[websocket] (file-transfer) Received transferVerified for id=\(id) verified=\(verified)")
                // Update AppState and show a confirmation notification via AppState util
                DispatchQueue.main.async {
                    AppState.shared.completeOutgoingVerified(id: id, verified: verified)
                    AppState.shared.postNativeNotification(
                        id: "transfer_verified_\(id)",
                        appName: "AirSync",
                        title: "Transfer verified",
                        body: verified ? "Receiver verified the file checksum" : "Receiver reported checksum mismatch"
                    )
                }
            }
            
        case .wakeUpRequest:
            // This case handles wake-up requests from Android to Mac
            // Currently not expected as Mac sends wake-up requests to Android, not vice versa
            print("[websocket] Received wakeUpRequest from Android (not typically expected)")
            
        case .wallpaperResponse:
            if let dict = message.data.value as? [String: Any] {
                let success = dict["success"] as? Bool ?? false
                let msg = dict["message"] as? String
                let wallpaperB64 = dict["wallpaper"] as? String
                print("[websocket] wallpaperResponse success=\(success) message=\(msg ?? "") wallpaperLen=\(wallpaperB64?.count ?? 0)")

                DispatchQueue.global(qos: .utility).async {
                    var stored: String? = nil
                    if let wallpaperB64 = wallpaperB64, !wallpaperB64.isEmpty {
                        stored = wallpaperB64
                    }
                    DispatchQueue.main.async {
                        if let stored = stored {
                            AppState.shared.currentDeviceWallpaperBase64 = stored
                        }
                    }
                }
            }
            
        case .mirrorRequest:
            if let dict = message.data.value as? [String: Any],
               let action = dict["action"] as? String {
                let mode = dict["mode"] as? String
                let package = dict["package"] as? String
                let options = dict["options"] as? [String: Any] ?? [:]

                if action == "start" {
                    if AppState.shared.isMirrorActive {
                        print("[websocket] Mirror already active; ignoring duplicate start")
                        sendMirrorResponse(["status": "already_active"]) 
                        return
                    }
                    guard AppState.shared.isPlus else {
                        sendMirrorResponse(["status": "error", "message": "Mirror feature requires Plus subscription"])
                        return
                    }
                    guard let device = AppState.shared.device else {
                        sendMirrorResponse(["status": "error", "message": "No connected device"])
                        return
                    }
                    guard AppState.shared.adbConnected else {
                        sendMirrorResponse(["status": "error", "message": "ADB not connected"])
                        return
                    }
                    // Save current scrcpy settings to restore after start
                    var originalBitrate = 0
                    var originalResolution = 0
                    DispatchQueue.main.sync {
                        originalBitrate = AppState.shared.scrcpyBitrate
                        originalResolution = AppState.shared.scrcpyResolution
                    }

                    // Override bitrate/resolution if options provided (expecting Int)
                    if let bitrateOpt = options["bitrate"] as? Int {
                        DispatchQueue.main.async {
                            AppState.shared.scrcpyBitrate = bitrateOpt
                        }
                    }
                    if let resolutionOpt = options["resolution"] as? Int {
                        DispatchQueue.main.async {
                            AppState.shared.scrcpyResolution = resolutionOpt
                        }
                    }

                    if mode == "app", let pkg = package, !pkg.isEmpty {
                        ADBConnector.startScrcpy(ip: device.ipAddress, port: AppState.shared.adbPort, deviceName: device.name, package: pkg)
                        sendMirrorResponse([
                            "status": "started",
                            "mode": "app",
                            "package": pkg,
                            "transport": "websocket",
                            "wsUrl": "ws://\(self.localIPAddress ?? "127.0.0.1"):\(self.localPort ?? Defaults.serverPort)/socket"
                        ])
                    } else if mode == "desktop" {
                        ADBConnector.startScrcpy(ip: device.ipAddress, port: AppState.shared.adbPort, deviceName: device.name, desktop: true)
                        sendMirrorResponse([
                            "status": "started",
                            "mode": "desktop",
                            "package": "",
                            "transport": "websocket",
                            "wsUrl": "ws://\(self.localIPAddress ?? "127.0.0.1"):\(self.localPort ?? Defaults.serverPort)/socket"
                        ])
                    } else {
                        ADBConnector.startScrcpy(ip: device.ipAddress, port: AppState.shared.adbPort, deviceName: device.name)
                        sendMirrorResponse([
                            "status": "started",
                            "mode": "device",
                            "package": "",
                            "transport": "websocket",
                            "wsUrl": "ws://\(self.localIPAddress ?? "127.0.0.1"):\(self.localPort ?? Defaults.serverPort)/socket"
                        ])
                    }

                    // Restore original scrcpy settings to avoid side effects
                    DispatchQueue.main.async {
                        AppState.shared.scrcpyBitrate = originalBitrate
                        AppState.shared.scrcpyResolution = originalResolution
                    }

                } else if action == "stop" {
                    // No direct stop API here; placeholder
                    // Could implement sending AppleScript or other means to kill scrcpy process or signal to stop
                    sendMirrorResponse(["status": "not_implemented"])
                } else {
                    sendMirrorResponse(["status": "error", "message": "Unknown mirrorRequest action"])
                }
            }
            
        case .mirrorResponse:
            if let dict = message.data.value as? [String: Any] {
                let status = dict["status"] as? String ?? "unknown"
                let message = dict["message"] as? String ?? ""
                let mode = dict["mode"] as? String ?? ""
                let package = dict["package"] as? String ?? ""
                print("[websocket] mirrorResponse status=\(status) message=\(message) mode=\(mode) package=\(package)")
            }
            
        case .mirrorStart:
            print("[mirror] 📥 Received mirrorStart from Android")
            if let dict = message.data.value as? [String: Any] {
                if self.activeSessions.count > 1 {
                    // Keep only the last (most recent) session; drop references to older ones
                    if let last = self.activeSessions.last {
                        self.activeSessions = [last]
                    }
                    print("[mirror] Pruned extra sessions; now \(self.activeSessions.count)")
                }
                DispatchQueue.main.async {
                    let wasActive = AppState.shared.isMirrorActive
                    AppState.shared.isMirrorActive = true
                    AppState.shared.isMirrorRequestPending = false
                    AppState.shared.isMirroring = true
                    AppState.shared.mirrorError = nil
                    #if os(macOS)
                    self.presentMirrorWindowIfNeeded()
                    #endif
                    if !wasActive {
                        print("[mirror] ✅ Mirror started successfully -> presenting UI now")
                    }
                }
                // Optionally parse parameters for debugging
                print("[mirror] 📊 Mirror parameters: fps=\(dict["fps"] ?? "nil") quality=\(dict["quality"] ?? "nil") width=\(dict["width"] ?? "nil") height=\(dict["height"] ?? "nil")")
                sendMirrorAck(action: "start", ok: true)
            } else {
                print("[mirror] ❌ Mirror start failed: Missing data")
                sendMirrorAck(action: "start", ok: false, message: "Missing data for mirrorStart")
                DispatchQueue.main.async {
                    AppState.shared.isMirrorRequestPending = false
                    AppState.shared.mirrorError = "Mirror start failed: Invalid data from Android"
                }
            }

        case .mirrorStop:
            print("[mirror] 🛑 Received mirrorStop from Android")
            DispatchQueue.main.async {
                AppState.shared.isMirrorActive = false
                AppState.shared.latestMirrorFrame = nil
                AppState.shared.isMirroring = false
                AppState.shared.isMirrorRequestPending = false
                #if os(macOS)
                self.mirrorWindow?.close()
                self.mirrorWindow = nil
                #endif
                print("[mirror] ✅ Mirror stopped successfully")
            }
            sendMirrorAck(action: "stop", ok: true)

        case .mirrorFrame:
            if let dict = message.data.value as? [String: Any] {
                let base64Payload = (dict["image"] as? String) ?? (dict["frame"] as? String)
                let format = (dict["format"] as? String)?.lowercased()
                let isConfig = (dict["isConfig"] as? Bool) ?? false

                guard let base64 = base64Payload, let data = Data(base64Encoded: base64) else {
                    print("[websocket] mirrorFrame failed to decode base64 payload")
                    break
                }

                if format == "h264" || format == nil {
                    h264Decoder.decode(frameData: data, isConfig: isConfig)
                } else {
                    // Handle JPEG/PNG as before
                    if let nsImage = NSImage(data: data) {
                        DispatchQueue.main.async {
                            let wasActive = AppState.shared.isMirrorActive
                            if !wasActive {
                                AppState.shared.isMirrorActive = true
                                // Removed posting notification line here as per instructions
                            }
                            AppState.shared.latestMirrorFrame = nsImage
                        }
                    } else {
                        print("[websocket] mirrorFrame failed to create NSImage from decoded data (format=\(format ?? "unknown"))")
                    }
                }
            }

        case .remoteConnectResponse:
            if let dict = message.data.value as? [String: Any],
               let features = dict["features"] as? [String] {
                print("[websocket] remoteConnectResponse features: \(features)")
                // Optionally: set a flag in AppState if needed
                // e.g. AppState.shared.remoteConnectFeatures = features
            }
            
        case .screenshotResponse:
            if let dict = message.data.value as? [String: Any],
               let base64Image = dict["image"] as? String {
                if let imageData = Data(base64Encoded: base64Image) {
                    if let nsImage = NSImage(data: imageData) {
                        DispatchQueue.main.async {
                            AppState.shared.latestMirrorFrame = nsImage // Reuse latestMirrorFrame for screenshot
                            AppState.shared.isMirrorActive = false      // On-demand screenshot, not active mirror stream
                        }
                    } else {
                        print("[websocket] screenshotResponse failed to create NSImage from data")
                    }
                } else {
                    print("[websocket] screenshotResponse failed to decode base64 image data")
                }
            }

        case .remoteConnectRequest:
            if let dict = message.data.value as? [String: Any], let features = dict["features"] as? [String] {
                print("[websocket] Received remoteConnectRequest (unexpected on Mac) features=\(features)")
            } else {
                print("[websocket] Received remoteConnectRequest (unexpected on Mac)")
            }
            
        case .inputEvent:
            if let dict = message.data.value as? [String: Any] {
                print("[remote-control] 📥 Received inputEvent response from Android: \(dict)")
                if let success = dict["success"] as? Bool {
                    if success {
                        print("[remote-control] ✅ Input event processed successfully on Android")
                    } else {
                        let error = dict["error"] as? String ?? "Unknown error"
                        print("[remote-control] ❌ Input event failed on Android: \(error)")
                    }
                }
            } else {
                print("[remote-control] ⚠️ Received inputEvent from Android (unexpected format)")
            }
            
        case .navAction:
            if let dict = message.data.value as? [String: Any] {
                print("[remote-control] 📥 Received navAction response from Android: \(dict)")
                if let success = dict["success"] as? Bool {
                    if success {
                        print("[remote-control] ✅ Nav action processed successfully on Android")
                    } else {
                        let error = dict["error"] as? String ?? "Unknown error"
                        print("[remote-control] ❌ Nav action failed on Android: \(error)")
                    }
                }
            } else {
                print("[remote-control] ⚠️ Received navAction from Android (unexpected format)")
            }
            
        case .launchApp:
            print("[websocket] Received launchApp from Android (ignored on Mac)")
            
        case .screenshotRequest:
            print("[websocket] Received screenshotRequest from Android (ignored on Mac)")
            
        // MARK: - SMS/Messaging Handlers
        case .smsThreads:
            print("[websocket] 📱 Received smsThreads message")
            if let dict = message.data.value as? [String: Any] {
                print("[websocket] 📱 SMS data dict keys: \(dict.keys)")
                if let threadsData = dict["threads"] as? [[String: Any]] {
                    print("[websocket] 📱 Processing \(threadsData.count) SMS threads")
                    let threads = threadsData.compactMap { threadDict -> SmsThread? in
                        guard let threadId = threadDict["threadId"] as? String,
                              let address = threadDict["address"] as? String,
                              let messageCount = threadDict["messageCount"] as? Int,
                              let snippet = threadDict["snippet"] as? String else {
                            print("[websocket] ❌ Failed to parse SMS thread - missing required fields")
                            return nil
                        }
                        
                        // Parse date as Int or Int64
                        let dateMs: Int64
                        if let date64 = threadDict["date"] as? Int64 {
                            dateMs = date64
                        } else if let dateInt = threadDict["date"] as? Int {
                            dateMs = Int64(dateInt)
                        } else {
                            print("[websocket] ❌ Failed to parse date for SMS thread")
                            return nil
                        }
                        
                        let unreadCount = threadDict["unreadCount"] as? Int ?? 0
                        
                        return SmsThread(
                            threadId: threadId,
                            address: address,
                            contactName: threadDict["contactName"] as? String,
                            messageCount: messageCount,
                            snippet: snippet,
                            date: Date(timeIntervalSince1970: Double(dateMs) / 1000.0),
                            unreadCount: unreadCount
                        )
                    }
                    print("[websocket] 📱 Successfully parsed \(threads.count) SMS threads")
                    LiveNotificationManager.shared.handleSmsThreads(threads)
                    print("[websocket] 📱 SMS threads sent to LiveNotificationManager")
                } else {
                    print("[websocket] ❌ Failed to parse threads array from SMS data")
                }
            } else {
                print("[websocket] ❌ Failed to parse smsThreads data dict")
            }
            
        case .smsMessages:
            print("[websocket] 📱 Received smsMessages")
            if let dict = message.data.value as? [String: Any] {
                print("[websocket] 📱 SMS messages data dict keys: \(dict.keys)")
                if let messagesData = dict["messages"] as? [[String: Any]] {
                    print("[websocket] 📱 Processing \(messagesData.count) SMS messages")
                    let messages = messagesData.compactMap { messageDict -> SmsMessage? in
                        guard let id = messageDict["id"] as? String,
                              let threadId = messageDict["threadId"] as? String,
                              let address = messageDict["address"] as? String,
                              let body = messageDict["body"] as? String,
                              let type = messageDict["type"] as? Int,
                              let read = messageDict["read"] as? Bool else {
                            print("[websocket] ❌ Failed to parse SMS message - missing required fields")
                            return nil
                        }
                        
                        // Parse date as Int or Int64
                        let dateMs: Int64
                        if let date64 = messageDict["date"] as? Int64 {
                            dateMs = date64
                        } else if let dateInt = messageDict["date"] as? Int {
                            dateMs = Int64(dateInt)
                        } else {
                            print("[websocket] ❌ Failed to parse date for SMS message")
                            return nil
                        }
                        
                        return SmsMessage(
                            id: id,
                            threadId: threadId,
                            address: address,
                            body: body,
                            date: Date(timeIntervalSince1970: Double(dateMs) / 1000.0),
                            type: type,
                            read: read,
                            contactName: messageDict["contactName"] as? String
                        )
                    }
                    print("[websocket] 📱 Successfully parsed \(messages.count) SMS messages")
                    LiveNotificationManager.shared.handleSmsMessages(messages)
                    print("[websocket] 📱 SMS messages sent to LiveNotificationManager")
                } else {
                    print("[websocket] ❌ Failed to parse messages array from SMS data")
                }
            } else {
                print("[websocket] ❌ Failed to parse smsMessages data dict")
            }
            
        case .smsSendResponse:
            if let dict = message.data.value as? [String: Any],
               let success = dict["success"] as? Bool {
                let msg = dict["message"] as? String ?? ""
                print("[websocket] SMS send \(success ? "succeeded" : "failed"): \(msg)")
            }
            
        case .smsReceived:
            if let dict = message.data.value as? [String: Any],
               let id = dict["id"] as? String,
               let threadId = dict["threadId"] as? String,
               let address = dict["address"] as? String,
               let body = dict["body"] as? String,
               let dateMs = dict["date"] as? Int64,
               let _ = dict["type"] as? Int, // SMS type (1=received, 2=sent)
               let read = dict["read"] as? Bool {
                
                let sms = LiveSmsNotification(
                    id: id,
                    threadId: threadId,
                    address: address,
                    contactName: dict["contactName"] as? String,
                    body: body,
                    date: Date(timeIntervalSince1970: Double(dateMs) / 1000.0),
                    read: read
                )
                LiveNotificationManager.shared.handleSmsReceived(sms)
                print("[websocket] New SMS from \(sms.displayName)")
            }
            
        // MARK: - Call Log Handlers
        case .callLogs:
            print("[websocket] 📞 Received callLogs message")
            if let dict = message.data.value as? [String: Any] {
                print("[websocket] 📞 Call logs data dict keys: \(dict.keys)")
                if let logsData = dict["logs"] as? [[String: Any]] {
                    print("[websocket] 📞 Processing \(logsData.count) call log entries")
                    let logs = logsData.compactMap { logDict -> CallLogEntry? in
                        guard let id = logDict["id"] as? String,
                              let number = logDict["number"] as? String,
                              let type = logDict["type"] as? String,
                              let duration = logDict["duration"] as? Int,
                              let isRead = logDict["isRead"] as? Bool else {
                            print("[websocket] ❌ Failed to parse call log - missing required fields")
                            return nil
                        }
                        
                        // Parse date as Int or Int64
                        let dateMs: Int64
                        if let date64 = logDict["date"] as? Int64 {
                            dateMs = date64
                        } else if let dateInt = logDict["date"] as? Int {
                            dateMs = Int64(dateInt)
                        } else {
                            print("[websocket] ❌ Failed to parse date for call log")
                            return nil
                        }
                        
                        return CallLogEntry(
                            id: id,
                            number: number,
                            contactName: logDict["contactName"] as? String,
                            type: type,
                            date: Date(timeIntervalSince1970: Double(dateMs) / 1000.0),
                            duration: duration,
                            isRead: isRead
                        )
                    }
                    print("[websocket] 📞 Successfully parsed \(logs.count) call log entries")
                    LiveNotificationManager.shared.handleCallLogs(logs)
                    print("[websocket] 📞 Call logs sent to LiveNotificationManager")
                } else {
                    print("[websocket] ❌ Failed to parse logs array from call data")
                }
            } else {
                print("[websocket] ❌ Failed to parse callLogs data dict")
            }
            
        // MARK: - Live Call Notification Handlers
        case .callNotification:
            if let dict = message.data.value as? [String: Any],
               let id = dict["id"] as? String,
               let number = dict["number"] as? String,
               let stateStr = dict["state"] as? String,
               let startTimeMs = dict["startTime"] as? Int64,
               let isIncoming = dict["isIncoming"] as? Bool,
               let state = CallState(rawValue: stateStr) {
                
                let call = LiveCallNotification(
                    id: id,
                    number: number,
                    contactName: dict["contactName"] as? String,
                    state: state,
                    startTime: Date(timeIntervalSince1970: Double(startTimeMs) / 1000.0),
                    isIncoming: isIncoming
                )
                LiveNotificationManager.shared.handleCallNotification(call)
                print("[websocket] Call notification: \(call.displayName) - \(state)")
            }
            
        case .callActionResponse:
            if let dict = message.data.value as? [String: Any],
               let action = dict["action"] as? String,
               let success = dict["success"] as? Bool {
                let msg = dict["message"] as? String ?? ""
                print("[websocket] Call action '\(action)' \(success ? "succeeded" : "failed"): \(msg)")
            }
            
        // MARK: - Health Data Handlers
        case .healthSummary:
            print("[websocket] 📊 Received healthSummary message")
            if let dict = message.data.value as? [String: Any] {
                print("[websocket] 📊 Health data dict: \(dict)")
                
                // Try to parse date as Int64, Int, or Double
                let dateMs: Int64
                if let date64 = dict["date"] as? Int64 {
                    dateMs = date64
                } else if let dateInt = dict["date"] as? Int {
                    dateMs = Int64(dateInt)
                } else if let dateDouble = dict["date"] as? Double {
                    dateMs = Int64(dateDouble)
                } else {
                    print("[websocket] ❌ Failed to parse date from health summary - type: \(type(of: dict["date"]))")
                    break
                }
                
                print("[websocket] 📊 Parsing health summary with date: \(dateMs)")
                
                // Filter out 0 values for heart rate (treat as nil)
                let heartRateAvg = dict["heartRateAvg"] as? Int
                let heartRateMin = dict["heartRateMin"] as? Int
                let heartRateMax = dict["heartRateMax"] as? Int
                
                let summary = HealthSummary(
                    date: Date(timeIntervalSince1970: Double(dateMs) / 1000.0),
                    steps: dict["steps"] as? Int,
                    distance: dict["distance"] as? Double,
                    calories: dict["calories"] as? Int,
                    activeMinutes: dict["activeMinutes"] as? Int,
                    heartRateAvg: (heartRateAvg == 0) ? nil : heartRateAvg,
                    heartRateMin: (heartRateMin == 0) ? nil : heartRateMin,
                    heartRateMax: (heartRateMax == 0) ? nil : heartRateMax,
                    sleepDuration: dict["sleepDuration"] as? Int,
                    floorsClimbed: dict["floorsClimbed"] as? Int,
                    weight: dict["weight"] as? Double,
                    bloodPressureSystolic: dict["bloodPressureSystolic"] as? Int,
                    bloodPressureDiastolic: dict["bloodPressureDiastolic"] as? Int,
                    oxygenSaturation: dict["oxygenSaturation"] as? Double,
                    restingHeartRate: dict["restingHeartRate"] as? Int,
                    vo2Max: dict["vo2Max"] as? Double,
                    bodyTemperature: dict["bodyTemperature"] as? Double,
                    bloodGlucose: dict["bloodGlucose"] as? Double,
                    hydration: dict["hydration"] as? Double
                )
                print("[websocket] 📊 Created HealthSummary: steps=\(summary.steps ?? 0), calories=\(summary.calories ?? 0), distance=\(summary.distance ?? 0)")
                LiveNotificationManager.shared.handleHealthSummary(summary)
                print("[websocket] 📊 Health summary sent to LiveNotificationManager")
            } else {
                print("[websocket] ❌ Failed to parse health summary data dict")
            }
            
        case .healthData:
            print("[websocket] Received health data records")
            // Handle detailed health data if needed
            
        // Ignore requests sent from Android (shouldn't happen)
        case .requestSmsThreads, .requestSmsMessages, .sendSms, .markSmsRead,
             .requestCallLogs, .markCallLogRead, .callAction,
             .requestHealthSummary, .requestHealthData:
            print("[websocket] Received request message from Android (ignored)")
            
        @unknown default:
            print("[websocket] Warning: unhandled message type: \(message.type)")
            return
        }


    }

    // MARK: - Flexible Message Handling (JSONSerialization-based)
    
    func handleFlexibleMessage(_ message: FlexibleMessage) {
        switch message.type {
        case .device:
            if let name = message.data["name"] as? String,
               let ip = message.data["ipAddress"] as? String,
               let port = message.data["port"] as? Int {

                let version = message.data["version"] as? String ?? "2.0.0"

                DispatchQueue.main.async {
                    AppState.shared.device = Device(
                        name: name,
                        ipAddress: ip,
                        port: port,
                        version: version
                    )

                    if let base64 = message.data["wallpaper"] as? String {
                        AppState.shared.currentDeviceWallpaperBase64 = base64
                    }
                }

                if (!AppState.shared.adbConnected && AppState.shared.adbEnabled && AppState.shared.isPlus) {
                    ADBConnector.connectToADB(ip: ip)
                }

                // mark first-time pairing
                if UserDefaults.standard.hasPairedDeviceOnce == false {
                    UserDefaults.standard.hasPairedDeviceOnce = true
                }
                
                // Send Mac info response to Android
                sendMacInfoResponse()
                
                // Mirroring is user-initiated from the UI; do not auto-start here.
               }

        case .notification:
            if let nid = message.data["id"] as? String,
               let title = message.data["title"] as? String,
               let body = message.data["body"] as? String,
               let app = message.data["app"] as? String,
               let package = message.data["package"] as? String {
                var actions: [NotificationAction] = []
                if let arr = message.data["actions"] as? [[String: Any]] {
                    for a in arr {
                        if let name = a["name"] as? String, let typeStr = a["type"] as? String,
                           let t = NotificationAction.ActionType(rawValue: typeStr) {
                            actions.append(NotificationAction(name: name, type: t))
                        }
                    }
                }
                let notif = Notification(title: title, body: body, app: app, nid: nid, package: package, actions: actions)
                print("[websocket] notification: id=\(nid) title=\(title) app=\(app)")
                DispatchQueue.main.async {
                    AppState.shared.addNotification(notif)
                }
            }

        case .status:
            if let battery = message.data["battery"] as? [String: Any],
               let level = battery["level"] as? Int,
               let isCharging = battery["isCharging"] as? Bool,
               let paired = message.data["isPaired"] as? Bool,
               let music = message.data["music"] as? [String: Any],
               let playing = music["isPlaying"] as? Bool,
               let title = music["title"] as? String,
               let artist = music["artist"] as? String,
               let volume = music["volume"] as? Int,
               let isMuted = music["isMuted"] as? Bool
            {
                let albumArt = (music["albumArt"] as? String) ?? ""
                let likeStatus = (music["likeStatus"] as? String) ?? "none"

                DispatchQueue.main.async {
                    AppState.shared.status = DeviceStatus(
                        battery: .init(level: level, isCharging: isCharging),
                        isPaired: paired,
                        music: .init(
                            isPlaying: playing,
                            title: title,
                            artist: artist,
                            volume: volume,
                            isMuted: isMuted,
                            albumArt: albumArt,
                            likeStatus: likeStatus
                        )
                    )
                }
                print("[websocket] status: battery=\(level)% charging=\(isCharging) music=\(title) playing=\(playing)")
            }

        case .smsThreads:
            print("[websocket] 📱 Received smsThreads message")
            print("[websocket] 📱 SMS data dict keys: \(message.data.keys)")
            if let threadsData = message.data["threads"] as? [[String: Any]] {
                print("[websocket] 📱 Processing \(threadsData.count) SMS threads")
                let threads = threadsData.compactMap { threadDict -> SmsThread? in
                    guard let threadId = threadDict["threadId"] as? String,
                          let address = threadDict["address"] as? String,
                          let messageCount = threadDict["messageCount"] as? Int,
                          let snippet = threadDict["snippet"] as? String else {
                        print("[websocket] ❌ Failed to parse SMS thread - missing required fields")
                        return nil
                    }
                    
                    // Parse date as Int or Int64
                    let dateMs: Int64
                    if let date64 = threadDict["date"] as? Int64 {
                        dateMs = date64
                    } else if let dateInt = threadDict["date"] as? Int {
                        dateMs = Int64(dateInt)
                    } else {
                        print("[websocket] ❌ Failed to parse date for SMS thread")
                        return nil
                    }
                    
                    let unreadCount = threadDict["unreadCount"] as? Int ?? 0
                    
                    return SmsThread(
                        threadId: threadId,
                        address: address,
                        contactName: threadDict["contactName"] as? String,
                        messageCount: messageCount,
                        snippet: snippet,
                        date: Date(timeIntervalSince1970: Double(dateMs) / 1000.0),
                        unreadCount: unreadCount
                    )
                }
                print("[websocket] 📱 Successfully parsed \(threads.count) SMS threads")
                LiveNotificationManager.shared.handleSmsThreads(threads)
                print("[websocket] 📱 SMS threads sent to LiveNotificationManager")
            } else {
                print("[websocket] ❌ Failed to parse threads array from SMS data")
            }

        case .callLogs:
            print("[websocket] 📞 Received callLogs message")
            print("[websocket] 📞 Call logs data dict keys: \(message.data.keys)")
            if let logsData = message.data["logs"] as? [[String: Any]] {
                print("[websocket] 📞 Processing \(logsData.count) call log entries")
                let logs = logsData.compactMap { logDict -> CallLogEntry? in
                    guard let id = logDict["id"] as? String,
                          let number = logDict["number"] as? String,
                          let type = logDict["type"] as? String,
                          let duration = logDict["duration"] as? Int,
                          let isRead = logDict["isRead"] as? Bool else {
                        print("[websocket] ❌ Failed to parse call log - missing required fields")
                        return nil
                    }
                    
                    // Parse date as Int or Int64
                    let dateMs: Int64
                    if let date64 = logDict["date"] as? Int64 {
                        dateMs = date64
                    } else if let dateInt = logDict["date"] as? Int {
                        dateMs = Int64(dateInt)
                    } else {
                        print("[websocket] ❌ Failed to parse date for call log")
                        return nil
                    }
                    
                    return CallLogEntry(
                        id: id,
                        number: number,
                        contactName: logDict["contactName"] as? String,
                        type: type,
                        date: Date(timeIntervalSince1970: Double(dateMs) / 1000.0),
                        duration: duration,
                        isRead: isRead
                    )
                }
                print("[websocket] 📞 Successfully parsed \(logs.count) call log entries")
                LiveNotificationManager.shared.handleCallLogs(logs)
                print("[websocket] 📞 Call logs sent to LiveNotificationManager")
            } else {
                print("[websocket] ❌ Failed to parse logs array from call data")
            }

        case .healthSummary:
            print("[websocket] 📊 Received healthSummary message")
            print("[websocket] 📊 Health data dict: \(message.data)")
            
            // Try to parse date as Int64, Int, or Double
            let dateMs: Int64
            if let date64 = message.data["date"] as? Int64 {
                dateMs = date64
            } else if let dateInt = message.data["date"] as? Int {
                dateMs = Int64(dateInt)
            } else if let dateDouble = message.data["date"] as? Double {
                dateMs = Int64(dateDouble)
            } else {
                print("[websocket] ❌ Failed to parse date from health summary - type: \(type(of: message.data["date"]))")
                break
            }
            
            print("[websocket] 📊 Parsing health summary with date: \(dateMs)")
            
            // Filter out 0 values for heart rate (treat as nil)
            let heartRateAvg = message.data["heartRateAvg"] as? Int
            let heartRateMin = message.data["heartRateMin"] as? Int
            let heartRateMax = message.data["heartRateMax"] as? Int
            
            let summary = HealthSummary(
                date: Date(timeIntervalSince1970: Double(dateMs) / 1000.0),
                steps: message.data["steps"] as? Int,
                distance: message.data["distance"] as? Double,
                calories: message.data["calories"] as? Int,
                activeMinutes: message.data["activeMinutes"] as? Int,
                heartRateAvg: (heartRateAvg == 0) ? nil : heartRateAvg,
                heartRateMin: (heartRateMin == 0) ? nil : heartRateMin,
                heartRateMax: (heartRateMax == 0) ? nil : heartRateMax,
                sleepDuration: message.data["sleepDuration"] as? Int,
                floorsClimbed: message.data["floorsClimbed"] as? Int,
                weight: message.data["weight"] as? Double,
                bloodPressureSystolic: message.data["bloodPressureSystolic"] as? Int,
                bloodPressureDiastolic: message.data["bloodPressureDiastolic"] as? Int,
                oxygenSaturation: message.data["oxygenSaturation"] as? Double,
                restingHeartRate: message.data["restingHeartRate"] as? Int,
                vo2Max: message.data["vo2Max"] as? Double,
                bodyTemperature: message.data["bodyTemperature"] as? Double,
                bloodGlucose: message.data["bloodGlucose"] as? Double,
                hydration: message.data["hydration"] as? Double
            )
            print("[websocket] 📊 Created HealthSummary: steps=\(summary.steps ?? 0), calories=\(summary.calories ?? 0), distance=\(summary.distance ?? 0)")
            LiveNotificationManager.shared.handleHealthSummary(summary)
            print("[websocket] 📊 Health summary sent to LiveNotificationManager")

        case .smsMessages:
            print("[websocket] 📱 Received smsMessages")
            print("[websocket] 📱 SMS messages data dict keys: \(message.data.keys)")
            if let messagesData = message.data["messages"] as? [[String: Any]] {
                print("[websocket] 📱 Processing \(messagesData.count) SMS messages")
                let messages = messagesData.compactMap { messageDict -> SmsMessage? in
                    guard let id = messageDict["id"] as? String,
                          let threadId = messageDict["threadId"] as? String,
                          let address = messageDict["address"] as? String,
                          let body = messageDict["body"] as? String,
                          let type = messageDict["type"] as? Int,
                          let read = messageDict["read"] as? Bool else {
                        print("[websocket] ❌ Failed to parse SMS message - missing required fields")
                        return nil
                    }
                    
                    // Parse date as Int or Int64
                    let dateMs: Int64
                    if let date64 = messageDict["date"] as? Int64 {
                        dateMs = date64
                    } else if let dateInt = messageDict["date"] as? Int {
                        dateMs = Int64(dateInt)
                    } else {
                        print("[websocket] ❌ Failed to parse date for SMS message")
                        return nil
                    }
                    
                    return SmsMessage(
                        id: id,
                        threadId: threadId,
                        address: address,
                        body: body,
                        date: Date(timeIntervalSince1970: Double(dateMs) / 1000.0),
                        type: type,
                        read: read,
                        contactName: messageDict["contactName"] as? String
                    )
                }
                print("[websocket] 📱 Successfully parsed \(messages.count) SMS messages")
                LiveNotificationManager.shared.handleSmsMessages(messages)
                print("[websocket] 📱 SMS messages sent to LiveNotificationManager")
            } else {
                print("[websocket] ❌ Failed to parse messages array from SMS data")
            }

        default:
            // For all other message types, convert back to the old Message format and use existing handler
            let codableValue = CodableValue(message.data)
            let oldMessage = Message(type: message.type, data: codableValue)
            handleMessage(oldMessage)
        }
    }

    // MARK: - Mac Media Control Handler
    private func handleMacMediaControl(action: String) {
        // Get reference to the NowPlayingViewModel from the app
        // We'll access it through the main app or AppState if needed

        switch action {
        case "play":
            NowPlayingCLI.shared.play()
            print("[websocket] Mac media control: play")

        case "pause":
            NowPlayingCLI.shared.pause()
            print("[websocket] Mac media control: pause")

        case "previous":
            NowPlayingCLI.shared.previous()
            print("[websocket] Mac media control: previous")

        case "next":
            NowPlayingCLI.shared.next()
            print("[websocket] Mac media control: next")

        case "stop":
            NowPlayingCLI.shared.stop()
            print("[websocket] Mac media control: stop")
            
        default:
            print("[websocket] Unknown Mac media control action: \(action)")
        }

        // Send response back to Android
        sendMacMediaControlResponse(action: action, success: true)
    }

    private func sendMacMediaControlResponse(action: String, success: Bool) {
        let message = """
        {
            "type": "macMediaControlResponse",
            "data": {
                "action": "\(action)",
                "success": \(success)
            }
        }
        """
        sendToFirstAvailable(message: message)
    }

    private func sendMacInfoResponse() {
        // Gather Mac info with robust fallbacks
        let macName = AppState.shared.myDevice?.name ?? (Host.current().localizedName ?? "My Mac")
        let categoryTypeRaw = DeviceTypeUtil.deviceTypeDescription()
        let exactDeviceNameRaw = DeviceTypeUtil.deviceFullDescription()
        let categoryType = categoryTypeRaw.isEmpty ? "Mac" : categoryTypeRaw
        let exactDeviceName = exactDeviceNameRaw.isEmpty ? categoryType : exactDeviceNameRaw
        let isPlusSubscription = AppState.shared.isPlus

        // Saved app packages
        let savedAppPackages = Array(AppState.shared.androidApps.keys)

        // Base macInfo model (for forward compatibility / decoding symmetry)
        let macInfo = MacInfo(
            name: macName,
            categoryType: categoryType,
            exactDeviceName: exactDeviceName,
            isPlusSubscription: isPlusSubscription,
            savedAppPackages: savedAppPackages
        )

        do {
            let jsonData = try JSONEncoder().encode(macInfo)
            if var jsonDict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                // Enrich with legacy / explicit keys Android may expect
                jsonDict["model"] = exactDeviceName   // Full marketing name
                jsonDict["type"] = categoryType       // Broad category
                jsonDict["isPlus"] = isPlusSubscription // Alias for existing isPlusSubscription

                let messageDict: [String: Any] = [
                    "type": "macInfo",
                    "data": jsonDict
                ]

                let messageJsonData = try JSONSerialization.data(withJSONObject: messageDict, options: [])
                if let messageJsonString = String(data: messageJsonData, encoding: .utf8) {
                    sendToFirstAvailable(message: messageJsonString)
                    print("[websocket] Sent Mac info response: model=\(exactDeviceName), type=\(categoryType)")
                }
            }
        } catch {
            print("[websocket] Error creating Mac info response: \(error)")
        }
    }

    // MARK: - Sending Helpers

    private func broadcast(message: String) {
        print("[websocket] [broadcast] sessions=\(activeSessions.count) msgLen=\(message.count)")
        activeSessions.forEach { $0.writeText(message) }
    }

    private func sendToFirstAvailable(message: String) {
        guard let first = activeSessions.first else {
            let preview = message.prefix(60)
            print("[websocket] [send] No active sessions; dropping message preview=\(preview)")
            return
        }
        if let key = symmetricKey, let encrypted = encryptMessage(message, using: key) {
            print("[websocket] [send] encrypted len=\(encrypted.count)")
            first.writeText(encrypted)
        } else {
            let encryptionState = (symmetricKey != nil) ? "enabled-but-failed" : "disabled"
            print("[websocket] [send] plain len=\(message.count) (encryption=\(encryptionState))")
            first.writeText(message)
        }
    }
    
    // New Sending Helpers per instructions
    
    func sendRemoteConnectRequest(features: [String]) {
        let dataDict: [String: Any] = [
            "features": features
        ]
        let messageDict: [String: Any] = [
            "type": "remoteConnectRequest",
            "data": dataDict
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: messageDict, options: [])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                sendToFirstAvailable(message: jsonString)
            }
        } catch {
            print("[websocket] Error creating remoteConnectRequest message: \(error)")
        }
    }
    
    func sendInputTap(x: Int, y: Int) {
        print("[remote-control] 📍 Sending TAP: x=\(x), y=\(y)")
        let dataDict: [String: Any] = [
            "type": "tap",
            "x": x,
            "y": y
        ]
        sendInputEvent(dataDict)
        print("[remote-control] ✅ TAP event sent to Android")
    }
    
    func sendInputSwipe(x1: Int, y1: Int, x2: Int, y2: Int, durationMs: Int) {
        print("[remote-control] 👆 Sending SWIPE: (\(x1),\(y1)) → (\(x2),\(y2)) duration=\(durationMs)ms")
        let dataDict: [String: Any] = [
            "type": "swipe",
            "x1": x1,
            "y1": y1,
            "x2": x2,
            "y2": y2,
            "durationMs": durationMs
        ]
        sendInputEvent(dataDict)
        print("[remote-control] ✅ SWIPE event sent to Android")
    }
    
    func sendInputKey(keyCode: Int) {
        let dataDict: [String: Any] = [
            "type": "key",
            "keyCode": keyCode
        ]
        sendInputEvent(dataDict)
    }
    
    func sendInputText(_ text: String) {
        let dataDict: [String: Any] = [
            "type": "text",
            "text": text
        ]
        sendInputEvent(dataDict)
    }
    
    private func sendInputEvent(_ data: [String: Any]) {
        let messageDict: [String: Any] = [
            "type": "inputEvent",
            "data": data
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: messageDict, options: [])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print("[remote-control] 📤 Sending inputEvent: \(jsonString)")
                sendToFirstAvailable(message: jsonString)
            }
        } catch {
            print("[remote-control] ❌ Error creating inputEvent message: \(error)")
        }
    }
    
    func sendNavAction(_ action: String) {
        print("[remote-control] 🧭 Sending NAV ACTION: \(action)")
        let messageDict: [String: Any] = [
            "type": "navAction",
            "data": [
                "action": action
            ]
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: messageDict, options: [])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print("[remote-control] 📤 Sending navAction: \(jsonString)")
                sendToFirstAvailable(message: jsonString)
                print("[remote-control] ✅ NAV ACTION sent to Android")
            }
        } catch {
            print("[websocket] Error creating navAction message: \(error)")
        }
    }
    
    func sendLaunchApp(package: String) {
        let messageDict: [String: Any] = [
            "type": "launchApp",
            "data": [
                "package": package
            ]
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: messageDict, options: [])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                sendToFirstAvailable(message: jsonString)
            }
        } catch {
            print("[websocket] Error creating launchApp message: \(error)")
        }
    }
    
    func requestScreenshot(format: String = "jpeg", quality: Double = 0.6, maxWidth: Int? = nil) {
        var dataDict: [String: Any] = [
            "format": format,
            "quality": quality
        ]
        if let maxWidth = maxWidth {
            dataDict["maxWidth"] = maxWidth
        }
        
        let messageDict: [String: Any] = [
            "type": "screenshotRequest",
            "data": dataDict
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: messageDict, options: [])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                sendToFirstAvailable(message: jsonString)
            }
        } catch {
            print("[websocket] Error creating screenshotRequest message: \(error)")
        }
    }

    // MARK: - Mirror Request/Response Helpers

    func sendMirrorRequest(action: String, mode: String? = nil, package: String? = nil, options: [String: Any] = [:]) {
        if action == "start" {
            DispatchQueue.main.async { AppState.shared.isMirrorRequestPending = true }
        }
        // Build a WebSocket URL to our existing /socket endpoint
        func buildMirrorServerURL() -> String {
            // Prefer the current known IP; if nil, try to resolve via adapter selection
            let ip: String = {
                if let ip = self.localIPAddress, !ip.isEmpty { return ip }
                return self.getLocalIPAddress(adapterName: AppState.shared.selectedNetworkAdapterName) ?? "127.0.0.1"
            }()
            let port = Int(self.localPort ?? Defaults.serverPort)
            return "ws://\(ip):\(port)/socket"
        }

        // Start from provided options and add sane defaults
        var combinedOptions: [String: Any] = options

        // Ensure transport is websocket so Android connects back to us via WebSocket
        if combinedOptions["transport"] == nil { combinedOptions["transport"] = "websocket" }

        // Provide sensible defaults if missing
        if combinedOptions["fps"] == nil { combinedOptions["fps"] = 30 }
        if combinedOptions["maxWidth"] == nil { combinedOptions["maxWidth"] = 1280 }

        // Prefer bitrateKbps if caller set a general bitrate
        if combinedOptions["bitrateKbps"] == nil, let bitrate = combinedOptions["bitrate"] as? Int, bitrate > 0 {
            combinedOptions["bitrateKbps"] = bitrate
        }

        // Provide the server URL Android should connect back to
        combinedOptions["serverUrl"] = buildMirrorServerURL()

        var dataDict: [String: Any] = ["action": action]
        if let mode = mode, !mode.isEmpty { dataDict["mode"] = mode }
        if let package = package, !package.isEmpty { dataDict["package"] = package }
        if !combinedOptions.isEmpty { dataDict["options"] = combinedOptions }

        let messageDict: [String: Any] = [
            "type": "mirrorRequest",
            "data": dataDict
        ]

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: messageDict, options: [])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                sendToFirstAvailable(message: jsonString)
            }
        } catch {
            print("[websocket] Error creating mirrorRequest message: \(error)")
        }
    }

    func sendMirrorResponse(_ payload: [String: Any]) {
        let messageDict: [String: Any] = [
            "type": "mirrorResponse",
            "data": payload
        ]

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: messageDict, options: [])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                sendToFirstAvailable(message: jsonString)
            }
        } catch {
            print("[websocket] Error creating mirrorResponse message: \(error)")
        }
    }
    
    func sendMirrorAck(action: String, ok: Bool, message: String? = nil) {
        var data: [String: Any] = [
            "action": action,
            "ok": ok
        ]
        if let message { data["message"] = message }
        let dict: [String: Any] = [
            "type": "mirrorResponse",
            "data": data
        ]
        if let json = try? JSONSerialization.data(withJSONObject: dict),
           let str = String(data: json, encoding: .utf8) {
            sendToFirstAvailable(message: str)
        }
    }

    // MARK: - Mirror UI Presentation
    private func presentMirrorWindowIfNeeded() {
        #if os(macOS)
        // If a window already exists and is visible, bring it to front
        if let win = mirrorWindow, win.isVisible {
            win.level = .floating
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Create a new window hosting the mirror view
        // Standard Android phone aspect ratio: 9:19.5 (e.g., 1080x2340)
        let aspectRatio: CGFloat = 19.5 / 9.0
        let windowWidth: CGFloat = 400
        let windowHeight: CGFloat = windowWidth * aspectRatio
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "AirSync Mirror - Remote Control"
        window.aspectRatio = NSSize(width: 9, height: 19.5)
        window.minSize = NSSize(width: 300, height: 300 * aspectRatio)
        window.maxSize = NSSize(width: 600, height: 600 * aspectRatio)
        
        // Set window level to float above other windows (like CSS z-index)
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        #if canImport(SwiftUI)
        // Use interactive mirror view with remote control capabilities
        let root = InteractiveMirrorView()
        window.contentView = NSHostingView(rootView: root)
        #else
        // Fallback if SwiftUI is not available
        window.contentView = NSView()
        #endif

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.mirrorWindow = window
        window.delegate = MirrorWindowDelegate.shared(self)
        #endif
    }

    // MARK: - Notification Control

    func dismissNotification(id: String) {
        let message = """
        {
            "type": "dismissNotification",
            "data": {
                "id": "\(id)"
            }
        }
        """
        sendToFirstAvailable(message: message)
    }

    func sendNotificationAction(id: String, name: String, text: String? = nil) {
        var data: [String: Any] = ["id": id, "name": name]
        if let t = text, !t.isEmpty { data["text"] = t }
        if let jsonData = try? JSONSerialization.data(withJSONObject: ["type": "notificationAction", "data": data], options: []),
           let json = String(data: jsonData, encoding: .utf8) {
            sendToFirstAvailable(message: json)
        }
    }

    func sendCallAction(eventId: String, action: String) {
        // Send key events via ADB to control calls
        // KeyCode 5 = KEYCODE_CALL (Accept/Answer call)
        // KeyCode 6 = KEYCODE_ENDCALL (End call)
        let keyCode: String
        switch action.lowercased() {
        case "accept":
            keyCode = "5"   // KEYCODE_CALL
        case "decline", "end":
            keyCode = "6"   // KEYCODE_ENDCALL
        default:
            keyCode = "6"
        }
        
        // Execute: adb shell input keyevent <keyCode>
        DispatchQueue.global(qos: .userInitiated).async {
            guard let adbPath = ADBConnector.findExecutable(named: "adb", fallbackPaths: ADBConnector.possibleADBPaths) else {
                print("[websocket] ADB not found for call action")
                return
            }
            
            // Use the actual connected ADB IP address (discovered IP), not the device reported IP
            let adbIP = AppState.shared.adbConnectedIP.isEmpty ? AppState.shared.device?.ipAddress ?? "" : AppState.shared.adbConnectedIP
            if !adbIP.isEmpty {
                let adbPort = AppState.shared.adbPort
                let fullAddress = "\(adbIP):\(adbPort)"
                let process = Process()
                process.executableURL = URL(fileURLWithPath: adbPath)
                process.arguments = ["-s", fullAddress, "shell", "input", "keyevent", keyCode]
                
                print("[websocket] Sending call action: \(action) (keyCode: \(keyCode)) to device \(fullAddress) for eventId: \(eventId)")
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    print("[websocket] Call action sent: keyevent \(keyCode) for event: \(eventId) on \(fullAddress)")
                } catch {
                    print("[websocket] Failed to send call action: \(error.localizedDescription)")
                }
            } else {
                print("[websocket] ERROR: No device address found for call action (adbConnectedIP: '\(AppState.shared.adbConnectedIP)', device IP: \(AppState.shared.device?.ipAddress ?? "nil"))")
            }
        }
    }

    // MARK: - Media Controls

    func togglePlayPause() {
        sendMediaAction("playPause")
    }

    func skipNext() {
        sendMediaAction("next")
    }

    func skipPrevious() {
        sendMediaAction("previous")
    }

    func stopMedia() {
        sendMediaAction("stop")
    }

    // Like controls
    func toggleLike() {
        sendMediaAction("toggleLike")
    }

    func like() {
        sendMediaAction("like")
    }

    func unlike() {
        sendMediaAction("unlike")
    }

    private func sendMediaAction(_ action: String) {
        let message = """
        {
            "type": "macMediaControl",
            "data": {
                "action": "\(action)"
            }
        }
        """
        sendToFirstAvailable(message: message)
        print("[websocket] 🎵 Sent macMediaControl action: \(action)")
    }

    // MARK: - Volume Controls

    func volumeUp() {
        sendVolumeAction("volumeUp")
    }

    func volumeDown() {
        sendVolumeAction("volumeDown")
    }

    func toggleMute() {
        sendVolumeAction("mute")
    }

    func setVolume(_ volume: Int) {
        let message = """
        {
            "type": "volumeControl",
            "data": {
                "action": "setVolume",
                "volume": \(volume)
            }
        }
        """
        sendToFirstAvailable(message: message)
    }

    private func sendVolumeAction(_ action: String) {
        let message = """
        {
            "type": "volumeControl",
            "data": {
                "action": "\(action)"
            }
        }
        """
        sendToFirstAvailable(message: message)
    }

    func sendClipboardUpdate(_ message: String) {
        sendToFirstAvailable(message: message)
    }

    // MARK: - SMS/Messaging
    
    func requestSmsThreads(limit: Int = 50) {
        let message = """
        {
            "type": "requestSmsThreads",
            "data": {
                "limit": \(limit)
            }
        }
        """
        sendToFirstAvailable(message: message)
    }
    
    func requestSmsMessages(threadId: String, limit: Int = 100) {
        let message = """
        {
            "type": "requestSmsMessages",
            "data": {
                "threadId": "\(threadId)",
                "limit": \(limit)
            }
        }
        """
        sendToFirstAvailable(message: message)
    }
    
    func sendSms(to address: String, message: String) {
        let escapedMessage = message.replacingOccurrences(of: "\"", with: "\\\"")
        let msg = """
        {
            "type": "sendSms",
            "data": {
                "address": "\(address)",
                "message": "\(escapedMessage)"
            }
        }
        """
        sendToFirstAvailable(message: msg)
    }
    
    func markSmsAsRead(messageId: String) {
        let message = """
        {
            "type": "markSmsRead",
            "data": {
                "messageId": "\(messageId)"
            }
        }
        """
        sendToFirstAvailable(message: message)
    }
    
    // MARK: - Call Logs
    
    func requestCallLogs(limit: Int = 100, since: Date? = nil) {
        var dataDict: [String: Any] = ["limit": limit]
        if let since = since {
            dataDict["since"] = Int(since.timeIntervalSince1970 * 1000)
        }
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: ["type": "requestCallLogs", "data": dataDict], options: []),
           let json = String(data: jsonData, encoding: .utf8) {
            sendToFirstAvailable(message: json)
        }
    }
    
    func markCallLogAsRead(callId: String) {
        let message = """
        {
            "type": "markCallLogRead",
            "data": {
                "callId": "\(callId)"
            }
        }
        """
        sendToFirstAvailable(message: message)
    }
    
    // MARK: - Call Actions
    
    func sendCallAction(_ action: String) {
        let message = """
        {
            "type": "callAction",
            "data": {
                "action": "\(action)"
            }
        }
        """
        sendToFirstAvailable(message: message)
    }
    
    // MARK: - Health Data
    
    func requestHealthSummary(for date: Date? = nil) {
        let targetDate = date ?? Date()
        let dateMs = Int64(targetDate.timeIntervalSince1970 * 1000)
        
        print("[websocket] 📅 Requesting health summary for date: \(targetDate), timestamp: \(dateMs)")
        
        let message = """
        {
            "type": "requestHealthSummary",
            "data": {
                "date": \(dateMs)
            }
        }
        """
        sendToFirstAvailable(message: message)
    }
    
    func requestHealthData(hours: Int = 24, for date: Date? = nil) {
        let targetDate = date ?? Date()
        let dateMs = Int64(targetDate.timeIntervalSince1970 * 1000)
        
        let message = """
        {
            "type": "requestHealthData",
            "data": {
                "hours": \(hours),
                "date": \(dateMs)
            }
        }
        """
        sendToFirstAvailable(message: message)
    }

    // MARK: - Device Status (Mac -> Android)
    func sendDeviceStatus(batteryLevel: Int, isCharging: Bool, isPaired: Bool, musicInfo: NowPlayingInfo?, albumArtBase64: String? = nil) {
        var statusDict: [String: Any] = [
            "battery": [
                "level": batteryLevel, // -1 for non-MacBooks, 0-100 for MacBooks
                "isCharging": isCharging
            ],
            "isPaired": isPaired
        ]

        // Only include music section if we have valid playback info
        if let musicInfo {
            let musicDict: [String: Any] = [
                "isPlaying": musicInfo.isPlaying ?? false,
                "title": musicInfo.title ?? "",
                "artist": musicInfo.artist ?? "",
                "volume": 50, // Hardcoded for now - will be replaced later
                "isMuted": false, // Hardcoded for now - will be replaced later
                "albumArt": albumArtBase64 ?? "",
                "likeStatus": "none" // Hardcoded for now - will be replaced later
            ]
            statusDict["music"] = musicDict
        }

        let messageDict: [String: Any] = [
            "type": "status",
            "data": statusDict
        ]

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: messageDict, options: [])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                sendToFirstAvailable(message: jsonString)
            }
        } catch {
            print("[websocket] Error creating device status message: \(error)")
        }
    }

    // MARK: - File transfer (Mac -> Android)
    func sendFile(url: URL, chunkSize: Int = 64 * 1024) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard let data = try? Data(contentsOf: url) else { return }
        // Compute checksum over the exact bytes that will be sent
        let digest = SHA256.hash(data: data)
        let checksum = digest.compactMap { String(format: "%02x", $0) }.joined()
        print("[websocket] (file-transfer) sendFile path=\(url.path) size=\(data.count) chunkSize=\(chunkSize)")

        let transferId = UUID().uuidString
        let fileName = url.lastPathComponent
        let totalSize = data.count
        let mime = mimeType(for: url) ?? "application/octet-stream"

        // Track in AppState
        AppState.shared.startOutgoingTransfer(id: transferId, name: fileName, size: totalSize, mime: mime, chunkSize: chunkSize)

        // Send init message
        let initMessage = FileTransferProtocol.buildInit(id: transferId, name: fileName, size: totalSize, mime: mime, checksum: checksum)
        sendToFirstAvailable(message: initMessage)

        // Send chunks using a simple sliding window to allow multiple in-flight chunks
        let windowSize = 8
        let totalChunks = (totalSize + chunkSize - 1) / chunkSize
        outgoingAcks[transferId] = []
        print("[websocket] (file-transfer) id=\(transferId) name=\(fileName) totalChunks=\(totalChunks) checksumPrefix=\(checksum.prefix(8))")

        // Keep a buffer of sent chunks for potential retransmit: index -> (payloadBase64, attempts, lastSent)
        var sentBuffer: [Int: (payload: String, attempts: Int, lastSent: Date)] = [:]

        var nextIndexToSend = 0
        let startTime = Date()

        func sendChunkAt(_ idx: Int) {
            let start = idx * chunkSize
            let end = min(start + chunkSize, totalSize)
            let chunk = data.subdata(in: start..<end)
            let base64 = chunk.base64EncodedString(options: [])
            let chunkMessage = FileTransferProtocol.buildChunk(id: transferId, index: idx, base64Chunk: base64)
            sendToFirstAvailable(message: chunkMessage)
            sentBuffer[idx] = (payload: base64, attempts: 1, lastSent: Date())
            print("[websocket] (file-transfer) -> send chunk id=\(transferId) index=\(idx) size=\(chunk.count)")
        }

        // Prime the window
        while nextIndexToSend < totalChunks && nextIndexToSend < windowSize {
            sendChunkAt(nextIndexToSend)
            nextIndexToSend += 1
        }

        // Loop until all chunks are acked
        while true {
            let acked = outgoingAcks[transferId] ?? []

            // compute baseIndex = lowest unacked index (first missing starting from 0)
            var baseIndex = 0
            while acked.contains(baseIndex) {
                // free memory for acknowledged chunks
                sentBuffer.removeValue(forKey: baseIndex)
                baseIndex += 1
            }

            // Update progress in AppState
            let bytesAcked = min(acked.count * chunkSize, totalSize)
            AppState.shared.updateOutgoingProgress(id: transferId, bytesTransferred: bytesAcked)

            // completion when baseIndex reached totalChunks
            if baseIndex >= totalChunks {
                break
            }

            // send new chunks while window has space
            while nextIndexToSend < totalChunks && (nextIndexToSend - baseIndex) < windowSize {
                sendChunkAt(nextIndexToSend)
                nextIndexToSend += 1
            }

            // Retransmit chunks that haven't been acked and exceeded timeout
            let now = Date()
            for (idx, entry) in sentBuffer {
                if acked.contains(idx) { continue }
                let elapsedMs = now.timeIntervalSince(entry.lastSent) * 1000.0
                if elapsedMs > Double(ackWaitMs) {
                    if entry.attempts >= maxChunkRetries {
                        print("[websocket] (file-transfer) Failed to get ack for chunk \(idx) after \(maxChunkRetries) attempts")
                        outgoingAcks.removeValue(forKey: transferId)
                        return
                    }
                    // retransmit
                    let start = idx * chunkSize
                    let end = min(start + chunkSize, totalSize)
                    let chunk = data.subdata(in: start..<end)
                    let base64 = chunk.base64EncodedString(options: [])
                    let chunkMessage = FileTransferProtocol.buildChunk(id: transferId, index: idx, base64Chunk: base64)
                    print("[websocket] (file-transfer) retransmit id=\(transferId) index=\(idx) attempt=\(entry.attempts + 1)")
                    sendToFirstAvailable(message: chunkMessage)
                    sentBuffer[idx] = (payload: base64, attempts: entry.attempts + 1, lastSent: Date())
                }
            }

            // brief sleep to avoid busy-looping
            usleep(50_000) // 50ms
        }

    // Ensure progress shows 100%
    AppState.shared.updateOutgoingProgress(id: transferId, bytesTransferred: totalSize)
    let elapsed = Date().timeIntervalSince(startTime)
        print("[websocket] (file-transfer) Completed sending \(totalSize) bytes in \(elapsed) s")

        // Send complete
    let completeMessage = FileTransferProtocol.buildComplete(id: transferId, name: fileName, size: totalSize, checksum: checksum)
        sendToFirstAvailable(message: completeMessage)
    }

    func toggleNotification(for package: String, to state: Bool) {
        guard var app = AppState.shared.androidApps[package] else { return }

        app.listening = state
        AppState.shared.androidApps[package] = app
        AppState.shared.saveAppsToDisk()

        // WebSocket call
        let message = """
        {
            "type": "toggleAppNotif",
            "data": {
                "package": "\(package)",
                "state": "\(state)"
            }
        }
        """
        sendToFirstAvailable(message: message)
    }

    func loadOrGenerateSymmetricKey() {
        let defaults = UserDefaults.standard

        if let savedKey = defaults.string(forKey: "encryptionKey"),
           let keyData = Data(base64Encoded: savedKey) {
            symmetricKey = SymmetricKey(data: keyData)
            print("[websocket] (auth) Loaded existing symmetric key")
        } else {
            let base64Key = generateSymmetricKey()
            defaults.set(base64Key, forKey: "encryptionKey")

            if let keyData = Data(base64Encoded: base64Key) {
                symmetricKey = SymmetricKey(data: keyData)
                print("[websocket] (auth) Generated and stored new symmetric key")
            } else {
                print("[websocket] (auth) Failed to generate symmetric key")
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
            print("[websocket] (auth) Encryption key set")
        }
    }

    // Helper: determine mime type for a file URL
    func mimeType(for url: URL) -> String? {
        let ext = url.pathExtension
        if ext.isEmpty { return nil }

        if #available(macOS 11.0, *) {
            if let ut = UTType(filenameExtension: ext) {
                return ut.preferredMIMEType
            }
        } else {
#if canImport(MobileCoreServices)
            // Fallback to MobileCoreServices APIs
            if let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, ext as CFString, nil)?.takeRetainedValue() {
                if let mime = UTTypeCopyPreferredTagWithClass(uti, kUTTagClassMIMEType)?.takeRetainedValue() as String? {
                    return mime
                }
            }
#else
            // No fallback available on this SDK
#endif
        }
        return nil
    }
    func startNetworkMonitoring() {
        networkMonitorTimer = Timer.scheduledTimer(withTimeInterval: networkCheckInterval, repeats: true) { [weak self] _ in
            self?.checkNetworkChange()
        }
        networkMonitorTimer?.tolerance = 1.0
        networkMonitorTimer?.fire()
    }

    func stopNetworkMonitoring() {
        networkMonitorTimer?.invalidate()
        networkMonitorTimer = nil
        lastKnownAdapters = []
    }

    private func checkNetworkChange() {
        let adapters = getAvailableNetworkAdapters()
        let chosenIP = getLocalIPAddress(adapterName: AppState.shared.selectedNetworkAdapterName)

        // Compare by addresses to detect any change
        let adapterAddresses = adapters.map { $0.address }
        let lastAddresses = lastKnownAdapters.map { $0.address }

        if adapterAddresses != lastAddresses {
            lastKnownAdapters = adapters

            // Revalidate the current network adapter selection
            AppState.shared.revalidateNetworkAdapter()

            for adapter in adapters {
                let activeMark = (adapter.address == chosenIP) ? " [ACTIVE]" : ""
                print("[websocket] (network) \(adapter.name) -> \(adapter.address)\(activeMark)")
            }

            // Restart if the IP changed
            if let lastIP = lastKnownIP, lastIP != chosenIP {
                print("[websocket] (network) IP changed from \(lastIP) to \(chosenIP ?? "N/A"), restarting WebSocket in 5 seconds")
                lastKnownIP = chosenIP
                AppState.shared.shouldRefreshQR = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    self.stop()
                    self.start(port: Defaults.serverPort)
                }
            } else if lastKnownIP == nil {
                // First run
                lastKnownIP = chosenIP
            }
        } else {
            // [quiet] No change is the common case; keep log line for debugging
            // print("[websocket] (network) No change detected")
        }
    }
    
    // MARK: - Quick Connect Delegate
    
    /// Delegates wake-up functionality to QuickConnectManager
    func wakeUpLastConnectedDevice() {
        QuickConnectManager.shared.wakeUpLastConnectedDevice()
    }

    /// Starts mirror and presents UI in one step.
    /// - Parameters:
    ///   - mode: "device", "desktop", or "app" (optional)
    ///   - package: Package name when mode == "app" (optional)
    ///   - options: Additional options to merge (optional)
    func startMirrorAndPresentUI(mode: String? = nil, package: String? = nil, options: [String: Any] = [:]) {
        print("[mirror] 🎬 Starting mirror request...")
        
        // Mark mirror request as pending to disable the button
        DispatchQueue.main.async {
            AppState.shared.isMirrorRequestPending = true
            AppState.shared.mirrorError = nil
        }
        
        // Set timeout for mirror request (10 seconds)
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            if AppState.shared.isMirrorRequestPending && !AppState.shared.isMirroring {
                print("[mirror] ⏱️ Mirror request timed out - no response from Android")
                AppState.shared.isMirrorRequestPending = false
                AppState.shared.mirrorError = "Mirror request timed out. Please try again."
            }
        }

        // 2) Send the mirrorRequest to Android with user-configured quality settings
        var mergedOptions = options
        if mergedOptions["transport"] == nil { mergedOptions["transport"] = "websocket" }
        if mergedOptions["fps"] == nil { mergedOptions["fps"] = AppState.shared.mirrorFPS }
        if mergedOptions["maxWidth"] == nil { mergedOptions["maxWidth"] = AppState.shared.mirrorMaxWidth }
        if mergedOptions["quality"] == nil { mergedOptions["quality"] = AppState.shared.mirrorQuality }
        if mergedOptions["bitrate"] == nil { mergedOptions["bitrate"] = AppState.shared.mirrorBitrate }

        print("[mirror] 📤 Sending mirror request with options: fps=\(mergedOptions["fps"] ?? 0), maxWidth=\(mergedOptions["maxWidth"] ?? 0)")
        self.sendMirrorRequest(action: "start", mode: mode, package: package, options: mergedOptions)
    }
    
    /// Request app-specific mirroring via WebSocket
    func requestAppMirror(packageName: String) {
        print("[mirror] 📱 Requesting app mirror for: \(packageName)")
        startMirrorAndPresentUI(mode: "app", package: packageName)
    }
    
    func stopMirroring() {
        // Send stop request to Android and update state
        self.sendMirrorRequest(action: "stop")
        DispatchQueue.main.async {
            AppState.shared.isMirrorRequestPending = true
        }
        
        // Reset pending state after timeout in case Android doesn't respond
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if AppState.shared.isMirrorRequestPending && !AppState.shared.isMirroring {
                print("[mirror] ⏱️ Stop request timed out - resetting pending state")
                AppState.shared.isMirrorRequestPending = false
            }
        }
    }

}


#if os(macOS)
private class MirrorWindowDelegate: NSObject, NSWindowDelegate {
    private weak var server: WebSocketServer?
    private static var _shared: MirrorWindowDelegate?
    static func shared(_ server: WebSocketServer) -> MirrorWindowDelegate {
        if let s = _shared { s.server = server; return s }
        let d = MirrorWindowDelegate()
        d.server = server
        _shared = d
        return d
    }
    func windowWillClose(_ notification: Foundation.Notification) {
        server?.stopMirroring()
    }
}
#endif

