import Foundation
import CoreBluetooth
import Combine

class BLECentralManager: NSObject, ObservableObject {
    static let shared = BLECentralManager()
    
    private var centralManager: CBCentralManager!
    private var discoveredPeripheral: CBPeripheral?
    
    private var characteristics: [CBUUID: CBCharacteristic] = [:]
    private var chunkBuffers: [CBUUID: [Int: Data]] = [:]
    private var serviceCharacteristicsDiscoveryStarted = Set<CBUUID>()
    private var discoveredServiceUUIDs = Set<CBUUID>()
    private var isAuthTokenWritten = false
    private var discoveredServiceCount = 0
    private let expectedServiceCount = 4
    
    @Published var connectionStatus: BLEConnectionStatus = .disconnected
    @Published var connectedDeviceName: String? = nil
    struct BLEDiscoveryRecord {
        let peripheral: CBPeripheral
        var name: String
        var lastSeen: Date
    }
    
    @Published var discoveredPeripherals: [String: BLEDiscoveryRecord] = [:]
    @Published var connectingDeviceUUID: String? = nil
    
    var isManuallyDisconnected = false
    
    var isConnected: Bool {
        connectionStatus != .disconnected && connectionStatus != .scanning
    }

    var isAuthenticated: Bool {
        connectionStatus == .authenticated
    }
    
    enum BLEConnectionStatus: Equatable {
        case disconnected
        case scanning
        case connected
        case authenticated
    }
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    private var scanTimer: Timer?
    private var connectionTimer: Timer?
    private var watchdogTimer: Timer?
    
    func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        let isRegularConnectionActive = AppState.shared.device != nil && AppState.shared.device?.ipAddress != "BLE"
        guard !isRegularConnectionActive else {
            print("[BLE] Skipping scan: active regular connection exists")
            return
        }
        guard connectionStatus == .disconnected || connectionStatus == .scanning else { return }
        print("[BLE] Starting scan...")
        connectionStatus = .scanning
        
        centralManager.stopScan()
        scanTimer?.invalidate()
        scanTimer = nil
        
