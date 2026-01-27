//
//  WebSocketServer+Handlers.swift
//  airsync-mac
//

import Foundation
import Swifter
import CryptoKit
import UserNotifications
import CoreGraphics

extension WebSocketServer {
    
    /// Central router for incoming WebSocket messages.
    /// Decodes message type and dispatches to specific specialized handlers.
    func handleMessage(_ message: Message, session: WebSocketSession) {
        let sessionId = ObjectIdentifier(session)
        
        if message.type != .device && sessionId != primarySessionID {
            print("[websocket] Ignoring message of type \(message.type) from non-primary session")
            return
        }

        switch message.type {
        case .device:
            handleDeviceHandshake(message, session: session)
        case .notification:
            handleNotification(message)
        case .callEvent:
            handleCallEvent(message)
        case .notificationActionResponse:
            handleNotificationActionResponse(message)
        case .notificationAction:
            print("[websocket] Warning: received 'notificationAction' from remote (ignored).")
        case .notificationUpdate:
            handleNotificationUpdate(message)
        case .status:
            handleStatusUpdate(message)
        case .dismissalResponse:
            handleDismissalResponse(message)
        case .mediaControlResponse:
            handleMediaControlResponse(message)
        case .appIcons:
            handleAppIcons(message)
        case .clipboardUpdate:
            handleClipboardUpdate(message)
        case .fileTransferInit:
            handleFileTransferInit(message)
        case .fileChunk:
            handleFileChunk(message, session: session)
        case .fileChunkAck:
            handleFileChunkAck(message)
        case .fileTransferComplete:
            handleFileTransferComplete(message)
        case .transferVerified:
            handleTransferVerified(message)
        case .fileTransferCancel:
            handleFileTransferCancel(message)
        case .macMediaControl:
            handleMacMediaControlRequest(message)
        case .callControlResponse:
            handleCallControlResponse(message)
        case .remoteControl:
            handleRemoteControl(message)
        case .browseData:
            handleBrowseData(message)
        case .volumeControl, .macVolume, .toggleAppNotif, .browseLs, .wakeUpRequest, .macMediaControlResponse, .macInfo, .callControl:
            // Outgoing or unexpected messages
            break
        }
    }

    // MARK: - Private Handlers

    /// Processes initial device handshake.
    /// Handles device registration, wallpaper syncing, and IP conflict resolution for local network priority.
    private func handleDeviceHandshake(_ message: Message, session: WebSocketSession) {
        let sessionId = ObjectIdentifier(session)
        self.lock.lock()
        
        let incomingTargetIp = (message.data.value as? [String: Any])?["targetIpAddress"] as? String ?? ""
        let isIncomingLocal = ipIsPrivatePreferred(incomingTargetIp)
        
        if let oldPrimary = primarySessionID, oldPrimary != sessionId {
            if isIncomingLocal {
                print("[websocket] New local session taking over as primary. Closing old session.")
                activeSessions.first(where: { ObjectIdentifier($0) == oldPrimary })?.writeBinary([])
                self.primarySessionID = sessionId
            } else {
                print("[websocket] Ignoring non-local session takeover attempt (\(incomingTargetIp)) to maintain stability.")
                self.lock.unlock()
                return
            }
        } else {
            self.primarySessionID = sessionId
        }
        self.lock.unlock()
        
        if let dict = message.data.value as? [String: Any],
           let name = dict["name"] as? String,
           let ip = dict["ipAddress"] as? String,
           let port = dict["port"] as? Int {

            if let targetIp = dict["targetIpAddress"] as? String {
                AppState.shared.activeMacIp = targetIp.trimmingCharacters(in: .whitespaces)
            }

            let version = dict["version"] as? String ?? "2.0.0"
            let adbPorts = dict["adbPorts"] as? [String] ?? []

            AppState.shared.device = Device(
                name: name,
                ipAddress: ip,
                port: port,
                version: version,
                adbPorts: adbPorts
            )

            if let base64 = dict["wallpaper"] as? String {
                AppState.shared.currentDeviceWallpaperBase64 = base64
            }

            if (!AppState.shared.adbConnected && AppState.shared.adbEnabled && AppState.shared.isPlus) {
                ADBConnector.connectToADB(ip: ip)
            }

            if UserDefaults.standard.hasPairedDeviceOnce == false {
                UserDefaults.standard.hasPairedDeviceOnce = true
            }
            
            sendMacInfoResponse()
        }
    }

