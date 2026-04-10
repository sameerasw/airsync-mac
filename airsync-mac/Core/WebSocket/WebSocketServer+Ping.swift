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
    /// Only the *primary* session going stale triggers a full server restart. Non-primary zombie
    /// sessions are force-closed silently to avoid cascading restarts.
    func performPing() {
        self.lock.lock()
        let sessions = activeSessions
        let timeout = self.activityTimeout
        let key = self.symmetricKey
        let primary = self.primarySessionID
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
                let isPrimary = (sessionId == primary)
                if isPrimary {
                    // Primary session has gone silent — full reconnect cycle
                    print("[websocket] Primary session \(sessionId) is stale (>\(Int(timeout))s). Restarting server.")
                    DispatchQueue.main.async {
                        AppState.shared.disconnectDevice()
                        ADBConnector.disconnectADB()
                        AppState.shared.adbConnected = false
                        self.restartServer()
                    }
                    return // Let the restart handle everything; stop iterating
                } else {
                    // Non-primary zombie — just evict it without touching app state
                    print("[websocket] Non-primary session \(sessionId) is stale. Force-closing silently.")
                    self.lock.lock()
                    self.activeSessions.removeAll { $0 === session }
                    self.lastActivity.removeValue(forKey: sessionId)
                    self.lock.unlock()
                    session.writeBinary([]) // Force-close
                    continue
                }
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
