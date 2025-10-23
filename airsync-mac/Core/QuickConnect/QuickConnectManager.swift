//
//  QuickConnectManager.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-09-30.
//

import Foundation
internal import Combine

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
    
    private init() {
        loadDeviceHistoryFromDisk()
    }
    
    // MARK: - Public Interface
    
    /// Gets the last connected device for the current network
    func getLastConnectedDevice() -> Device? {
        guard let currentIP = getCurrentMacIP() else { return nil }
        return lastConnectedDevices[currentIP]
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
    
    /// Attempts to wake up and reconnect to the last connected device
    func wakeUpLastConnectedDevice() {
        guard let lastDevice = getLastConnectedDevice() else {
            print("[quick-connect] No last connected device to wake up")
            return
        }
        
        print("[quick-connect] Attempting to wake up device: \(lastDevice.name) at \(lastDevice.ipAddress)")
        print("[quick-connect] Will try HTTP port \(Self.ANDROID_HTTP_WAKEUP_PORT), then UDP port \(Self.ANDROID_UDP_WAKEUP_PORT) if needed")
        
        Task {
            await sendWakeUpRequest(to: lastDevice)
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
    
    private func sendWakeUpRequest(to device: Device) async {
        // Get current connection info to send in wake-up request
        guard let currentIP = getCurrentMacIP(),
              let currentPort = getCurrentMacPort() else {
            print("[quick-connect] Cannot wake up device - no current connection info available")
            return
        }
        
        let macName = AppState.shared.myDevice?.name ?? "My Mac"
        
        // Create wake-up message with current connection details (no auth key needed)
        let wakeUpMessage = """
        {
            "type": "wakeUpRequest",
            "data": {
                "macIP": "\(currentIP)",
                "macPort": \(currentPort),
                "macName": "\(macName)",
                "isPlus": \(AppState.shared.isPlus)
            }
        }
        """
        
        // Try to send HTTP POST request to the Android device
        await sendHTTPWakeUpRequest(to: device, message: wakeUpMessage)
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
        let udpMessage = "AIRSYNC_WAKEUP:\(message)"
        
        DispatchQueue.global(qos: .background).async {
            // Create UDP socket and send wake-up message
            let socket = socket(AF_INET, SOCK_DGRAM, 0)
            defer { close(socket) }
            
            guard socket >= 0 else {
                print("[quick-connect] Failed to create UDP socket")
                return
            }
            
            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = in_port_t(UInt16(Self.ANDROID_UDP_WAKEUP_PORT).bigEndian)
            inet_aton(device.ipAddress, &addr.sin_addr)
            
            let messageData = udpMessage.data(using: .utf8) ?? Data()
            _ = messageData.withUnsafeBytes { bytes in
                withUnsafePointer(to: addr) { addrPtr in
                    addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                        return sendto(socket, bytes.bindMemory(to: Int8.self).baseAddress, messageData.count, 0, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
        }
    }
}