    private func handleNotification(_ message: Message) {
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
            DispatchQueue.main.async {
                AppState.shared.addNotification(notif)
            }
        }
    }

    private func handleCallEvent(_ message: Message) {
        if let dict = message.data.value as? [String: Any],
           let eventId = dict["eventId"] as? String,
           let number = dict["number"] as? String,
           let normalizedNumber = dict["normalizedNumber"] as? String,
           let directionStr = dict["direction"] as? String,
           let direction = CallDirection(rawValue: directionStr),
           let stateStr = dict["state"] as? String,
           let state = CallState(rawValue: stateStr) {
            
            let contactName = (dict["contactName"] as? String) ?? normalizedNumber
            
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
            DispatchQueue.main.async {
                AppState.shared.updateCallEvent(callEvent)
            }
        }
    }

    private func handleStatusUpdate(_ message: Message) {
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
    }

    private func handleAppIcons(_ message: Message) {
        if let dict = message.data.value as? [String: [String: Any]] {
            DispatchQueue.global(qos: .background).async {
                let incomingPackages = Set(dict.keys)
                let existingPackages = Set(AppState.shared.androidApps.keys)

                for (package, details) in dict {
                    guard let name = details["name"] as? String,
                          let iconBase64 = details["icon"] as? String,
                          let systemApp = details["systemApp"] as? Bool,
                          let listening = details["listening"] as? Bool else { continue }

                    var cleaned = iconBase64
                    if let range = cleaned.range(of: "base64,") { cleaned = String(cleaned[range.upperBound...]) }

                    var iconPath: String? = nil
                    if let data = Data(base64Encoded: cleaned), !cleaned.isEmpty {
                        let fileURL = appIconsDirectory().appendingPathComponent("\(package).png")
                        do {
                            try data.write(to: fileURL, options: .atomic)
                            iconPath = fileURL.path
                        } catch {
                            print("[websocket] Failed to write icon for \(package): \(error)")
                        }
                    }

                    DispatchQueue.main.async {
                        if var existingApp = AppState.shared.androidApps[package] {
                            existingApp.listening = listening
                            if let newIconPath = iconPath {
                                existingApp.iconUrl = newIconPath
                            }
                            AppState.shared.androidApps[package] = existingApp
                        } else {
                            let app = AndroidApp(
                                packageName: package,
                                name: name,
                                iconUrl: iconPath,
                                listening: listening,
                                systemApp: systemApp
                            )
                            AppState.shared.androidApps[package] = app
                        }
                    }
                }

                let toRemove = existingPackages.subtracting(incomingPackages)
                if !toRemove.isEmpty {
                    DispatchQueue.main.async {
                        for pkg in toRemove {
                            if let iconPath = AppState.shared.androidApps[pkg]?.iconUrl {
                                try? FileManager.default.removeItem(atPath: iconPath)
                            }
                            AppState.shared.androidApps.removeValue(forKey: pkg)
                        }
                    }
                }

                DispatchQueue.main.async {
                    AppState.shared.saveAppsToDisk()
                }
            }
        }
    }

    private func handleFileTransferInit(_ message: Message) {
        if let dict = message.data.value as? [String: Any],
           let id = dict["id"] as? String,
           let name = dict["name"] as? String,
           let size = dict["size"] as? Int,
           let mime = dict["mime"] as? String {
            let chunkSize = dict["chunkSize"] as? Int ?? 64 * 1024
            let checksum = dict["checksum"] as? String

            let tempDir = FileManager.default.temporaryDirectory
            let safeName = name.replacingOccurrences(of: "/", with: "_")
            let tempFile = tempDir.appendingPathComponent("incoming_\(id)_\(safeName)")
            FileManager.default.createFile(atPath: tempFile.path, contents: nil, attributes: nil)
            let handle = try? FileHandle(forWritingTo: tempFile)

            let io = IncomingFileIO(tempUrl: tempFile, fileHandle: handle, chunkSize: chunkSize)
            self.lock.lock()
            incomingFiles[id] = io
            if let checksum = checksum {
                incomingFilesChecksum[id] = checksum
            }
            self.lock.unlock()
            
            DispatchQueue.main.async {
                AppState.shared.startIncomingTransfer(id: id, name: name, size: size, mime: mime)
            }
        }
    }

    /// Handles incoming file chunks.
    /// Writes data to the temporary file handle on a serial queue to ensure thread safety.
    private func handleFileChunk(_ message: Message, session: WebSocketSession) {
        if let dict = message.data.value as? [String: Any],
           let id = dict["id"] as? String,
           let index = dict["index"] as? Int,
           let chunkBase64 = dict["chunk"] as? String {
            
            self.lock.lock()
            let io = incomingFiles[id]
            self.lock.unlock()

            if let io = io, let data = Data(base64Encoded: chunkBase64, options: .ignoreUnknownCharacters) {
                fileQueue.async {
                    let offset = UInt64(index * io.chunkSize)
                    if let fh = io.fileHandle {
                        do {
                            try fh.seek(toOffset: offset)
                            try fh.write(contentsOf: data)
                        } catch {
                            print("[websocket] (file-transfer) Write failed for chunk \(index): \(error)")
                        }
                    }
                }
                DispatchQueue.main.async {
                    let prev = AppState.shared.transfers[id]?.bytesTransferred ?? 0
                    let newBytes = prev + data.count
                    AppState.shared.updateIncomingProgress(id: id, receivedBytes: newBytes)
                }
            }
            
            let ackMsg = FileTransferProtocol.buildChunkAck(id: id, index: index)
            self.sendToFirstAvailable(message: ackMsg)
        }
    }

    private func handleFileTransferComplete(_ message: Message) {
        if let dict = message.data.value as? [String: Any],
           let id = dict["id"] as? String {
            
            self.lock.lock()
            let state = incomingFiles[id]
            self.lock.unlock()

            if let state = state {
                fileQueue.async {
                    state.fileHandle?.closeFile()
                    
                    var totalBytes: UInt64 = 0
                    do {
                        let attr = try FileManager.default.attributesOfItem(atPath: state.tempUrl.path)
                        totalBytes = attr[.size] as? UInt64 ?? 0
                    } catch {
                        print("[websocket] (file-transfer) Failed to get size for validation: \(error)")
                    }
                    
                    var expectedSize: Int = 0
                    var resolvedName = state.tempUrl.lastPathComponent
                    DispatchQueue.main.sync {
                        if let t = AppState.shared.transfers[id] {
                            expectedSize = t.size
                            resolvedName = t.name
                        }
                    }
                    
                    if Int(totalBytes) != expectedSize {
                        DispatchQueue.main.async {
                            AppState.shared.failTransfer(id: id, reason: "Size mismatch: \(totalBytes)/\(expectedSize)")
                        }
                        try? FileManager.default.removeItem(at: state.tempUrl)
                        self.lock.lock()
                        self.incomingFiles.removeValue(forKey: id)
                        self.incomingFilesChecksum.removeValue(forKey: id)
                        self.lock.unlock()
                        return 
                    }
                    
                    self.lock.lock()
                    let expectedChecksum = self.incomingFilesChecksum[id]
                    self.lock.unlock()

                    if let expected = expectedChecksum {
                        if let fileData = try? Data(contentsOf: state.tempUrl) {
                            let computed = SHA256.hash(data: fileData).compactMap { String(format: "%02x", $0) }.joined()
                            if computed != expected {
                                print("[websocket] (file-transfer) Checksum mismatch for incoming file id=\(id)")
                            }
                        }
                        self.lock.lock()
                        self.incomingFilesChecksum.removeValue(forKey: id)
                        self.lock.unlock()
                    }

                    if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
                        do {
                            let finalDest = downloads.appendingPathComponent(resolvedName)
                            if FileManager.default.fileExists(atPath: finalDest.path) {
                                try FileManager.default.removeItem(at: finalDest)
                            }
                            try FileManager.default.moveItem(at: state.tempUrl, to: finalDest)

                            DispatchQueue.main.async {
                                AppState.shared.completeIncoming(id: id, verified: nil)
                                AppState.shared.postNativeNotification(
                                    id: "incoming_file_\(id)",
                                    appName: "AirSync",
                                    title: "Received: \(resolvedName)",
                                    body: "Saved to Downloads"
                                )
                            }
                        } catch {
                            print("[websocket] (file-transfer) Failed to move incoming file: \(error)")
                        }
                    }
                    
                    self.lock.lock()
                    self.incomingFiles.removeValue(forKey: id)
                    self.lock.unlock()
                }
            }
        }
    }

    private func handleBrowseData(_ message: Message) {
        if let dict = message.data.value as? [String: Any],
           let path = dict["path"] as? String,
           let itemsArray = dict["items"] as? [[String: Any]] {
            
            var items: [FileBrowserItem] = []
            for itemDict in itemsArray {
                let name = itemDict["name"] as? String ?? ""
                let isDir = itemDict["isDir"] as? Bool ?? false
                let size = (itemDict["size"] as? Int64) ?? Int64(itemDict["size"] as? Int ?? 0)
                let timeValue = (itemDict["time"] as? Int64) ?? Int64(itemDict["time"] as? Int ?? 0)
                
                if !name.isEmpty {
                    items.append(FileBrowserItem(name: name, isDir: isDir, size: size, time: timeValue))
                }
            }
            
            DispatchQueue.main.async {
                AppState.shared.browsePath = path
                AppState.shared.browseItems = items
                AppState.shared.browseError = nil
                AppState.shared.isBrowsingLoading = false
            }
        } else if let error = (message.data.value as? [String: Any])?["error"] as? String {
            DispatchQueue.main.async {
                AppState.shared.browseError = error
                AppState.shared.isBrowsingLoading = false
            }
        }
    }

    private func handleRemoteControl(_ message: Message) {
        if let dict = message.data.value as? [String: Any],
           let action = dict["action"] as? String {
            
            switch action {
            case "keypress":
                if let code = dict["keycode"] as? Int {
                    let modifiers = dict["modifiers"] as? [String] ?? []
                    MacRemoteManager.shared.simulateKeyCode(code, modifiers: modifiers)
                }
            case "type":
                if let text = dict["text"] as? String {
                    let modifiers = dict["modifiers"] as? [String] ?? []
                    MacRemoteManager.shared.simulateText(text, modifiers: modifiers)
                }
            case "arrow_up": MacRemoteManager.shared.simulateKey(.upArrow)
            case "arrow_down": MacRemoteManager.shared.simulateKey(.downArrow)
            case "arrow_left": MacRemoteManager.shared.simulateKey(.leftArrow)
            case "arrow_right": MacRemoteManager.shared.simulateKey(.rightArrow)
            case "enter": MacRemoteManager.shared.simulateKey(.enter)
            case "space": MacRemoteManager.shared.simulateKey(.space)
            case "escape": MacRemoteManager.shared.simulateKey(.escape)
            case "vol_up": MacRemoteManager.shared.increaseVolume()
            case "vol_down": MacRemoteManager.shared.decreaseVolume()
            case "vol_mute": MacRemoteManager.shared.toggleMute()
            case "vol_set":
                if let value = dict["value"] as? Int {
                    MacRemoteManager.shared.setVolume(value)
                }
            case "media_play_pause": MacRemoteManager.shared.simulateMediaKey(.playPause)
            case "media_next": MacRemoteManager.shared.simulateMediaKey(.next)
            case "media_prev": MacRemoteManager.shared.simulateMediaKey(.previous)
            case "mouse_move":
                if let dx = dict["dx"] as? Double, let dy = dict["dy"] as? Double {
                    MacRemoteManager.shared.simulateMouseRelativeMove(dx: CGFloat(dx), dy: CGFloat(dy))
                }
            case "mouse_click":
                if let buttonStr = dict["button"] as? String, let isDown = dict["isDown"] as? Bool {
                    let button: CGMouseButton
                    switch buttonStr {
                    case "right": button = .right
                    case "center": button = .center
                    default: button = .left
                    }
                    MacRemoteManager.shared.simulateMouseClick(button: button, isDown: isDown)
                }
            case "mouse_scroll":
                if let dx = dict["dx"] as? Double, let dy = dict["dy"] as? Double {
                    MacRemoteManager.shared.simulateMouseScroll(dx: CGFloat(dx), dy: CGFloat(dy))
                }
            default: break
            }
        }
    }

    private func handleMacMediaControlRequest(_ message: Message) {
        if let dict = message.data.value as? [String: Any],
           let action = dict["action"] as? String {
            handleMacMediaControl(action: action)
        }
    }

    private func handleMacMediaControl(action: String) {
        switch action {
        case "play": NowPlayingCLI.shared.play()
        case "pause": NowPlayingCLI.shared.pause()
        case "previous": NowPlayingCLI.shared.previous()
        case "next": NowPlayingCLI.shared.next()
        case "stop": NowPlayingCLI.shared.stop()
        default: break
        }
        sendMacMediaControlResponse(action: action, success: true)
    }

    private func handleNotificationUpdate(_ message: Message) {
        if let dict = message.data.value as? [String: Any],
           let nid = dict["id"] as? String {
            if let action = dict["action"] as? String, action.lowercased() == "dismiss" || dict["dismissed"] as? Bool == true {
                DispatchQueue.main.async {
                    if AppState.shared.notifications.contains(where: { $0.nid == nid }) {
                        AppState.shared.removeNotificationById(nid)
                    }
                    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [nid])
                }
            }
        }
    }

    private func handleNotificationActionResponse(_ message: Message) {
        if let dict = message.data.value as? [String: Any],
           let id = dict["id"] as? String,
           let action = dict["action"] as? String,
           let success = dict["success"] as? Bool {
            print("[websocket] Notification action response id=\(id) action=\(action) success=\(success)")
        }
    }

    private func handleDismissalResponse(_ message: Message) {
        if let dict = message.data.value as? [String: Any],
           let id = dict["id"] as? String,
           let success = dict["success"] as? Bool {
            print("[websocket] Dismissal \(success ? "succeeded" : "failed") for notification id: \(id)")
        }
    }

    private func handleMediaControlResponse(_ message: Message) {
        if let dict = message.data.value as? [String: Any],
           let action = dict["action"] as? String,
           let success = dict["success"] as? Bool {
            print("[websocket] Media control \(action) \(success ? "succeeded" : "failed")")
        }
    }

    private func handleClipboardUpdate(_ message: Message) {
        if let dict = message.data.value as? [String: Any],
           let text = dict["text"] as? String {
            AppState.shared.updateClipboardFromAndroid(text)
        }
    }

    private func handleFileChunkAck(_ message: Message) {
        if let dict = message.data.value as? [String: Any],
           let id = dict["id"] as? String,
           let index = dict["index"] as? Int {
            self.lock.lock()
            if var set = outgoingAcks[id] {
                set.insert(index)
                outgoingAcks[id] = set
            }
            self.lock.unlock()
        }
    }

    private func handleTransferVerified(_ message: Message) {
        if let dict = message.data.value as? [String: Any],
           let id = dict["id"] as? String,
           let verified = dict["verified"] as? Bool {
            AppState.shared.completeOutgoingVerified(id: id, verified: verified)
            AppState.shared.postNativeNotification(
                id: "transfer_verified_\(id)",
                appName: "AirSync",
                title: "Transfer complete",
                body: verified ? "File sent successfully" : "File might be incomplete"
            )
        }
    }

    private func handleFileTransferCancel(_ message: Message) {
        if let dict = message.data.value as? [String: Any],
           let id = dict["id"] as? String {
            DispatchQueue.main.async {
                AppState.shared.stopTransferRemote(id: id)
            }
        }
    }

    private func handleCallControlResponse(_ message: Message) {
        if let dict = message.data.value as? [String: Any],
           let action = dict["action"] as? String,
           let success = dict["success"] as? Bool {
            let msg = dict["message"] as? String ?? ""
            print("[websocket] Call control \(action) \(success ? "succeeded" : "failed"): \(msg)")
        }
    }

    // MARK: - Outgoing Responses

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
        let macName = AppState.shared.myDevice?.name ?? (Host.current().localizedName ?? "My Mac")
        let categoryTypeRaw = DeviceTypeUtil.deviceTypeDescription()
        let exactDeviceNameRaw = DeviceTypeUtil.deviceFullDescription()
        let categoryType = categoryTypeRaw.isEmpty ? "Mac" : categoryTypeRaw
        let exactDeviceName = exactDeviceNameRaw.isEmpty ? categoryType : exactDeviceNameRaw
        let isPlusSubscription = AppState.shared.isPlus
        let savedAppPackages = Array(AppState.shared.androidApps.keys)

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
                jsonDict["model"] = exactDeviceName
                jsonDict["type"] = categoryType
                jsonDict["isPlus"] = isPlusSubscription

                let messageDict: [String: Any] = [
                    "type": "macInfo",
                    "data": jsonDict
                ]

                let messageJsonData = try JSONSerialization.data(withJSONObject: messageDict, options: [])
                if let messageJsonString = String(data: messageJsonData, encoding: .utf8) {
                    sendToFirstAvailable(message: messageJsonString)
                }
            }
        } catch {
            print("[websocket] Error creating mac info response: \(error)")
        }
    }
}
