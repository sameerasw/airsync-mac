//
//  WebSocketServer+Outgoing.swift
//  airsync-mac
//

import Foundation
import Swifter
import CryptoKit

extension WebSocketServer {
    
    // MARK: - Sending Helpers

    func broadcast(message: String) {
        lock.lock()
        defer { lock.unlock() }
        guard primarySessionID != nil else { return }
        activeSessions.forEach { $0.writeText(message) }
    }

    func sendToFirstAvailable(message: String) {
        lock.lock()
        guard let pId = primarySessionID,
              let session = activeSessions.first(where: { ObjectIdentifier($0) == pId }) else {
            lock.unlock()
            return
        }
        let key = symmetricKey
        lock.unlock()
        
        if let key = key, let encrypted = encryptMessage(message, using: key) {
            session.writeText(encrypted)
        } else {
            session.writeText(message)
        }
    }

    private func sendMessage(type: String, data: [String: Any]) {
        let messageDict: [String: Any] = [
            "type": type,
            "data": data
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: messageDict, options: [])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                sendToFirstAvailable(message: jsonString)
            }
        } catch {
            print("[websocket] Error creating \(type) message: \(error)")
        }
    }

    // MARK: - Outgoing Requests

    func sendDisconnectRequest() {
        sendMessage(type: "disconnectRequest", data: [:])
    }

    func sendRefreshAdbPortsRequest() {
        sendMessage(type: "refreshAdbPorts", data: [:])
    }

    func sendTransferCancel(id: String) {
        sendMessage(type: "fileTransferCancel", data: ["id": id])
    }

    func toggleNotification(for package: String, to state: Bool) {
        guard var app = AppState.shared.androidApps[package] else { return }
        app.listening = state
        AppState.shared.androidApps[package] = app
        AppState.shared.saveAppsToDisk()

        sendMessage(type: "toggleAppNotif", data: ["package": package, "state": "\(state)"])
    }

    func sendBrowseRequest(path: String, showHidden: Bool = false) {
        sendMessage(type: "browseLs", data: ["path": path, "showHidden": showHidden])
    }

    func sendPullRequest(path: String) {
        let message = FileTransferProtocol.buildFilePull(path: path)
        sendToFirstAvailable(message: message)
    }

    func dismissNotification(id: String) {
        sendMessage(type: "dismissNotification", data: ["id": id])
    }

    func sendNotificationAction(id: String, name: String, text: String? = nil) {
        var data: [String: Any] = ["id": id, "name": name]
        if let t = text, !t.isEmpty { data["text"] = t }
        sendMessage(type: "notificationAction", data: data)
    }

    // MARK: - Media Controls

    func togglePlayPause() { sendMediaAction("playPause") }
    func skipNext() { sendMediaAction("next") }
    func skipPrevious() { sendMediaAction("previous") }
    func stopMedia() { sendMediaAction("stop") }
    func toggleLike() { sendMediaAction("toggleLike") }
    func like() { sendMediaAction("like") }
    func unlike() { sendMediaAction("unlike") }

    private func sendMediaAction(_ action: String) {
        sendMessage(type: "mediaControl", data: ["action": action])
    }

    // MARK: - Volume Controls

    func volumeUp() { sendVolumeAction("volumeUp") }
    func volumeDown() { sendVolumeAction("volumeDown") }
    func toggleMute() { sendVolumeAction("mute") }

    func setVolume(_ volume: Int) {
        sendMessage(type: "volumeControl", data: ["action": "setVolume", "volume": volume])
    }

    private func sendVolumeAction(_ action: String) {
        sendMessage(type: "volumeControl", data: ["action": action])
    }

    func sendMacVolumeUpdate(level: Int) {
        sendMessage(type: "macVolume", data: ["volume": level])
    }

    func sendModifierStatus(status: [String: [String: Any]]) {
        sendMessage(type: "modifierStatus", data: status)
    }

    func sendClipboardUpdate(_ message: String) {
        sendToFirstAvailable(message: message)
    }

    // MARK: - Device Status (Mac -> Android)

    func sendDeviceStatus(batteryLevel: Int, isCharging: Bool, isPaired: Bool, musicInfo: NowPlayingInfo?, albumArtBase64: String? = nil) {
        var statusDict: [String: Any] = [
            "battery": ["level": batteryLevel, "isCharging": isCharging],
            "isPaired": isPaired
        ]

        if let musicInfo {
            statusDict["music"] = [
                "isPlaying": musicInfo.isPlaying ?? false,
                "title": musicInfo.title ?? "",
                "artist": musicInfo.artist ?? "",
                "volume": 50,
                "isMuted": false,
                "albumArt": albumArtBase64 ?? "",
                "likeStatus": "none"
            ]
        }

        sendMessage(type: "status", data: statusDict)
    }

    // MARK: - Call Control

    /// Executes a call control action on the Android device via ADB.
    /// Maps generic actions (accept, end) to specific ADB key events.
    func sendCallAction(eventId: String, action: String) {
        let keyCode: String
        switch action.lowercased() {
        case "accept": keyCode = "5"
        case "decline", "end": keyCode = "6"
        default: keyCode = "6"
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            guard let adbPath = ADBConnector.findExecutable(named: "adb", fallbackPaths: ADBConnector.possibleADBPaths) else { return }
            
            let adbIP = AppState.shared.adbConnectedIP.isEmpty ? AppState.shared.device?.ipAddress ?? "" : AppState.shared.adbConnectedIP
            if !adbIP.isEmpty {
                let adbPort = AppState.shared.adbPort
                let fullAddress = "\(adbIP):\(adbPort)"
                let process = Process()
                process.executableURL = URL(fileURLWithPath: adbPath)
                process.arguments = ["-s", fullAddress, "shell", "input", "keyevent", keyCode]
                
                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    print("[websocket] Failed to send call action: \(error)")
                }
            }
        }
    }

    // MARK: - File Transfer (Mac -> Android)

    /// Initiates a robust file transfer to the connected device.
    /// Implements a sliding window protocol with checksum verification and retry logic for reliable delivery.
    func sendFile(url: URL, chunkSize: Int = 64 * 1024, isClipboard: Bool = false) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            guard FileManager.default.fileExists(atPath: url.path) else { return }

            let fileName = url.lastPathComponent
            let mime = self.mimeType(for: url) ?? "application/octet-stream"
            
            guard let fileHandle = try? FileHandle(forReadingFrom: url) else { return }
            
            let totalSize: Int
            do {
                let attr = try FileManager.default.attributesOfItem(atPath: url.path)
                totalSize = attr[.size] as? Int ?? 0
            } catch { return }
            
            var hasher = SHA256()
            let hashBuffer = 1024 * 1024
            while true {
                let data = fileHandle.readData(ofLength: hashBuffer)
                if data.isEmpty { break }
                hasher.update(data: data)
            }
            let checksum = hasher.finalize().compactMap { String(format: "%02x", $0) }.joined()
            try? fileHandle.seek(toOffset: 0)

            let transferId = UUID().uuidString
            AppState.shared.startOutgoingTransfer(id: transferId, name: fileName, size: totalSize, mime: mime, chunkSize: chunkSize)

            let initMessage = FileTransferProtocol.buildInit(id: transferId, name: fileName, size: Int64(totalSize), mime: mime, chunkSize: chunkSize, checksum: checksum, isClipboard: isClipboard)
            self.sendToFirstAvailable(message: initMessage)

            let windowSize = 8
            let totalChunks = totalSize == 0 ? 1 : (totalSize + chunkSize - 1) / chunkSize
            
            self.lock.lock()
            self.outgoingAcks[transferId] = []
            self.lock.unlock()

            var sentBuffer: [Int: (payload: String, attempts: Int, lastSent: Date)] = [:]
            var nextIndexToSend = 0

            var transferFailed = false
            while !transferFailed {
                self.lock.lock()
                let acked = self.outgoingAcks[transferId] ?? []
                self.lock.unlock()
                
                var baseIndex = 0
                while acked.contains(baseIndex) {
                    sentBuffer.removeValue(forKey: baseIndex)
                    baseIndex += 1
                }

                let bytesAcked = min(baseIndex * chunkSize, totalSize)
                DispatchQueue.main.async {
                    AppState.shared.updateOutgoingProgress(id: transferId, bytesTransferred: bytesAcked)
                }

                if baseIndex >= totalChunks { break }

                while nextIndexToSend < totalChunks && (nextIndexToSend - baseIndex) < windowSize {
                    var isCancelled = false
                     DispatchQueue.main.sync {
                        if let t = AppState.shared.transfers[transferId], t.status != .inProgress {
                            isCancelled = true
                        }
                     }
                    if isCancelled {
                        transferFailed = true
                        break
                    }

                    // sendChunkAt logic
                    let offset = UInt64(nextIndexToSend * chunkSize)
                    do {
                        try fileHandle.seek(toOffset: offset)
                        let chunk = fileHandle.readData(ofLength: chunkSize)
                        let base64 = chunk.base64EncodedString()
                        let chunkMessage = FileTransferProtocol.buildChunk(id: transferId, index: nextIndexToSend, base64Chunk: base64)
                        self.sendToFirstAvailable(message: chunkMessage)
                        sentBuffer[nextIndexToSend] = (payload: base64, attempts: 1, lastSent: Date())
                    } catch {
                        transferFailed = true
                        break
                    }
                    nextIndexToSend += 1
                }

                let now = Date()
                for (idx, entry) in sentBuffer {
                    if acked.contains(idx) { continue }
                    let elapsedMs = now.timeIntervalSince(entry.lastSent) * 1000.0
                    if elapsedMs > Double(self.ackWaitMs) {
                        if entry.attempts >= self.maxChunkRetries {
                             DispatchQueue.main.async {
                                AppState.shared.failTransfer(id: transferId, reason: "Multiple retries failed for chunk \(idx)")
                             }
                            transferFailed = true
                            break
                        }
                        let chunkMessage = FileTransferProtocol.buildChunk(id: transferId, index: idx, base64Chunk: entry.payload)
                        self.sendToFirstAvailable(message: chunkMessage)
                        sentBuffer[idx] = (payload: entry.payload, attempts: entry.attempts + 1, lastSent: Date())
                    }
                }
                usleep(20_000)
            }

            try? fileHandle.close()
            
            if !transferFailed {
                 DispatchQueue.main.async {
                    AppState.shared.updateOutgoingProgress(id: transferId, bytesTransferred: totalSize)
                 }
                let completeMessage = FileTransferProtocol.buildComplete(id: transferId, name: fileName, size: Int64(totalSize), checksum: checksum)
                self.sendToFirstAvailable(message: completeMessage)
            }
            
            self.lock.lock()
            self.outgoingAcks.removeValue(forKey: transferId)
            self.lock.unlock()
        }
    }
}