        centralManager.scanForPeripherals(withServices: [BLEConstants.serviceSystem], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        
        // Restart scan periodically to avoid stale states
        scanTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let regularActive = AppState.shared.device != nil && AppState.shared.device?.ipAddress != "BLE"
            if regularActive {
                print("[BLE] Stopping scan: regular connection active")
                self.stopScanning()
                return
            }
            
            guard self.connectionStatus == .scanning || self.connectionStatus == .disconnected else { return }
//             print("[BLE] Restarting scan...")
            
            // Prune stale devices older than 25 seconds
            let now = Date()
            let staleUUIDs = self.discoveredPeripherals.filter { now.timeIntervalSince($1.lastSeen) > 15.0 }.map { $0.key }
            for uuid in staleUUIDs {
                self.discoveredPeripherals.removeValue(forKey: uuid)
            }
            
            self.centralManager.stopScan()
            self.centralManager.scanForPeripherals(withServices: [BLEConstants.serviceSystem], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
    }
    
    func stopScanning() {
        scanTimer?.invalidate()
        scanTimer = nil
        centralManager.stopScan()
        if connectionStatus == .scanning {
            connectionStatus = .disconnected
        }
    }
    
    private func prepareForConnection() {
        characteristics.removeAll()
        chunkBuffers.removeAll()
        serviceCharacteristicsDiscoveryStarted.removeAll()
        discoveredServiceUUIDs.removeAll()
        isAuthTokenWritten = false
        discoveredServiceCount = 0
        connectionTimer?.invalidate()
        connectionTimer = nil
    }
    
    func disconnect(isManual: Bool = false) {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        if isManual {
            isManuallyDisconnected = true
        }
        
        if let peripheral = discoveredPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        discoveredPeripheral = nil
        connectionStatus = .disconnected
        connectingDeviceUUID = nil
        discoveredPeripherals.removeAll()
        
        // Resume scanning to immediately show nearby devices in the unpaired list
        if AppState.shared.isBLEEnabled {
            startScanning()
        }
    }
    
    func write(characteristicUUID: CBUUID, data: Data) {
        resetWatchdog()
        guard let peripheral = discoveredPeripheral, let char = characteristics[characteristicUUID] else { return }
        peripheral.writeValue(data, for: char, type: .withoutResponse)
    }
    
    func writeChunked(characteristicUUID: CBUUID, payload: String) {
        let mtu = discoveredPeripheral?.maximumWriteValueLength(for: .withoutResponse) ?? 20
        let chunks = BLEChunkUtil.splitIntoChunks(payload: payload, mtu: mtu)
        for chunk in chunks {
            write(characteristicUUID: characteristicUUID, data: chunk)
        }
    }
    
    private func getStoredDeviceName() -> String? {
        if let name = UserDefaults.standard.string(forKey: "bleDeviceName"), !name.isEmpty {
            return name
        }
        if let device = QuickConnectManager.shared.lastConnectedDevices.values.first {
            return device.name
        }
        return nil
    }
    
    var discoveredBLEDevices: [DiscoveredDevice] {
        let token = UserDefaults.standard.string(forKey: "bleAuthToken") ?? ""
        if token.isEmpty {
            return []
        }
        
        let fallbackName = getStoredDeviceName() ?? "Android Device"
        
        return discoveredPeripherals.values.map { record in
            var displayName = record.name
            if displayName == "Unknown" || displayName == "Android Device" {
                displayName = record.peripheral.name ?? fallbackName
            }
            if displayName.hasPrefix("AirSync-") {
                displayName = String(displayName.dropFirst(8))
            }
            
            let udpDevice = UDPDiscoveryManager.shared.discoveredDevices.first(where: { $0.name == displayName })
            return DiscoveredDevice(
                deviceId: record.peripheral.identifier.uuidString,
                name: displayName,
                ips: ["Bluetooth LE"],
                port: 0,
                type: "ble",
                lastSeen: record.lastSeen,
                autoConnect: udpDevice?.autoConnect ?? true,
                bleAutoConnect: udpDevice?.bleAutoConnect ?? true
            )
        }
    }
    
    func connectManually(toUuid uuidStr: String) {
        let token = UserDefaults.standard.string(forKey: "bleAuthToken") ?? ""
        if token.isEmpty {
            print("[BLE] Cannot connect manually: Devices have never been paired via QR/Wi-Fi before.")
            return
        }
        
        guard let record = discoveredPeripherals[uuidStr] else { return }
        let peripheral = record.peripheral
        print("[BLE] Manual connection requested for \(peripheral.name ?? "Unknown")")
        
        isManuallyDisconnected = false
        discoveredPeripheral = peripheral
        centralManager.stopScan()
        scanTimer?.invalidate()
        scanTimer = nil
        
        connectingDeviceUUID = uuidStr
        connectionStatus = .scanning
        prepareForConnection()
        centralManager.connect(peripheral, options: [
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
        ])
        
        connectionTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            print("[BLE] Manual connection timed out, cancelling...")
            if let p = self.discoveredPeripheral {
                self.centralManager.cancelPeripheralConnection(p)
            }
        }
    }
    
    private func resetWatchdog() {
        DispatchQueue.main.async {
            self.watchdogTimer?.invalidate()
            self.watchdogTimer = Timer.scheduledTimer(withTimeInterval: 25.0, repeats: false) { [weak self] _ in
                print("[BLE] Heartbeat timeout (25s), disconnecting...")
                self?.disconnect()
            }
        }
    }
}

