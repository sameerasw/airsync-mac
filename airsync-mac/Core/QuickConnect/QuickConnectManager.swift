//
//  QuickConnectManager.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-09-30.
//

import Foundation
import Combine

/// Manages quick reconnection functionality for previously connected devices
class QuickConnectManager: ObservableObject {
    static let shared = QuickConnectManager()
    
    // Android wake-up ports
    private static let ANDROID_HTTP_WAKEUP_PORT = 8888
    private static let ANDROID_UDP_WAKEUP_PORT = 8889
    
    // Storage key for device history
    private static let DEVICE_HISTORY_KEY = "deviceHistory"
    
    // Store last connected devices per network (key: Mac IP, value: Device)
    @Published var lastConnectedDevices: [String: Device] = [:]
    
    // Track which device is currently being connected to 
    @Published var connectingDeviceID: String? = nil
    
    private init() {
        loadDeviceHistoryFromDisk()
    }
    
    // MARK: - Public Interface
    
    /// Gets the last connected device for the current network, with a gateway fallback for hotspots
    func getLastConnectedDevice() -> Device? {
        guard let currentIP = getCurrentMacIP() else { return nil }
        
        // 1. Exact match for this Mac IP (if we connected on this network/hotspot before)
        if let exactMatch = lastConnectedDevices[currentIP] {
            return exactMatch
        }
        
        // 2. Hotspot Fallback: if no exact match, find the most recently connected device from ANY network
        // and target the default gateway (.1) of the current network.
        let allDevices = lastConnectedDevices.values
        guard let fallbackDevice = allDevices.first else { return nil }
        
        // Construct gateway IP by replacing the last octet with .1
        let parts = currentIP.split(separator: ".")
        if parts.count == 4 {
            let gatewayIP = parts[0...2].joined(separator: ".") + ".1"
            print("[quick-connect] No exact device history for IP \(currentIP). Hotspot fallback: targeting gateway \(gatewayIP) for \(fallbackDevice.name)")
            return Device(
                name: fallbackDevice.name,
                ipAddress: gatewayIP,
                port: fallbackDevice.port,
                version: fallbackDevice.version,
                adbPorts: fallbackDevice.adbPorts
            )
        }
        
        return nil
    }
    
    /// Saves a device as the last connected for the current network
    func saveLastConnectedDevice(_ device: Device) {
        guard let currentMacIP = getCurrentMacIP() else {
            print("[quick-connect] Cannot save device - no current Mac IP available")
            return
        }
        
        DispatchQueue.main.async {
            self.lastConnectedDevices[currentMacIP] = device
            self.saveDeviceHistoryToDisk()
        }
        print("[quick-connect] Saved last connected device for network \(currentMacIP): \(device.name) (\(device.ipAddress))")
    }
    
    /// Clears the last connected device for the current network
    func clearLastConnectedDevice() {
        guard let currentMacIP = getCurrentMacIP() else { return }
        
        DispatchQueue.main.async {
            self.lastConnectedDevices.removeValue(forKey: currentMacIP)
            self.saveDeviceHistoryToDisk()
        }
        print("[quick-connect] Cleared last connected device for network \(currentMacIP)")
    }
    
    /// Attempts to wake up and reconnect to a specific discovered device
    func connect(to discoveredDevice: DiscoveredDevice) {
        // Pick best IP using subnet matching
        let bestIP = getBestTargetIP(from: discoveredDevice.ips)
        
        // Convert DiscoveredDevice to Device model
        let device = Device(
            name: discoveredDevice.name,
            ipAddress: bestIP,
            port: discoveredDevice.port,
            version: "Unknown",
            adbPorts: []
        )
        
        saveLastConnectedDevice(device)
        
        print("[quick-connect] Initiating connection to discovered device: \(device.name) at \(device.ipAddress)")
        
        // Show progress in UI
        if Thread.isMainThread {
            self.connectingDeviceID = discoveredDevice.id
            AppState.shared.isManuallyDisconnected = false
        } else {
            DispatchQueue.main.async {
                self.connectingDeviceID = discoveredDevice.id
                AppState.shared.isManuallyDisconnected = false
            }
        }
        
        Task {
            await sendWakeUpRequest(to: device, isManual: true)
        }
    }

    /// Attempts to wake up and reconnect to the last connected device
    func wakeUpLastConnectedDevice() {
        guard !AppState.shared.isManuallyDisconnected else {
            print("[quick-connect] Skipping wake-up request because isManuallyDisconnected is true")
            return
        }
        guard let lastDevice = getLastConnectedDevice() else {
            print("[quick-connect] No last connected device to wake up")
            return
        }
        
        print("[quick-connect] Attempting to wake up device: \(lastDevice.name) at \(lastDevice.ipAddress)")
        print("[quick-connect] Will try HTTP port \(Self.ANDROID_HTTP_WAKEUP_PORT), then UDP port \(Self.ANDROID_UDP_WAKEUP_PORT) if needed")
        
        Task {
            await sendWakeUpRequest(to: lastDevice, isManual: false)
        }
    }
    
