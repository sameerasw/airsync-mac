import Foundation
import Network
internal import Combine
import SwiftUI

struct DiscoveredDevice: Identifiable, Equatable, Hashable {
    let deviceId: String
    let name: String
    var ips: Set<String>
    let port: Int
    let type: String
    var lastSeen: Date
    
    var id: String {
        return deviceId
    }
    
    var isActive: Bool {
        return Date().timeIntervalSince(lastSeen) < 15
    }
    
    static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

class UDPDiscoveryManager: ObservableObject {
    static let shared = UDPDiscoveryManager()
    
    @Published var discoveredDevices: [DiscoveredDevice] = []
    
    private var listener: NWListener?
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.airsync.discovery")
    private let broadcastPort: NWEndpoint.Port = 8889
    private var cancellables = Set<AnyCancellable>()
    private var isListening = false
    
    private init() {
        startPruning()
    }
    
    // MARK: - Lifecycle
    
    func start() {
        if !isListening {
            startListening()
            isListening = true
        }
    }
    
    func stop() {
        stopListening()
        isListening = false
    }
    
    // MARK: - Broadcasting
    
    func broadcastPresence() {
        let adapters = WebSocketServer.shared.getAvailableNetworkAdapters()
        guard !adapters.isEmpty else { return }
        
        // knownPeerIPs: List of IPs we have connected to before (e.g. Android on Tailscale)
        let knownPeerIPs = Set(QuickConnectManager.shared.lastConnectedDevices.values.map { $0.ipAddress })
        
        let allIPs = adapters.map { $0.address }
        
        let info = AppState.shared.myDevice
        let port = info?.port ?? Int(Defaults.serverPort)
        let name = info?.name ?? Host.current().localizedName ?? "Mac"
        let uuid = getStableUUID()
        
        // 1. Broadcast Loop
        let payload: [String: Any] = [
            "type": "presence",
            "deviceType": "mac",
            "id": uuid,
            "name": name,
            "ips": allIPs, // Send ALL IPs
            "port": port
        ]
        
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let jsonString = String(data: data, encoding: .utf8) {
            for adapter in adapters {
                sendBroadcast(message: jsonString, sourceIP: adapter.address)
            }
        }
        
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let jsonString = String(data: data, encoding: .utf8) {
            
            for peerIP in knownPeerIPs {
                if allIPs.contains(peerIP) { continue }
                sendUnicast(message: jsonString, targetIP: peerIP)
            }
        }
    }
    
    private func sendBroadcast(message: String, sourceIP: String) {
        let host = NWEndpoint.Host("255.255.255.255")
        let port = broadcastPort
        
        let parameters = NWParameters.udp
        if let localIP = IPv4Address(sourceIP) {
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(localIP.debugDescription), port: 0)
        }
        