extension BLECentralManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            if AppState.shared.isBLEEnabled {
                print("[BLE] Bluetooth powered on, starting scan")
                startScanning()
            }
        } else {
            print("[BLE] Bluetooth state changed: \(central.state.rawValue)")
            connectionStatus = .disconnected
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // Try to get name from advertisementData, peripheral, or stored name
        var name = "Unknown"
        if let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String, !advName.isEmpty {
            name = advName
        } else if let pName = peripheral.name, !pName.isEmpty {
            name = pName
        } else if let storedName = getStoredDeviceName(), !storedName.isEmpty {
            name = storedName
        }
        
        if name.hasPrefix("AirSync-") {
            name = String(name.dropFirst(8))
        }
        
        let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let uuidStr = peripheral.identifier.uuidString
        let isNewDevice = discoveredPeripherals[uuidStr] == nil
        if isNewDevice {
            print("[BLE] Discovered \(name) with RSSI: \(RSSI), Services: \(serviceUUIDs.map { $0.uuidString }.joined(separator: ", "))")
        }
        
        DispatchQueue.main.async {
            self.discoveredPeripherals[uuidStr] = BLEDiscoveryRecord(
                peripheral: peripheral,
                name: name,
                lastSeen: Date()
            )
        }
        
        // Auto connect if enabled, not manually disconnected, and no active regular connection exists
        let isRegularConnectionActive = AppState.shared.device != nil && AppState.shared.device?.ipAddress != "BLE"
        if AppState.shared.isBLEAutoConnectEnabled && !isManuallyDisconnected && !isRegularConnectionActive {
            // Guard: check if we have a UDP discovered device record and if it disables BLE auto-connect
            if let match = UDPDiscoveryManager.shared.discoveredDevices.first(where: { $0.name == name }) {
                guard match.bleAutoConnect else {
                    print("[BLE] Skipping BLE auto-connect because bleAutoConnect is disabled for \(name)")
                    return
                }
            }
            
            // Guard: must not be already connecting or connected
            guard connectionTimer == nil && connectionStatus != .connected && connectionStatus != .authenticated else { return }
            
            let token = UserDefaults.standard.string(forKey: "bleAuthToken") ?? ""
            if token.isEmpty {
                return
            }
            
            // Check if already discovered via UDP
            let isDiscoveredViaUDP = UDPDiscoveryManager.shared.discoveredDevices.contains { $0.name == name }
            guard !isDiscoveredViaUDP else {
                print("[BLE] Prioritizing Wi-Fi/Hotspot: \(name) is discovered via UDP, skipping BLE auto-connect")
                return
            }
            
            // If local network is active, delay BLE auto-connect by 3 seconds to give Wi-Fi/Hotspot priority
            let adapters = WebSocketServer.shared.getAvailableNetworkAdapters()
            if !adapters.isEmpty {
                print("[BLE] Local network active. Delaying BLE auto-connect by 3.0s to prioritize Wi-Fi/Hotspot...")
                
                connectionTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
                    guard let self = self else { return }
                    
                    // Re-verify all guards after 3 seconds
                    let isRegActive = AppState.shared.device != nil && AppState.shared.device?.ipAddress != "BLE"
                    let regDiscovered = UDPDiscoveryManager.shared.discoveredDevices.contains { $0.name == name }
                    guard !isRegActive && !regDiscovered && !self.isManuallyDisconnected else {
                        print("[BLE] Wi-Fi/Hotspot connection active or discovered, cancelling delayed BLE auto-connect")
                        self.connectionTimer = nil
                        return
                    }
                    
                    self.performBLEAutoConnect(peripheral: peripheral, name: name)
                }
            } else {
                // No local network active — immediately connect via BLE as last resort!
                print("[BLE] No local network active. Connecting via BLE immediately as last resort...")
                performBLEAutoConnect(peripheral: peripheral, name: name)
            }
        }
    }
    
    private func performBLEAutoConnect(peripheral: CBPeripheral, name: String) {
        discoveredPeripheral = peripheral
        centralManager.stopScan()
        scanTimer?.invalidate()
        scanTimer = nil
        
        print("[BLE] Attempting auto-connect to \(name)...")
        prepareForConnection()
        centralManager.connect(peripheral, options: [
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
        ])
        
        connectionTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            print("[BLE] Connection timed out, cancelling...")
            if let p = self.discoveredPeripheral {
                self.centralManager.cancelPeripheralConnection(p)
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionTimer?.invalidate()
        connectionTimer = nil
        connectingDeviceUUID = nil
        discoveredServiceCount = 0
        let name = peripheral.name ?? "Unknown Device"
        let maxWrite = peripheral.maximumWriteValueLength(for: .withoutResponse)
        print("[BLE] Connected to \(name), Max Write Length: \(maxWrite)")
        connectionStatus = .connected
        peripheral.delegate = self
        peripheral.discoverServices([BLEConstants.serviceSystem, BLEConstants.serviceNotifications, BLEConstants.serviceMedia, BLEConstants.serviceClipboard])
        
        resetWatchdog()
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionTimer?.invalidate()
        connectionTimer = nil
        connectingDeviceUUID = nil
        print("[BLE] Failed to connect: \(error?.localizedDescription ?? "Unknown error")")
        connectionStatus = .disconnected
        discoveredPeripheral = nil
        characteristics.removeAll()
        chunkBuffers.removeAll()
        serviceCharacteristicsDiscoveryStarted.removeAll()
        discoveredServiceUUIDs.removeAll()
        isAuthTokenWritten = false
        discoveredServiceCount = 0
        
        // Retry scanning after a delay
        if AppState.shared.isBLEAutoConnectEnabled && !isManuallyDisconnected {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.startScanning()
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectionTimer?.invalidate()
        connectionTimer = nil
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        
        print("[BLE] Disconnected: \(error?.localizedDescription ?? "clean")")
        connectionStatus = .disconnected
        connectingDeviceUUID = nil
        discoveredPeripheral = nil
        connectedDeviceName = nil
        characteristics.removeAll()
        chunkBuffers.removeAll()
        serviceCharacteristicsDiscoveryStarted.removeAll()
        discoveredServiceUUIDs.removeAll()
        isAuthTokenWritten = false
        discoveredServiceCount = 0
        
        if AppState.shared.isBLEAutoConnectEnabled && !isManuallyDisconnected {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.startScanning()
            }
        }
    }
}

