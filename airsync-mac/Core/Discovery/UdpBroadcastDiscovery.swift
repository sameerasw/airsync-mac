import Foundation
import Network
import Combine
import SwiftUI

enum DiscoverySource: String, Codable, CaseIterable {
    case mdns
    case udp
}

struct DiscoveredDevice: Identifiable, Equatable, Hashable {
    let deviceId: String
    let name: String
    var ips: Set<String>
    let port: Int
    let type: String
    var lastSeen: Date
    var discoverySource: DiscoverySource = .udp
    
    var id: String {
        return deviceId
    }
    
    var isActive: Bool {
        if discoverySource == .mdns {
            return true
        }
        return Date().timeIntervalSince(lastSeen) < 20
    }
    
    static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

class UdpBroadcastDiscovery: ObservableObject {
    @Published var discoveredDevices: [DiscoveredDevice] = []
    
    private var listener: NWListener?
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.airsync.discovery")
    private let broadcastPort: NWEndpoint.Port = 8889
    private var cancellables = Set<AnyCancellable>()
    private var isListening = false
    private var lastBroadcastTime: Date = .distantPast
    private var networkChangePendingWork: DispatchWorkItem?
    
    init() {
        // Init logic only
    }
    
    private var networkMonitor: NWPathMonitor?
    
    // MARK: - Lifecycle
    
    func start() {
        if !isListening {
            startListening()
            startPruning()
            startMonitoring()
            isListening = true
            
            // Immediate broadcast on start
            broadcastBurst()
        }
    }
    
    func stop() {
        stopListening()
        stopMonitoring()
        isListening = false
    }
    
    // MARK: - Smart Triggers
    
    private func startMonitoring() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSystemSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSystemWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        
        setupNetworkPathMonitor()
    }
    
    private func setupNetworkPathMonitor() {
        networkMonitor = NWPathMonitor()
        networkMonitor?.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            guard path.status == .satisfied else { return }

            self.networkChangePendingWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                guard Date().timeIntervalSince(self.lastBroadcastTime) >= 2.0 else { return }
                print("[Discovery] Network change detected – broadcasting presence")
                self.broadcastBurst()
            }
            self.networkChangePendingWork = work
            queue.asyncAfter(deadline: .now() + 2.0, execute: work)
        }
        networkMonitor?.start(queue: queue)
    }
    
    private func stopMonitoring() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        networkMonitor?.cancel()
        networkMonitor = nil
    }
    
    @objc private func handleSystemSleep() {
        print("[Discovery] System going to sleep – suspending discovery network triggers")
        networkChangePendingWork?.cancel()
        networkMonitor?.cancel()
        networkMonitor = nil
        
        stopListening()
    }
    
    @objc private func handleSystemWake() {
        print("[Discovery] System wake detected – resuming discovery network triggers")
        setupNetworkPathMonitor()
        if isListening {
            startListening()
        }
        broadcastBurst()
    }
    
    // MARK: - Broadcasting
    
    func broadcastBurst() {
        print("[Discovery] Triggering broadcast burst")
        lastBroadcastTime = Date()
        
        for i in 0..<3 {
            DispatchQueue.global().asyncAfter(deadline: .now() + (Double(i) * 0.1)) { [weak self] in
                self?.broadcastPresence()
            }
        }
    }
    
    func broadcastPresence() {
        let adapters = WebSocketServer.shared.getAvailableNetworkAdapters()
        guard !adapters.isEmpty else { return }
        
        let knownPeerIPs = Set(QuickConnectManager.shared.lastConnectedDevices.values.map { $0.ipAddress })
        let allIPs = adapters.map { $0.address }
        
        let info = AppState.shared.myDevice
        let port = info?.port ?? Int(Defaults.serverPort)
        let name = info?.name ?? Host.current().localizedName ?? "Mac"
        let uuid = getStableUUID()
        
        let payload: [String: Any] = [
            "type": "presence",
            "deviceType": "mac",
            "id": uuid,
            "name": name,
            "ips": allIPs,
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
                guard DiscoveryManager.shared.isIPOnLocalNetwork(peerIP) else { continue }
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
                connection.send(content: message.data(using: .utf8), completion: .contentProcessed({ _ in
                    connection.cancel()
                }))
            case .failed(_):
                connection.cancel()
            case .cancelled:
                break
            default:
                break
            }
        }
        
        connection.start(queue: queue)
    }
    
    private func sendUnicast(message: String, targetIP: String) {
        let host = NWEndpoint.Host(targetIP)
        let port = broadcastPort
        let parameters = NWParameters.udp
        let connection = NWConnection(host: host, port: port, using: parameters)
        
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: message.data(using: .utf8), completion: .contentProcessed({ _ in
                    connection.cancel()
                }))
            case .failed(_):
                connection.cancel()
            case .cancelled:
                break
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
            
            Timer.publish(every: 10, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    guard let self = self, self.isListening else { return }
                    let isWifiConnected = AppState.shared.device != nil &&
                                         AppState.shared.device?.ipAddress != "BLE" &&
                                         AppState.shared.device?.ipAddress != "Bluetooth LE"
                    guard !isWifiConnected else { return }
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
        
        var incomingIps: Set<String> = []
        if let ipsArray = json["ips"] as? [String] {
            incomingIps = Set(ipsArray)
        } else if let singleIp = json["ip"] as? String {
            incomingIps = [singleIp]
        }
        
        let validIps = incomingIps.filter { isValidCandidateIP($0) }
        guard !validIps.isEmpty else { return }
        
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                if let index = self.discoveredDevices.firstIndex(where: { $0.deviceId == id }) {
                    var device = self.discoveredDevices[index]
                    device.ips.formUnion(validIps)
                    device.lastSeen = Date()
                    device.discoverySource = .udp
                    self.discoveredDevices[index] = device
                } else {
                    let device = DiscoveredDevice(
                        deviceId: id,
                        name: name,
                        ips: validIps,
                        port: port,
                        type: deviceType,
                        lastSeen: Date(),
                        discoverySource: .udp
                    )
                    self.discoveredDevices.append(device)
                }
            }
        }
    }
    
    private func isValidCandidateIP(_ ip: String) -> Bool {
        if ip.hasPrefix("100.") { return true }
        if ip.hasPrefix("192.168.") { return true }
        if ip.hasPrefix("172.") {
             let parts = ip.split(separator: ".")
             if parts.count > 1, let octet = Int(parts[1]), octet >= 16 && octet <= 31 {
                 return true
             }
        }
        
        if ip.hasPrefix("10.") {
            let adapters = WebSocketServer.shared.getAvailableNetworkAdapters()
            let hasTenNet = adapters.contains { $0.address.hasPrefix("10.") }
            return hasTenNet
        }
        
        return false
    }
    
    private func startPruning() {
        Timer.publish(every: 10.0, on: .main, in: .default)
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
                let initialCount = self.discoveredDevices.count
                self.discoveredDevices = self.discoveredDevices.filter {
                    now.timeIntervalSince($0.lastSeen) <= 35
                }
                
                let activeStatusChanged = self.discoveredDevices.contains(where: { device in
                    let wasActive = oldDevices.first(where: { $0.id == device.id })?.isActive ?? false
                    let isActive = device.isActive
                    return wasActive != isActive
                })
                if activeStatusChanged {
                    self.objectWillChange.send()
                }
            }
        }
    }
    
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
