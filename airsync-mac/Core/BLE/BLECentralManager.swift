import Foundation
import CoreBluetooth
import Combine

class BLECentralManager: NSObject, ObservableObject {
    static let shared = BLECentralManager()
    
    private var centralManager: CBCentralManager!
    private var discoveredPeripheral: CBPeripheral?
    
    private var characteristics: [CBUUID: CBCharacteristic] = [:]
    private var chunkBuffers: [CBUUID: [Int: Data]] = [:]
    private var discoveredServiceCount = 0
    private let expectedServiceCount = 4
    
    @Published var connectionStatus: BLEConnectionStatus = .disconnected
    @Published var connectedDeviceName: String? = nil
    struct BLEDiscoveryRecord {
        let peripheral: CBPeripheral
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
        
        let isRegularConnection = AppState.shared.device?.ipAddress != nil && AppState.shared.device?.ipAddress != "BLE"
        guard !isRegularConnection else {
            print("[BLE] Skip scan: Regular connection is active.")
            return
        }
        
        print("[BLE] Starting scan...")
        connectionStatus = .scanning
        
        centralManager.stopScan()
        scanTimer?.invalidate()
        scanTimer = nil
        
        centralManager.scanForPeripherals(withServices: [BLEConstants.serviceSystem], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        
        // Restart scan periodically to avoid stale states
        scanTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            // Skip restart cycle when already connected — nothing to rediscover
            guard self.connectionStatus == .scanning else { return }
            
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
    
    func disconnect() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        isManuallyDisconnected = true
        
        if let peripheral = discoveredPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
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
    
    var discoveredBLEDevices: [DiscoveredDevice] {
        let token = UserDefaults.standard.string(forKey: "bleAuthToken") ?? ""
        if token.isEmpty {
            return []
        }
        
        return discoveredPeripherals.values.map { record in
            DiscoveredDevice(
                deviceId: record.peripheral.identifier.uuidString,
                name: record.peripheral.name ?? "Android Device",
                ips: ["Bluetooth LE"],
                port: 0,
                type: "ble",
                lastSeen: record.lastSeen
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
        centralManager.connect(peripheral, options: [
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
        ])
        
        connectionTimer?.invalidate()
        connectionTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            print("[BLE] Manual connection timed out, cancelling...")
            if let p = self.discoveredPeripheral {
                self.centralManager.cancelPeripheralConnection(p)
            }
            self.discoveredPeripheral = nil
            self.connectingDeviceUUID = nil
            self.connectionStatus = .disconnected
            self.characteristics.removeAll()
            self.discoveredServiceCount = 0
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
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown"
        let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let uuidStr = peripheral.identifier.uuidString
        let isNewDevice = discoveredPeripherals[uuidStr] == nil
        if isNewDevice {
            print("[BLE] Discovered \(name) with RSSI: \(RSSI), Services: \(serviceUUIDs.map { $0.uuidString }.joined(separator: ", "))")
        }
        
        DispatchQueue.main.async {
            self.discoveredPeripherals[uuidStr] = BLEDiscoveryRecord(peripheral: peripheral, lastSeen: Date())
        }
        
        // Auto connect if enabled and not manually disconnected
        if AppState.shared.isBLEAutoConnectEnabled && !isManuallyDisconnected {
            let isWifiConnected = AppState.shared.device != nil && AppState.shared.device?.ipAddress != "BLE" && AppState.shared.device?.ipAddress != "Bluetooth LE"
            if isWifiConnected {
                print("[BLE] Regular Wi-Fi connection is active — skipping auto-connect to BLE")
                return
            }
            
            let token = UserDefaults.standard.string(forKey: "bleAuthToken") ?? ""
            if token.isEmpty {
                return
            }
            
            discoveredPeripheral = peripheral
            centralManager.stopScan()
            scanTimer?.invalidate()
            scanTimer = nil
            
            print("[BLE] Attempting auto-connect to \(name)...")
            centralManager.connect(peripheral, options: [
                CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
            ])
            
            // CoreBluetooth connect() has no timeout — it can hang forever with stale pairing data.
            connectionTimer?.invalidate()
            connectionTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                print("[BLE] Connection timed out, cancelling and retrying...")
                if let p = self.discoveredPeripheral {
                    self.centralManager.cancelPeripheralConnection(p)
                }
                self.discoveredPeripheral = nil
                self.connectionStatus = .disconnected
                self.characteristics.removeAll()
                self.discoveredServiceCount = 0
                
                if AppState.shared.isBLEAutoConnectEnabled && !self.isManuallyDisconnected {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.startScanning()
                    }
                }
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionTimer?.invalidate()
        connectionTimer = nil
        connectingDeviceUUID = nil
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
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }
        print("[BLE] Discovered \(chars.count) characteristics for service \(service.uuid)")
        for char in chars {
            characteristics[char.uuid] = char
            
            if char.properties.contains(.notify) {
                print("[BLE] Subscribing to \(char.uuid)")
                peripheral.setNotifyValue(true, for: char)
            }
        }
        
        discoveredServiceCount += 1
        print("[BLE] Services discovered: \(discoveredServiceCount)/\(expectedServiceCount)")
        
        // Only attempt auth after ALL services are discovered
        if discoveredServiceCount >= expectedServiceCount {
            if characteristics[BLEConstants.charAuthToken] != nil {
                print("[BLE] All services discovered, attempting authentication...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.attemptAuthentication()
                }
            }
        }
    }
    
    private func attemptAuthentication() {
        guard connectionStatus == .connected else { return }
        let token = UserDefaults.standard.string(forKey: "bleAuthToken") ?? ""
        if !token.isEmpty, let data = token.data(using: .utf8) {
            print("[BLE] Attempting authentication...")
            write(characteristicUUID: BLEConstants.charAuthToken, data: data)
        } else {
            print("[BLE] Auth token is empty, skipping auth and disconnecting because they have never paired")
            disconnect()
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
