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
            s.bytesTransferred = min(bytesTransferred, s.size)
            self.transfers[id] = s
        }
    }

    func updateIncomingProgress(id: String, receivedBytes: Int) {
        DispatchQueue.main.async {
            guard var s = self.transfers[id] else { return }
            s.bytesTransferred = min(receivedBytes, s.size)
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
        failTransfer(id: id, reason: "Cancelled by user")
    }
}