extension BLECentralManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else {
            print("[BLE] Service discovery completed with empty services or error: \(error?.localizedDescription ?? "nil")")
            return
        }
        let targetServices = [
            BLEConstants.serviceSystem,
            BLEConstants.serviceNotifications,
            BLEConstants.serviceMedia,
            BLEConstants.serviceClipboard
        ]
        for service in services {
            if targetServices.contains(service.uuid) {
                if !serviceCharacteristicsDiscoveryStarted.contains(service.uuid) {
                    serviceCharacteristicsDiscoveryStarted.insert(service.uuid)
                    print("[BLE] Discovering characteristics for target service: \(service.uuid)")
                    peripheral.discoverCharacteristics(nil, for: service)
                } else {
                    print("[BLE] Skipping characteristics discovery for already-started service: \(service.uuid)")
                }
            } else {
                print("[BLE] Skipping discovery for non-target service: \(service.uuid)")
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }
        print("[BLE] Discovered \(chars.count) characteristics for service \(service.uuid)")
        for char in chars {
            characteristics[char.uuid] = char
            
            if char.properties.contains(.notify) {
                if !char.isNotifying {
                    print("[BLE] Subscribing to \(char.uuid)")
                    peripheral.setNotifyValue(true, for: char)
                } else {
                    print("[BLE] Already subscribed to notify for \(char.uuid)")
                }
            }
        }
        
        if !discoveredServiceUUIDs.contains(service.uuid) {
            discoveredServiceUUIDs.insert(service.uuid)
            discoveredServiceCount = discoveredServiceUUIDs.count
            print("[BLE] Service characteristics successfully discovered: \(service.uuid) (\(discoveredServiceCount)/\(expectedServiceCount))")
        }
        
        // Only attempt auth after ALL target services are discovered
        let targetServices = [
            BLEConstants.serviceSystem,
            BLEConstants.serviceNotifications,
            BLEConstants.serviceMedia,
            BLEConstants.serviceClipboard
        ]
        let allDiscovered = targetServices.allSatisfy { discoveredServiceUUIDs.contains($0) }
        if allDiscovered {
            if characteristics[BLEConstants.charAuthToken] != nil {
                print("[BLE] All target services discovered, attempting authentication...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.attemptAuthentication()
                }
            }
        }
    }
    
    private func attemptAuthentication() {
        guard connectionStatus == .connected else {
            print("[BLE] Skipping authentication attempt: connectionStatus is \(connectionStatus)")
            return
        }
        guard !isAuthTokenWritten else {
            print("[BLE] Auth token already written, skipping duplicate write.")
            return
        }
        let token = UserDefaults.standard.string(forKey: "bleAuthToken") ?? ""
        print("[BLE] Found stored auth token for authentication: length=\(token.count), tokenIsEmpty=\(token.isEmpty)")
        if !token.isEmpty, let data = token.data(using: .utf8) {
            if let peripheral = discoveredPeripheral, let char = characteristics[BLEConstants.charAuthToken] {
                print("[BLE] Writing auth token data (\(data.count) bytes) to characteristic \(char.uuid) withResponse")
                isAuthTokenWritten = true
                peripheral.writeValue(data, for: char, type: .withResponse)
            } else {
                print("[BLE] Failed to write auth token: peripheral is \(discoveredPeripheral == nil ? "nil" : "non-nil"), char is \(characteristics[BLEConstants.charAuthToken] == nil ? "nil" : "non-nil")")
            }
        } else {
            print("[BLE] Auth token is empty, skipping auth and disconnecting because they have never paired")
            disconnect()
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("[BLE] Error writing value for \(characteristic.uuid.uuidString): \(error.localizedDescription) (Raw error: \(error))")
        } else {
            print("[BLE] Successfully wrote value for characteristic: \(characteristic.uuid.uuidString)")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("[BLE] Error updating notification state for \(characteristic.uuid.uuidString): \(error.localizedDescription) (Raw error: \(error))")
        } else {
            print("[BLE] Notification state updated for \(characteristic.uuid.uuidString): isNotifying=\(characteristic.isNotifying)")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        resetWatchdog()
        guard let data = characteristic.value else { return }
        
        switch characteristic.uuid {
        case BLEConstants.charAuthResult:
            if data.first == BLEConstants.authSuccess {
                print("[BLE] Auth Success!")
                connectionStatus = .authenticated
                connectedDeviceName = discoveredPeripheral?.name ?? "Android Device"
                
                // Immediately notify Android of Mac status
                WebSocketServer.shared.sendMacStatusOverBLE()
                
                // Also trigger a full fetch (which includes media info)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    MacInfoSyncManager.shared.fetch()
                }
            } else {
                print("[BLE] Auth Failed!")
                connectionStatus = .connected // Revert to connected but not auth
            }
        case BLEConstants.charBatteryLevel:
            let level = Int(data.first ?? 0)
            print("[BLE] Received Android Battery: \(level)%")
            DispatchQueue.main.async {
                if AppState.shared.status == nil {
                    AppState.shared.status = DeviceStatus(battery: DeviceStatus.Battery(level: level, isCharging: false), isPaired: true, music: nil)
                } else {
                    AppState.shared.status?.battery.level = level
                }
            }
        case BLEConstants.charNotificationData, BLEConstants.charMediaState, BLEConstants.charClipboardDataNotify, BLEConstants.charDeviceName, BLEConstants.charNotificationDismissNotify, BLEConstants.charMacControl:
            handleChunkedUpdate(uuid: characteristic.uuid, data: data)
        default:
            break
        }
    }
    
    private func handleChunkedUpdate(uuid: CBUUID, data: Data) {
        guard let (current, total) = BLEChunkUtil.parseHeader(from: data) else { return }
        let payload = BLEChunkUtil.getPayload(from: data)
        
        var buffer = chunkBuffers[uuid] ?? [:]
        buffer[current] = payload
        chunkBuffers[uuid] = buffer
        
        if buffer.count == total {
            let completePayload = BLEChunkUtil.reassemble(chunks: buffer)
            print("[BLE] Received complete chunked payload for \(uuid)")
            chunkBuffers.removeValue(forKey: uuid)
            
            // Route to BLETransportBridge
            BLETransportBridge.shared.handleIncoming(uuid: uuid, payload: completePayload)
        }
    }
}
