//
//  WebSocketServer+Ping.swift
//  airsync-mac
//

import Foundation
import Swifter

extension WebSocketServer {
    
    // MARK: - Heartbeat / Ping
    
    func startPing() {
        DispatchQueue.main.async {
            self.stopPing()
            self.lock.lock()
            let interval = self.pingInterval
            self.lock.unlock()
            
            self.pingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                self?.performPing()
            }
            self.pingTimer?.tolerance = 0.5
        }
    }
    
    func stopPing() {
        self.lock.lock()
        pingTimer?.invalidate()
        pingTimer = nil
        self.lock.unlock()
    }
    
    /// Performs a session health check.
    /// Identifies and forcibly disconnects stale sessions that have exceeded the activity timeout.
    func performPing() {
        self.lock.lock()
        let sessions = activeSessions
        let timeout = self.activityTimeout
        let key = self.symmetricKey
        self.lock.unlock()
        
        if sessions.isEmpty { return }
        
        let now = Date()
        
        // We use a local copy of sessions to avoid prolonged locking during network I/O
        for session in sessions {
            let sessionId = ObjectIdentifier(session)
            
            self.lock.lock()
            let lastDate = self.lastActivity[sessionId] ?? .distantPast
            self.lock.unlock()
            
            let isStale = now.timeIntervalSince(lastDate) > timeout
            
            if isStale {
                print("[websocket] Session \(sessionId) is stale. Performing hard reset and discovery restart.")
                DispatchQueue.main.async {
                    // Disconnect and restart
                    AppState.shared.disconnectDevice()
                    ADBConnector.disconnectADB()
                    AppState.shared.adbConnected = false
                    
                    self.stop()
                    self.start(port: self.localPort ?? Defaults.serverPort)
                }
                return
            }
            
            let pingJson = "{\"type\":\"ping\",\"data\":{}}"
            
            DispatchQueue.global(qos: .utility).async {
                if let key = key, let encrypted = encryptMessage(pingJson, using: key) {
                    session.writeText(encrypted)
                } else {
                    session.writeText(pingJson)
                }
            }
        }
    }
}
