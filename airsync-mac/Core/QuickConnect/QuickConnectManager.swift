//
//  QuickConnectManager.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-09-30.
//

import Foundation
import Darwin
internal import Combine

/// Manages quick reconnection functionality for previously connected devices
class QuickConnectManager: ObservableObject {
    static let shared = QuickConnectManager()
    
    // Android wake-up ports
    private static let ANDROID_HTTP_WAKEUP_PORT = 8888
    private static let ANDROID_UDP_WAKEUP_PORT = 8889
    
    // Storage key for device history
    private static let DEVICE_HISTORY_KEY = "deviceHistory"
    
    // Store last connected devices per network (key: network prefix like "192.168.1", value: Device)
    // Using network prefix instead of exact Mac IP to handle DHCP IP changes
    @Published var lastConnectedDevices: [String: Device] = [:]
    private var autoReconnectTimer: Timer?
    
    private init() {
        loadDeviceHistoryFromDisk()
        startAutoReconnect()
    }
    
    // MARK: - Public Interface
    
    /// Gets the last connected device for the current network
    func getLastConnectedDevice() -> Device? {
        guard let currentIP = getCurrentMacIP() else { return nil }
        let networkKey = getNetworkKey(from: currentIP)
        return lastConnectedDevices[networkKey]
    }
    
    /// Saves a device as the last connected for the current network
    func saveLastConnectedDevice(_ device: Device) {
        guard let currentMacIP = getCurrentMacIP() else {
            print("[quick-connect] Cannot save device - no current Mac IP available")
            return
        }
        
        let networkKey = getNetworkKey(from: currentMacIP)
        
        DispatchQueue.main.async {
            self.lastConnectedDevices[networkKey] = device
            self.saveDeviceHistoryToDisk()
        }
        print("[quick-connect] Saved last connected device for network \(networkKey): \(device.name) (\(device.ipAddress))")
    }
    
    /// Clears the last connected device for the current network
    func clearLastConnectedDevice() {
        guard let currentMacIP = getCurrentMacIP() else { return }
        let networkKey = getNetworkKey(from: currentMacIP)
        
        DispatchQueue.main.async {
            self.lastConnectedDevices.removeValue(forKey: networkKey)
            self.saveDeviceHistoryToDisk()
        }
        print("[quick-connect] Cleared last connected device for network \(networkKey)")
    }
    
    /// Attempts to wake up and reconnect to the last connected device
    func wakeUpLastConnectedDevice() {
        guard let lastDevice = getLastConnectedDevice() else {
            print("[quick-connect] No last connected device to wake up for current network")
            return
        }
        
        // Check if device IP is on the same network as Mac
        guard let currentMacIP = getCurrentMacIP() else {
            print("[quick-connect] Cannot determine current Mac IP")
            return
        }
        
        let macNetwork = getNetworkKey(from: currentMacIP)
        let deviceNetwork = getNetworkKey(from: lastDevice.ipAddress)
        
        if macNetwork != deviceNetwork {
            print("[quick-connect] ⚠️ Device IP \(lastDevice.ipAddress) is on different network than Mac \(currentMacIP)")
            print("[quick-connect] Skipping wake-up - device may have changed networks or IP")
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
        DispatchQueue.main.async {
            self.objectWillChange.send()
            print("[quick-connect] Refreshed device info for current network")
        }
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
    
    /// Extracts network prefix from IP address (e.g., "192.168.1.34" -> "192.168.1")
    /// This allows matching devices on the same subnet even if exact IPs change due to DHCP
    private func getNetworkKey(from ipAddress: String) -> String {
        let components = ipAddress.split(separator: ".")
        if components.count >= 3 {
            // Use first 3 octets as network identifier (Class C subnet)
            return "\(components[0]).\(components[1]).\(components[2])"
        }
        // Fallback to full IP if parsing fails
        return ipAddress
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
        request.timeoutInterval = 3.0 // Reduced timeout
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    print("[quick-connect] ✅ Wake-up request successful - device should reconnect soon")
                } else {
                    print("[quick-connect] ⚠️ Wake-up request failed with status: \(httpResponse.statusCode)")
                }
            }
        } catch {
            // Only log if it's not a connection refused error (which is expected if service isn't running)
            let nsError = error as NSError
            if nsError.code != -1004 { // -1004 is "Could not connect to server"
                print("[quick-connect] ⚠️ Wake-up error: \(error.localizedDescription)")
            } else {
                print("[quick-connect] ℹ️ Android wake-up service not available (this is normal if not implemented)")
            }
            
            // Don't fallback to UDP if HTTP fails - it's likely the service isn't running
            // await sendUDPWakeUpRequest(to: device, message: message)
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
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = in_port_t(UInt16(Self.ANDROID_UDP_WAKEUP_PORT).bigEndian)

            // Convert IP string to network address; bail out if invalid
            let ipConversionOK: Bool = device.ipAddress.withCString { cStr in
                inet_pton(AF_INET, cStr, &addr.sin_addr) == 1
            }
            guard ipConversionOK else {
                print("[quick-connect] Invalid IPv4 address for UDP wake-up: \(device.ipAddress)")
                return
            }

            let messageData = udpMessage.data(using: .utf8) ?? Data()
            _ = messageData.withUnsafeBytes { bytes in
                withUnsafePointer(to: addr) { addrPtr in
                    addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                        return sendto(socket, bytes.bindMemory(to: UInt8.self).baseAddress, messageData.count, 0, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
        }
    }
    
    // MARK: - Auto Reconnect
    private func startAutoReconnect() {
        // Disabled: Android app needs to implement wake-up service on ports 8888/8889
        // TODO: Re-enable once Android background service is implemented
        /*
        autoReconnectTimer?.invalidate()
        autoReconnectTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                // Only attempt when no device is connected
                if AppState.shared.device == nil {
                    self.wakeUpLastConnectedDevice()
                }
            }
        }
        autoReconnectTimer?.tolerance = 5.0
        */
    }

    deinit {
        autoReconnectTimer?.invalidate()
    }
}