    /// Refreshes device info for current network (triggers UI updates)
    func refreshDeviceForCurrentNetwork() {
        objectWillChange.send()
        print("[quick-connect] Refreshed device info for current network")
    }
    
    // MARK: - Private Implementation
    
    private func getCurrentMacIP() -> String? {
        return WebSocketServer.shared.getLocalIPAddress(
            adapterName: AppState.shared.selectedNetworkAdapterName
        )
    }
    
    private func getCurrentMacPort() -> UInt16? {
        return WebSocketServer.shared.localPort
    }
    
    private func saveDeviceHistoryToDisk() {
        if let encoded = try? JSONEncoder().encode(lastConnectedDevices) {
            UserDefaults.standard.set(encoded, forKey: Self.DEVICE_HISTORY_KEY)
        }
    }
    
    private func loadDeviceHistoryFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: Self.DEVICE_HISTORY_KEY),
              let history = try? JSONDecoder().decode([String: Device].self, from: data) else {
            return
        }
        
        self.lastConnectedDevices = history
        print("[quick-connect] Loaded device history for \(history.count) networks")
    }
    
    // MARK: - Wake-up Implementation
    
    private func sendWakeUpRequest(to device: Device, isManual: Bool) async {
        // Get current connection info to send in wake-up request
        var currentIP = getBestLocalIP(for: device.ipAddress)
        var currentPort = getCurrentMacPort()
        
        if currentIP == nil || currentPort == nil {
            print("[quick-connect] Network info not ready, waiting for WebSocket server...")
            for i in 1...10 {
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
                currentIP = getBestLocalIP(for: device.ipAddress)
                currentPort = getCurrentMacPort()
                
                if currentIP != nil && currentPort != nil {
                    print("[quick-connect] Network info obtained after \(i * 200)ms")
                    break
                }
            }
        }
        
        guard let finalIP = currentIP, let finalPort = currentPort else {
            print("[quick-connect] Cannot wake up device - no current connection info available after waiting")
            DispatchQueue.main.async {
                self.connectingDeviceID = nil
            }
            return
        }
        
        let macName = AppState.shared.myDevice?.name ?? "My Mac"
        
        // Create wake-up message with current connection details (no auth key needed)
        let wakeUpMessage = """
        {
            "type": "wakeUpRequest",
            "data": {
                "macIP": "\(finalIP)",
                "macPort": \(finalPort),
                "macName": "\(macName)",
                "isPlus": \(AppState.shared.isPlus),
                "isManual": \(isManual)
            }
        }
        """
        
        // Try to send HTTP POST request to the Android device
        Task {
            await sendUDPWakeUpRequest(to: device, message: wakeUpMessage)
        }
        await sendHTTPWakeUpRequest(to: device, message: wakeUpMessage)
        
        // Clear progress after short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.connectingDeviceID = nil
        }
    }
    
    /// Selects the best target IP from a set of discovered IPs by matching subnets with the Mac's adapters
    func getBestTargetIP(from targetIPs: Set<String>) -> String {
        let adapters = WebSocketServer.shared.getAvailableNetworkAdapters()
        let allMacIPs = adapters.map { $0.address }
        
        // 1. Try to find a target IP that shares the first 3 octets (same subnet) with one of our Mac IPs
        for macIP in allMacIPs {
            let macParts = macIP.split(separator: ".")
            if macParts.count >= 3 {
                let macSubnet = macParts[0...2].joined(separator: ".") + "."
                if let match = targetIPs.first(where: { $0.hasPrefix(macSubnet) }) {
                    return match
                }
            }
        }
        
        // 2. Try to find a target IP that shares the first 2 octets with one of our Mac IPs
        for macIP in allMacIPs {
            let macParts = macIP.split(separator: ".")
            if macParts.count >= 2 {
                let macSubnet = macParts[0...1].joined(separator: ".") + "."
                if let match = targetIPs.first(where: { $0.hasPrefix(macSubnet) }) {
                    return match
                }
            }
        }
        
        // 3. Try to find a target IP that shares the first octet with one of our Mac IPs
        for macIP in allMacIPs {
            let macParts = macIP.split(separator: ".")
            if let firstOctet = macParts.first {
                let macSubnet = "\(firstOctet)."
                if let match = targetIPs.first(where: { $0.hasPrefix(macSubnet) }) {
                    return match
                }
            }
        }
        
        // 4. Fallback: Prefer non-Tailscale local IPs
        if let localIP = targetIPs.first(where: { !$0.hasPrefix("100.") }) {
            return localIP
        }
        
        // 5. Ultimate fallback
        return targetIPs.first ?? ""
    }
    
    /// Selects the best local IP to present to the target device
    /// Prioritizes IPs that match the target's subnet/prefix (e.g. Tailscale 100.x)
    private func getBestLocalIP(for targetIP: String) -> String? {
        let adapters = WebSocketServer.shared.getAvailableNetworkAdapters()
        let allIPs = adapters.map { $0.address }
        
        // 1. If user manually selected an adapter, MUST use that
        if let selected = AppState.shared.selectedNetworkAdapterName {
            if let match = adapters.first(where: { $0.name == selected }) {
                return match.address
            }
        }
        
        // 2. If valid target IP, try to match prefix
        if !targetIP.isEmpty {
            // Check for Tailscale (100.x)
            if targetIP.hasPrefix("100.") {
                if let tailscaleIP = allIPs.first(where: { $0.hasPrefix("100.") }) {
                    return tailscaleIP
                }
            }
            
            // Check for other common prefixes (subnet match)
            let parts = targetIP.split(separator: ".")
            if let firstOctet = parts.first {
                let prefix = "\(firstOctet)."
                if let match = allIPs.first(where: { $0.hasPrefix(prefix) }) {
                    return match
                }
            }
        }
        
        // 3. Fallback: Use the first available IP 
        return allIPs.first
    }
    
    private func sendHTTPWakeUpRequest(to device: Device, message: String) async {
        print("[quick-connect] Trying HTTP wake-up to \(device.ipAddress):\(Self.ANDROID_HTTP_WAKEUP_PORT)")
        
        // Construct URL for Android device's HTTP endpoint
        guard let url = URL(string: "http://\(device.ipAddress):\(Self.ANDROID_HTTP_WAKEUP_PORT)/wakeup") else {
            print("[quick-connect] Invalid wake-up URL for device")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = message.data(using: .utf8)
        request.timeoutInterval = 5.0
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    print("[quick-connect] Wake-up request successful - device should reconnect soon")
                } else {
                    print("[quick-connect] Wake-up request failed with status: \(httpResponse.statusCode)")
                }
            }
        } catch {
            print("[quick-connect] Failed to send wake-up request: \(error)")
            
            // Fallback: Try UDP broadcast
            await sendUDPWakeUpRequest(to: device, message: message)
        }
    }
    
    private func sendUDPWakeUpRequest(to device: Device, message: String) async {
        print("[quick-connect] Trying UDP wake-up to \(device.ipAddress):\(Self.ANDROID_UDP_WAKEUP_PORT) as fallback")
        
        // Simple UDP wake-up attempt (fire and forget)
        let udpMessage = message
        
        DispatchQueue.global(qos: .background).async {
            // Create UDP socket and send wake-up message
            let socketFd = socket(AF_INET, SOCK_DGRAM, 0)
            defer { close(socketFd) }
            
            guard socketFd >= 0 else {
                print("[quick-connect] Failed to create UDP socket")
                return
            }
            
            // Enable broadcast
            var broadcastEnable: Int32 = 1
            setsockopt(socketFd, SOL_SOCKET, SO_BROADCAST, &broadcastEnable, socklen_t(MemoryLayout<Int32>.size))
            
            let messageData = udpMessage.data(using: .utf8) ?? Data()
            
            // 1. Send Unicast
            var unicastAddr = sockaddr_in()
            unicastAddr.sin_family = sa_family_t(AF_INET)
            unicastAddr.sin_port = in_port_t(UInt16(Self.ANDROID_UDP_WAKEUP_PORT).bigEndian)
            inet_aton(device.ipAddress, &unicastAddr.sin_addr)
            
            _ = messageData.withUnsafeBytes { bytes in
                withUnsafePointer(to: unicastAddr) { addrPtr in
                    addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                        sendto(socketFd, bytes.bindMemory(to: Int8.self).baseAddress, messageData.count, 0, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            
            // 2. Send Broadcast
            var broadcastAddr = sockaddr_in()
            broadcastAddr.sin_family = sa_family_t(AF_INET)
            broadcastAddr.sin_port = in_port_t(UInt16(Self.ANDROID_UDP_WAKEUP_PORT).bigEndian)
            broadcastAddr.sin_addr.s_addr = inet_addr("255.255.255.255")
            
            _ = messageData.withUnsafeBytes { bytes in
                withUnsafePointer(to: broadcastAddr) { addrPtr in
                    addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                        sendto(socketFd, bytes.bindMemory(to: Int8.self).baseAddress, messageData.count, 0, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
        }
    }
}
