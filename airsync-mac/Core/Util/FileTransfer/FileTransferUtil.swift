//
//  FileTransferUtil.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2025-08-16.
//

import SwiftUI

extension AppState {
    enum TransferDirection: String, Codable { case outgoing, incoming }
    enum TransferStatus: Equatable {
        case inProgress
        case completed(verified: Bool?)
        case failed(reason: String)
    }

    struct FileTransferSession: Identifiable, Equatable {
        let id: String
        let name: String
        let size: Int
        let mime: String
        let direction: TransferDirection
        var bytesTransferred: Int
        var chunkSize: Int
        let startedAt: Date
        var estimatedTimeRemaining: TimeInterval? // smoothed
        var smoothedSpeed: Double?
        var lastUpdateTime: Date
        var bytesSinceLastUpdate: Int
        var status: TransferStatus

        var progress: Double {
            guard size > 0 else { return 0 }
            return min(1.0, Double(bytesTransferred) / Double(size))
        }
    }

    func startOutgoingTransfer(id: String, name: String, size: Int, mime: String, chunkSize: Int) {
        DispatchQueue.main.async {
            self.transfers[id] = FileTransferSession(
                id: id,
                name: name,
                size: size,
                mime: mime,
                direction: .outgoing,
                bytesTransferred: 0,
                chunkSize: chunkSize,
                startedAt: Date(),
                lastUpdateTime: Date(),
                bytesSinceLastUpdate: 0,
                status: .inProgress
            )
            
            // Auto-show dialog if enabled
            if self.showFileShareDialog {
                self.activeTransferId = id
                self.transferDismissTimer?.invalidate()
                self.transferDismissTimer = nil
            }
        }
    }

    func startIncomingTransfer(id: String, name: String, size: Int, mime: String) {
        DispatchQueue.main.async {
            self.transfers[id] = FileTransferSession(
                id: id,
                name: name,
                size: size,
                mime: mime,
                direction: .incoming,
                bytesTransferred: 0,
                chunkSize: 0,
                startedAt: Date(),
                lastUpdateTime: Date(),
                bytesSinceLastUpdate: 0,
                status: .inProgress
            )

            // Auto-show dialog if enabled
            if self.showFileShareDialog {
                self.activeTransferId = id
                self.transferDismissTimer?.invalidate()
                self.transferDismissTimer = nil
            }
        }
    }

    func updateOutgoingProgress(id: String, bytesTransferred: Int) {
        DispatchQueue.main.async {
            guard var s = self.transfers[id] else { return }
            let now = Date()
            let timeDiff = now.timeIntervalSince(s.lastUpdateTime)
            let bytesDiff = bytesTransferred - s.bytesTransferred
            
            s.bytesTransferred = min(bytesTransferred, s.size)
            s.bytesSinceLastUpdate += bytesDiff
            
            // Update speed / ETA every 1 second
            if timeDiff >= 1.0 {
                let intervalSpeed = Double(s.bytesSinceLastUpdate) / timeDiff
                
                let alpha = 0.4
                if let oldSpeed = s.smoothedSpeed {
                    s.smoothedSpeed = alpha * intervalSpeed + (1.0 - alpha) * oldSpeed
                } else {
                    s.smoothedSpeed = intervalSpeed
                }
                
                s.lastUpdateTime = now
                s.bytesSinceLastUpdate = 0
                
                // Calculate ETA
                if let speed = s.smoothedSpeed, speed > 0 {
                    let remainingBytes = Double(s.size - s.bytesTransferred)
                    let newEta = remainingBytes / speed
                    s.estimatedTimeRemaining = newEta
                }
            }
            
            self.transfers[id] = s
        }
    }

    func updateIncomingProgress(id: String, receivedBytes: Int) {
        DispatchQueue.main.async {
            guard var s = self.transfers[id] else { return }
            let now = Date()
            let timeDiff = now.timeIntervalSince(s.lastUpdateTime)
            let bytesDiff = receivedBytes - s.bytesTransferred
            
            s.bytesTransferred = min(receivedBytes, s.size)
            s.bytesSinceLastUpdate += bytesDiff
            
            // Update speed / ETA every 1 second
            if timeDiff >= 1.0 {
                let intervalSpeed = Double(s.bytesSinceLastUpdate) / timeDiff
                
                let alpha = 0.4
                if let oldSpeed = s.smoothedSpeed {
                    s.smoothedSpeed = alpha * intervalSpeed + (1.0 - alpha) * oldSpeed
                } else {
                    s.smoothedSpeed = intervalSpeed
                }
                
                s.lastUpdateTime = now
                s.bytesSinceLastUpdate = 0
                
                if let speed = s.smoothedSpeed, speed > 0 {
                    let remaining = Double(s.size - s.bytesTransferred)
                    s.estimatedTimeRemaining = remaining / speed
                }
            }
            
            self.transfers[id] = s
        }
    }

    func completeIncoming(id: String, verified: Bool?) {
        DispatchQueue.main.async {
            guard var s = self.transfers[id] else { return }
            s.bytesTransferred = s.size
            s.status = .completed(verified: verified)
            self.transfers[id] = s
            
            // Auto-dismiss after 10s if this is the active one
            if self.activeTransferId == id {
                self.scheduleTransferDismiss()
            }
        }
    }

    func completeOutgoingVerified(id: String, verified: Bool?) {
        DispatchQueue.main.async {
            guard var s = self.transfers[id] else { return }
            s.status = .completed(verified: verified)
            self.transfers[id] = s
            
            // Auto-dismiss after 10s if this is the active one
            if self.activeTransferId == id {
                self.scheduleTransferDismiss()
            }
        }
    }

    func failTransfer(id: String, reason: String) {
        DispatchQueue.main.async {
            guard var s = self.transfers[id] else { return }
            s.status = .failed(reason: reason)
            self.transfers[id] = s
            
            // Auto-dismiss failed transfers after 10s too, to let user see error
            if self.activeTransferId == id {
               self.scheduleTransferDismiss()
            }
        }
    }

    /// Remove transfers that are completed (either verified or not). Leaves in-progress and failed transfers.
    func removeCompletedTransfers() {
        DispatchQueue.main.async {
            for (id, session) in self.transfers {
                switch session.status {
                case .completed(_):
                    self.transfers.removeValue(forKey: id)
                default:
                    break
                }
            }
        }
    }
    func scheduleTransferDismiss() {
        self.transferDismissTimer?.invalidate()
        self.transferDismissTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.clearActiveTransfer()
            }
        }
    }

    func clearActiveTransfer() {
        self.activeTransferId = nil
        self.transferDismissTimer?.invalidate()
        self.transferDismissTimer = nil
    }

    func cancelTransfer(id: String) {
        // Send cancel message to remote
        WebSocketServer.shared.sendTransferCancel(id: id)
        failTransfer(id: id, reason: "Cancelled by user")
    }
    
    func stopTransferRemote(id: String) {
        failTransfer(id: id, reason: "Cancelled by receiver")
    }
    
    func stopAllTransfers(reason: String) {
        DispatchQueue.main.async {
            for (id, session) in self.transfers {
                if case .inProgress = session.status {
                    var s = session
                    s.status = .failed(reason: reason)
                    self.transfers[id] = s
                }
            }
            // Clear active if any
            if self.activeTransferId != nil {
                self.scheduleTransferDismiss()
            }
        }
    }
}

