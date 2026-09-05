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
            
            let timeSinceLastActivity = now.timeIntervalSince(lastDate)
            let isStale = timeSinceLastActivity > timeout
            
            let isPrimary = (sessionId == primary)
            if isPrimary && !isStale {
                let isWeak = timeSinceLastActivity > 10
                DispatchQueue.main.async {
                    if AppState.shared.isConnectionWeak != isWeak {
                        AppState.shared.isConnectionWeak = isWeak
                        if isWeak {
                            print("[websocket] Primary session connection is weak. Time since last activity: \(Int(timeSinceLastActivity))s")
                        } else {
                            print("[websocket] Primary session connection recovered.")
                        }
                    }
                }
            }
            
            if isStale {
                // If relay is currently active, avoid hard restart: stale local sessions
                // can happen during transport switch (LAN <-> relay).
                if AirBridgeClient.shared.connectionState == .relayActive {
                    self.lock.lock()
                    self.activeSessions.removeAll(where: { ObjectIdentifier($0) == sessionId })
                    self.lastActivity.removeValue(forKey: sessionId)
                    let evictedPrimary = (self.primarySessionID == sessionId)
                    if self.primarySessionID == sessionId {
                        self.primarySessionID = nil
                    }
                    let sessionCount = self.activeSessions.count
                    self.lock.unlock()

                    if evictedPrimary {
                        self.publishLanTransportState(isActive: false, reason: "stale_primary_evicted_by_ping")
                    }

                    if sessionCount == 0 {
                        MacRemoteManager.shared.stopVolumeMonitoring()
                        self.stopPing()
                    }
                    continue
                }

                let isPrimary = (sessionId == primary)
                if isPrimary {
                    self.lock.lock()
                    let alreadyRestarting = self.isRestarting
                    self.lock.unlock()
                    
                    if alreadyRestarting {
                        return
                    }
                    
                    print("[websocket] Primary session \(sessionId) is stale (>\(Int(timeout))s). Disconnecting now.")
                    
                    self.lock.lock()
                    self.isRestarting = true
                    self.lock.unlock()
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.0) { [weak self] in
                        guard let self = self else { return }
                        
                        self.lock.lock()
                        let currentPrimary = self.primarySessionID
                        self.lock.unlock()
                        
                        guard currentPrimary == sessionId, AppState.shared.device != nil else {
                            self.lock.lock()
                            self.isRestarting = false
                            self.lock.unlock()
                            print("[websocket] Grace period expired but primary session changed or device disconnected. Cancelling restart.")
                            return
                        }
                        
                        AppState.shared.disconnectDevice()
                        ADBConnector.disconnectADB()
                        AppState.shared.adbConnected = false
                        
                        self.lock.lock()
                        self.isRestarting = false
                        self.lock.unlock()
                        
                        self.restartServer()
                    }
                    return // Let the restart handle everything; stop iterating
                } else {
                    // Non-primary zombie — just evict it without touching app state
                    print("[websocket] Non-primary session \(sessionId) is stale. Force-closing silently.")
                    self.lock.lock()
                    self.activeSessions.removeAll { $0 === session }
                    self.lastActivity.removeValue(forKey: sessionId)
                    session.writeBinary([]) // Force-close
                    self.lock.unlock()
                    continue
                }
            }
            
            let pingJson = "{\"type\":\"ping\",\"data\":{}}"
            
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self = self else { return }
                self.lock.lock()
                defer { self.lock.unlock() }
                if let key = key, let encrypted = encryptMessage(pingJson, using: key) {
                    session.writeText(encrypted)
                } else {
                    session.writeText(pingJson)
                }
            }
        }
    }
}