        let connection = NWConnection(host: host, port: port, using: parameters)
        
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: message.data(using: .utf8), completion: .contentProcessed({ error in
                    if let error = error {
                        // print("[UDP] Broadcast send error (from \(sourceIP)): \(error)")
                    }
                    connection.cancel()
                }))
            case .failed(_):
                // print("[UDP] Broadcast connection failed (from \(sourceIP)): \(error)")
                connection.cancel()
            default:
                break
            }
        }
        
        connection.start(queue: queue)
    }
    
    private func sendUnicast(message: String, targetIP: String) {
        let host = NWEndpoint.Host(targetIP)
        let port = broadcastPort
        
        // Use default UDP parameters (let OS route)
        let parameters = NWParameters.udp
        
        let connection = NWConnection(host: host, port: port, using: parameters)
        
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: message.data(using: .utf8), completion: .contentProcessed({ error in
                    if let error = error {
                        print("[UDP] Unicast send error (to \(targetIP)): \(error)")
                    }
                    connection.cancel()
                }))
            case .failed(let error):
                print("[UDP] Unicast connection failed (to \(targetIP)): \(error)")
                connection.cancel()
            default:
                break
            }
        }
        
        connection.start(queue: queue)
    }
    
    // MARK: - Listening
    
    private func startListening() {
        do {
            let parameters = NWParameters.udp
            parameters.allowLocalEndpointReuse = true
            
            listener = try NWListener(using: parameters, on: broadcastPort)
            
            listener?.newConnectionHandler = { [weak self] newConnection in
                newConnection.receiveMessage { (data, context, isComplete, error) in
                    if let data = data, !data.isEmpty, let message = String(data: data, encoding: .utf8) {
                        self?.handleMessage(message)
                    }
                    newConnection.cancel()
                }
                newConnection.start(queue: self?.queue ?? .global())
            }
            
            listener?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("[UDP] Listener ready on port \(self.broadcastPort.rawValue)")
                case .failed(let error):
                    print("[UDP] Listener failed: \(error)")
                default:
                    break
                }
            }
            
            listener?.start(queue: queue)
            
            // Start periodic broadcast
            Timer.publish(every: 3, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    guard let self = self, self.isListening else { return }
                    self.broadcastPresence()
                }
                .store(in: &cancellables)
            
        } catch {
            print("[UDP] Failed to create listener: \(error)")
        }
    }
    
    private func stopListening() {
        listener?.cancel()
        listener = nil
        cancellables.removeAll()
    }
    
    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] (data, context, isComplete, error) in
            if let data = data, !data.isEmpty, let message = String(data: data, encoding: .utf8) {
                self?.handleMessage(message)
            }
            if error == nil {
                self?.receive(on: connection)
            }
        }
    }
    
    private func handleMessage(_ message: String) {
        guard let data = message.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String,
              let deviceType = json["deviceType"] as? String,
              deviceType == "android"
        else { return }
        
        let id = json["id"] as? String ?? UUID().uuidString
        
        if type == "bye" {
            DispatchQueue.main.async {
                self.discoveredDevices.removeAll { $0.deviceId == id }
            }
            return
        }
        
        guard type == "presence" else { return }
        
        let name = json["name"] as? String ?? "Unknown Android"
        let port = json["port"] as? Int ?? 0
        
        // Support both "ips" (array) and legacy "ip" (string)
        var incomingIps: Set<String> = []
        if let ipsArray = json["ips"] as? [String] {
            incomingIps = Set(ipsArray)
        } else if let singleIp = json["ip"] as? String {
            incomingIps = [singleIp]
        }
        
        // Filter out unreachable IPs (e.g. Cellular NAT 10.x.x.x)
        let validIps = incomingIps.filter { isValidCandidateIP($0) }
        guard !validIps.isEmpty else { return }
        
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                if let index = self.discoveredDevices.firstIndex(where: { $0.deviceId == id }) {
                    // Merge into existing device
                    var device = self.discoveredDevices[index]
                    device.ips.formUnion(validIps)
                    device.lastSeen = Date()
                    self.discoveredDevices[index] = device
                } else {
                    // New device
                    let device = DiscoveredDevice(
                        deviceId: id,
                        name: name,
                        ips: validIps,
                        port: port,
                        type: deviceType,
                        lastSeen: Date()
                    )
                    self.discoveredDevices.append(device)
                }
            }
        }
    }
    
    /// IP validation
    private func isValidCandidateIP(_ ip: String) -> Bool {
        // 1. Allow Tailscale (100.x.x.x)
        if ip.hasPrefix("100.") { return true }
        
        // 2. Allow Standard Local LAN (192.168.x.x)
        if ip.hasPrefix("192.168.") { return true }
        
        // 3. Allow Local LAN (172.16.x.x - 172.31.x.x)
        if ip.hasPrefix("172.") {
             let parts = ip.split(separator: ".")
             if parts.count > 1, let octet = Int(parts[1]), octet >= 16 && octet <= 31 {
                 return true
             }
        }
        
        // Other
        if ip.hasPrefix("10.") {
            let adapters = WebSocketServer.shared.getAvailableNetworkAdapters()
            let hasTenNet = adapters.contains { $0.address.hasPrefix("10.") }
            return hasTenNet
        }
        
        return false // Block public IPs or unknown ranges
    }
    
    private func startPruning() {
        // More frequent pruning for better UI responsiveness
        Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.pruneStaleDevices()
            }
            .store(in: &cancellables)
    }
    
    private func pruneStaleDevices() {
        let now = Date()
        let oldDevices = discoveredDevices
        
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.6)) {
                self.discoveredDevices.removeAll { now.timeIntervalSince($0.lastSeen) > 30 }
                
                if oldDevices.contains(where: { $0.isActive != (now.timeIntervalSince($0.lastSeen) < 15) }) {
                    self.objectWillChange.send()
                }
            }
        }
    }
    
    // Helper to get a stable ID for this Mac
    private func getStableUUID() -> String {
        let defaults = UserDefaults.standard
        if let uuid = defaults.string(forKey: "device_stable_uuid") {
            return uuid
        }
        let uuid = UUID().uuidString
        defaults.set(uuid, forKey: "device_stable_uuid")
        return uuid
    }
}
