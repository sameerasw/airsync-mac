//
//  BluetoothManager.swift
//  airsync-mac
//
//  Bluetooth device discovery and connection management
//  Supports both Central (scanning) and Peripheral (advertising) modes
//  Includes 3-option pairing code verification
//

import Foundation
import CoreBluetooth
internal import Combine

class BluetoothManager: NSObject, ObservableObject {
    static let shared = BluetoothManager()
    
    @Published var isBluetoothEnabled = false
    @Published var isScanning = false
    @Published var isAdvertising = false
    @Published var discoveredDevices: [DiscoveredDevice] = []
    @Published var connectedDevice: DiscoveredDevice?
    @Published var connectionState: ConnectionState = .disconnected
    
    // Pairing state
    @Published var pairingState: PairingState = .idle
    
    // Saved paired device
    @Published var pairedDevice: PairedDeviceInfo?
    @Published var autoConnectEnabled: Bool = true
    
    private var centralManager: CBCentralManager?
    private var peripheralManager: CBPeripheralManager?
    private var connectedPeripheral: CBPeripheral?
    private var pendingPairingDevice: CBPeripheral?
    private var pairingTimeoutTask: DispatchWorkItem?
    private let pairingTimeoutSeconds: TimeInterval = 30
    
    // Pairing code
    private var currentPairingCode: String?
    private var shouldSendPairingRequestOnServicesDiscovered = false
    
    // Track our GATT service and characteristics for peripheral mode
    private var airSyncService: CBMutableService?
    private var commandCharacteristic: CBMutableCharacteristic?
    private var dataTransferCharacteristic: CBMutableCharacteristic?
    private var subscribedCentrals: [CBCentral] = []
    
    // AirSync service UUID - must match Android side
    private let airSyncServiceUUID = CBUUID(string: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")
    
    // Characteristic UUIDs
    private let deviceInfoCharUUID = CBUUID(string: "A1B2C3D4-E5F6-7890-ABCD-EF1234567891")
    private let dataTransferCharUUID = CBUUID(string: "A1B2C3D4-E5F6-7890-ABCD-EF1234567892")
    private let commandCharUUID = CBUUID(string: "A1B2C3D4-E5F6-7890-ABCD-EF1234567893")
    private let notificationCharUUID = CBUUID(string: "A1B2C3D4-E5F6-7890-ABCD-EF1234567894")
    
    // UserDefaults keys
    private let pairedDeviceAddressKey = "pairedBluetoothDeviceAddress"
    private let pairedDeviceNameKey = "pairedBluetoothDeviceName"
    private let autoConnectKey = "bluetoothAutoConnect"
    
    enum ConnectionState: Equatable {
        case disconnected
        case scanning
        case connecting
        case connected
        case failed(String)
    }
    
    enum PairingState: Equatable {
        case idle
        case waitingForConfirmation(String) // We sent a request, waiting for peer to confirm
        case confirmationRequired(String)   // We received a request, user needs to confirm
        case success
        case failed(String)
    }
    
    struct DiscoveredDevice: Identifiable, Equatable {
        let id: UUID
        let name: String
        let rssi: Int
        let peripheral: CBPeripheral
        var isAirSyncDevice: Bool = false
        
        static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
            lhs.id == rhs.id
        }
    }
    
    struct PairedDeviceInfo: Codable {
        let address: String
        let name: String
        let pairedAt: Date
    }
    
    private override init() {
        super.init()
        loadPairedDevice()
        autoConnectEnabled = UserDefaults.standard.bool(forKey: autoConnectKey)
        if UserDefaults.standard.object(forKey: autoConnectKey) == nil {
            autoConnectEnabled = true
        }
    }
    
    func initialize() {
        guard centralManager == nil else { return }
        centralManager = CBCentralManager(delegate: self, queue: nil)
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        print("[Bluetooth] Initialized CBCentralManager and CBPeripheralManager")
    }
    
    // MARK: - Scanning
    
    func startScanning() {
        guard let central = centralManager, central.state == .poweredOn else {
            print("[Bluetooth] Cannot scan - Bluetooth not ready")
            return
        }
        
        discoveredDevices.removeAll()
        isScanning = true
        connectionState = .scanning
        
        // Scan for AirSync devices specifically
        central.scanForPeripherals(withServices: [airSyncServiceUUID], options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
        
        print("[Bluetooth] Started scanning for AirSync devices")
        
        // Auto-stop after 30 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.stopScanning()
        }
    }
    
    func stopScanning() {
        centralManager?.stopScan()
        isScanning = false
        if case .scanning = connectionState {
            connectionState = .disconnected
        }
        print("[Bluetooth] Stopped scanning")
    }
    
    // MARK: - Advertising
    
    func startAdvertising() {
        guard let peripheral = peripheralManager, peripheral.state == .poweredOn else {
            print("[Bluetooth] Cannot advertise - Bluetooth not ready")
            return
        }
        
        // Create AirSync service
        let service = CBMutableService(type: airSyncServiceUUID, primary: true)
        
        let deviceInfoChar = CBMutableCharacteristic(
            type: deviceInfoCharUUID,
            properties: [.read],
            value: createDeviceInfoData(),
            permissions: [.readable]
        )
        
        let dataTransferChar = CBMutableCharacteristic(
            type: dataTransferCharUUID,
            properties: [.read, .write, .writeWithoutResponse, .notify],
            value: nil,
            permissions: [.readable, .writeable]
        )
        
        let commandChar = CBMutableCharacteristic(
            type: commandCharUUID,
            properties: [.write, .writeWithoutResponse, .notify],
            value: nil,
            permissions: [.writeable, .readable]
        )
        
        let notificationChar = CBMutableCharacteristic(
            type: notificationCharUUID,
            properties: [.notify, .indicate],
            value: nil,
            permissions: [.readable]
        )
        
        service.characteristics = [deviceInfoChar, dataTransferChar, commandChar, notificationChar]
        
        // Store references for later use
        airSyncService = service
        commandCharacteristic = commandChar
        dataTransferCharacteristic = dataTransferChar
        
        peripheral.add(service)
        
        let advertisementData: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [airSyncServiceUUID],
            CBAdvertisementDataLocalNameKey: Host.current().localizedName ?? "AirSync Mac"
        ]
        
        peripheral.startAdvertising(advertisementData)
        isAdvertising = true
        print("[Bluetooth] Started advertising as '\(Host.current().localizedName ?? "AirSync Mac")'")
    }
    
    func stopAdvertising() {
        peripheralManager?.stopAdvertising()
        peripheralManager?.removeAllServices()
        airSyncService = nil
        commandCharacteristic = nil
        dataTransferCharacteristic = nil
        subscribedCentrals.removeAll()
        isAdvertising = false
        print("[Bluetooth] Stopped advertising")
    }
    
    // MARK: - Pairing
    
    func initiatePairing(with device: DiscoveredDevice) {
        pendingPairingDevice = device.peripheral
        
        // Generate 6-digit code
        let code = String(format: "%06d", Int.random(in: 0...999999))
        currentPairingCode = code
        
        pairingState = .waitingForConfirmation(code)
        connectionState = .connecting
        
        print("[Bluetooth] 🔐 Pairing initiated - generated code: \(code)")
        startPairingTimeout()
        
        // Check if already connected and ready
        if device.peripheral.state == .connected {
            print("[Bluetooth] Device already connected, checking services...")
            
            // Check if we already have the command characteristic
            if let services = device.peripheral.services,
               let service = services.first(where: { $0.uuid == airSyncServiceUUID }),
               let chars = service.characteristics,
               chars.contains(where: { $0.uuid == commandCharUUID }) {
                
                print("[Bluetooth] ⚡️ Services ready, sending pairing request immediately")
                shouldSendPairingRequestOnServicesDiscovered = false
                
                // Ensure connectedPeripheral is set so sendDataToConnectedDevices works
                connectedPeripheral = device.peripheral
                sendPairingRequest(code)
                return
            }
        }
        
        shouldSendPairingRequestOnServicesDiscovered = true
        centralManager?.connect(device.peripheral, options: nil)
    }
    
    func acceptPairing() {
        print("[Bluetooth] ✅ User accepted pairing")
        sendPairingAccepted()
        completePairing()
    }
    
    func rejectPairing() {
        print("[Bluetooth] ❌ User rejected pairing")
        pairingState = .idle
        cancelPairing()
    }
    
    private func handlePairingRequest(_ code: String) {
        print("[Bluetooth] 📥 Received pairing request with code: \(code)")
        currentPairingCode = code
        pairingState = .confirmationRequired(code)
        startPairingTimeout()
    }
    
    private func startPairingTimeout() {
        pairingTimeoutTask?.cancel()
        
        let task = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if case .waitingForConfirmation = self.pairingState {
                self.pairingState = .failed("Pairing timed out")
                self.cancelPairing()
            } else if case .confirmationRequired = self.pairingState {
                self.pairingState = .failed("Pairing timed out")
                self.cancelPairing()
            }
        }
        
        pairingTimeoutTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + pairingTimeoutSeconds, execute: task)
    }
    
    private func completePairing() {
        pairingTimeoutTask?.cancel()
        guard let peripheral = pendingPairingDevice ?? connectedPeripheral else { return }
        
        let deviceName = peripheral.name ?? "Unknown Device"
        let pairedInfo = PairedDeviceInfo(
            address: peripheral.identifier.uuidString,
            name: deviceName,
            pairedAt: Date()
        )
        
        pairedDevice = pairedInfo
        savePairedDevice(pairedInfo)
        
        pairingState = .success
        connectionState = .connected
        
        if let device = discoveredDevices.first(where: { $0.peripheral.identifier == peripheral.identifier }) {
            connectedDevice = device
        }
        
        print("[Bluetooth] ✅ Pairing completed: \(deviceName)")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.pairingState = .idle
        }
    }
    
    func cancelPairing() {
        if let peripheral = pendingPairingDevice {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        pendingPairingDevice = nil
        currentPairingCode = nil
        pairingState = .idle
        connectionState = .disconnected
    }
    
    // MARK: - Connection
    
    func connect(to device: DiscoveredDevice) {
        guard let central = centralManager else { return }
        
        connectionState = .connecting
        connectedPeripheral = device.peripheral
        central.connect(device.peripheral, options: nil)
        
        print("[Bluetooth] Connecting to: \(device.name)")
    }
    
    func disconnect() {
        guard let peripheral = connectedPeripheral else { return }
        centralManager?.cancelPeripheralConnection(peripheral)
        connectedPeripheral = nil
        connectedDevice = nil
        connectionState = .disconnected
        
        print("[Bluetooth] Disconnected")
    }
    
    func tryAutoConnect() {
        guard let paired = pairedDevice, autoConnectEnabled else { return }
        
        print("[Bluetooth] 🔄 Attempting auto-connect to \(paired.name)")
        connectionState = .scanning
        startScanning()
        
        // Watch for device
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self = self else { return }
            if let device = self.discoveredDevices.first(where: { $0.id.uuidString == paired.address }) {
                self.connect(to: device)
            } else if case .scanning = self.connectionState {
                self.connectionState = .disconnected
                self.stopScanning()
            }
        }
    }
    
    func forgetPairedDevice() {
        disconnect()
        pairedDevice = nil
        UserDefaults.standard.removeObject(forKey: pairedDeviceAddressKey)
        UserDefaults.standard.removeObject(forKey: pairedDeviceNameKey)
        print("[Bluetooth] 🗑️ Paired device forgotten")
    }
    
    func setAutoConnect(_ enabled: Bool) {
        autoConnectEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: autoConnectKey)
    }
    
    // MARK: - Data Transfer
    
    func sendData(_ data: Data) {
        print("[Bluetooth] sendData not implemented - requires characteristic discovery")
    }
    
    // MARK: - Private Helpers
    
    private func sendPairingRequest(_ code: String) {
        let message: [String: Any] = [
            "command": "pairingRequest",
            "params": ["code": code],
            "timestamp": Date().timeIntervalSince1970 * 1000
        ]
        
        if let data = try? JSONSerialization.data(withJSONObject: message) {
            sendDataToConnectedDevices(data, characteristic: commandCharUUID)
            print("[Bluetooth] 📤 Sent pairing request with code: \(code)")
        }
    }
    
    private func sendPairingAccepted() {
        let message: [String: Any] = [
            "command": "pairingAccepted",
            "params": [:],
            "timestamp": Date().timeIntervalSince1970 * 1000
        ]
        
        if let data = try? JSONSerialization.data(withJSONObject: message) {
            sendDataToConnectedDevices(data, characteristic: commandCharUUID)
            print("[Bluetooth] 📤 Sent pairing accepted")
        }
    }
    
    private func sendDataToConnectedDevices(_ data: Data, characteristic charUUID: CBUUID) {
        // If we're acting as peripheral (advertising), use stored characteristic
        if charUUID == commandCharUUID, let char = commandCharacteristic {
            char.value = data
            for central in subscribedCentrals {
                peripheralManager?.updateValue(data, for: char, onSubscribedCentrals: [central])
            }
            print("[Bluetooth] 📤 Updated command characteristic value")
        } else if charUUID == dataTransferCharUUID, let char = dataTransferCharacteristic {
            char.value = data
            for central in subscribedCentrals {
                peripheralManager?.updateValue(data, for: char, onSubscribedCentrals: [central])
            }
            print("[Bluetooth] 📤 Updated data transfer characteristic value")
        }
        
        // If we're acting as central (connected to peripheral), write to characteristic
        if let peripheral = connectedPeripheral,
           let service = peripheral.services?.first(where: { $0.uuid == airSyncServiceUUID }),
           let char = service.characteristics?.first(where: { $0.uuid == charUUID }) {
            peripheral.writeValue(data, for: char, type: .withResponse)
            print("[Bluetooth] 📤 Wrote to peripheral characteristic")
        }
    }
    
    private func savePairedDevice(_ device: PairedDeviceInfo) {
        UserDefaults.standard.set(device.address, forKey: pairedDeviceAddressKey)
        UserDefaults.standard.set(device.name, forKey: pairedDeviceNameKey)
    }
    
    private func loadPairedDevice() {
        guard let address = UserDefaults.standard.string(forKey: pairedDeviceAddressKey),
              let name = UserDefaults.standard.string(forKey: pairedDeviceNameKey) else { return }
        
        pairedDevice = PairedDeviceInfo(address: address, name: name, pairedAt: Date())
        print("[Bluetooth] 📱 Loaded paired device: \(name)")
    }
    
    private func createDeviceInfoData() -> Data {
        let info: [String: Any] = [
            "alias": Host.current().localizedName ?? "Mac",
            "version": "2.0",
            "deviceModel": getMacModel(),
            "deviceType": "desktop",
            "port": 6996,
            "protocol": "ws"
        ]
        return (try? JSONSerialization.data(withJSONObject: info)) ?? Data()
    }
    
    private func getMacModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }
    
    private func handleReceivedData(_ data: Data, from characteristicUUID: CBUUID) {
        print("[Bluetooth] 📥 Received data on characteristic: \(characteristicUUID)")
        
        if characteristicUUID == commandCharUUID || characteristicUUID == notificationCharUUID {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("[Bluetooth] 📥 Parsed command JSON: \(json)")
                
                if let command = json["command"] as? String,
                   let params = json["params"] as? [String: Any] {
                    
                    switch command {
                    case "pairingRequest":
                        if let code = params["code"] as? String {
                            DispatchQueue.main.async { [weak self] in
                                self?.handlePairingRequest(code)
                            }
                        }
                    case "pairingAccepted":
                        print("[Bluetooth] ✅ Peer accepted pairing!")
                        DispatchQueue.main.async { [weak self] in
                            self?.completePairing()
                        }
                    default:
                        print("[Bluetooth] Received command: \(command)")
                    }
                }
            }
        } else if characteristicUUID == dataTransferCharUUID {
            print("[Bluetooth] Received data transfer: \(data.count) bytes")
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DispatchQueue.main.async { [weak self] in
            switch central.state {
            case .poweredOn:
                self?.isBluetoothEnabled = true
                print("[Bluetooth] Bluetooth is ON")
            case .poweredOff:
                self?.isBluetoothEnabled = false
                self?.isScanning = false
                print("[Bluetooth] Bluetooth is OFF")
            case .unauthorized:
                self?.isBluetoothEnabled = false
                print("[Bluetooth] Bluetooth unauthorized")
            case .unsupported:
                self?.isBluetoothEnabled = false
                print("[Bluetooth] Bluetooth unsupported")
            default:
                print("[Bluetooth] Bluetooth state: \(central.state.rawValue)")
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        guard let name = peripheral.name, !name.isEmpty else { return }
        
        let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let isAirSync = serviceUUIDs.contains(airSyncServiceUUID)
        
        let device = DiscoveredDevice(
            id: peripheral.identifier,
            name: name,
            rssi: RSSI.intValue,
            peripheral: peripheral,
            isAirSyncDevice: isAirSync
        )
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Thread-safe duplicate check - must be inside main queue block
            if self.discoveredDevices.contains(where: { $0.id == peripheral.identifier }) { return }
            
            self.discoveredDevices.append(device)
            self.discoveredDevices.sort { $0.rssi > $1.rssi }
            
            print("[Bluetooth] Discovered: \(name) (RSSI: \(RSSI), AirSync: \(isAirSync))")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("[Bluetooth] Connected to: \(peripheral.name ?? "Unknown")")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.connectionState = .connected
            if let device = self.discoveredDevices.first(where: { $0.id == peripheral.identifier }) {
                self.connectedDevice = device
            }
            // Remove from discovered list
            self.discoveredDevices.removeAll { $0.id == peripheral.identifier }
        }
        
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let errorMsg = error?.localizedDescription ?? "Unknown error"
        print("[Bluetooth] Failed to connect: \(errorMsg)")
        
        DispatchQueue.main.async { [weak self] in
            self?.connectionState = .failed(errorMsg)
            self?.connectedPeripheral = nil
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("[Bluetooth] Disconnected from: \(peripheral.name ?? "Unknown")")
        
        DispatchQueue.main.async { [weak self] in
            self?.connectionState = .disconnected
            self?.connectedDevice = nil
            self?.connectedPeripheral = nil
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        
        for service in services {
            print("[Bluetooth] Discovered service: \(service.uuid)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            let properties = characteristic.properties
            let propStrings = [
                properties.contains(.read) ? "read" : nil,
                properties.contains(.write) ? "write" : nil,
                properties.contains(.notify) ? "notify" : nil,
                properties.contains(.indicate) ? "indicate" : nil
            ].compactMap { $0 }.joined(separator: ", ")
            
            print("[Bluetooth] Discovered characteristic: \(characteristic.uuid) [\(propStrings)]")
            
            // Subscribe to notification/indicate characteristics
            if properties.contains(.notify) || properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: characteristic)
                print("[Bluetooth] 🔔 Subscribing to notifications for: \(characteristic.uuid)")
            }
        }
        
        // Check if this is the AirSync service and we have a pending pairing request
        if service.uuid == airSyncServiceUUID && shouldSendPairingRequestOnServicesDiscovered {
            print("[Bluetooth] 📋 AirSync service characteristics discovered, sending pairing request...")
            shouldSendPairingRequestOnServicesDiscovered = false
            
            // Small delay to ensure notifications are set up
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                if let code = self?.currentPairingCode {
                    self?.sendPairingRequest(code)
                }
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("[Bluetooth] ❌ Failed to subscribe to \(characteristic.uuid): \(error.localizedDescription)")
        } else {
            let state = characteristic.isNotifying ? "enabled" : "disabled"
            print("[Bluetooth] ✅ Notifications \(state) for: \(characteristic.uuid)")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("[Bluetooth] ❌ Error receiving value for \(characteristic.uuid): \(error.localizedDescription)")
            return
        }
        guard let data = characteristic.value else { return }
        print("[Bluetooth] 📥 Received \(data.count) bytes from characteristic: \(characteristic.uuid)")
        handleReceivedData(data, from: characteristic.uuid)
    }
}

// MARK: - CBPeripheralManagerDelegate
extension BluetoothManager: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        DispatchQueue.main.async { [weak self] in
            switch peripheral.state {
            case .poweredOn:
                print("[Bluetooth] Peripheral manager is ON")
            case .poweredOff:
                self?.isAdvertising = false
                print("[Bluetooth] Peripheral manager is OFF")
            default:
                print("[Bluetooth] Peripheral manager state: \(peripheral.state.rawValue)")
            }
        }
    }
    
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            print("[Bluetooth] Failed to start advertising: \(error.localizedDescription)")
            DispatchQueue.main.async { [weak self] in self?.isAdvertising = false }
        } else {
            print("[Bluetooth] Started advertising successfully")
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error {
            print("[Bluetooth] Failed to add service: \(error.localizedDescription)")
        } else {
            print("[Bluetooth] Added service: \(service.uuid)")
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        if request.characteristic.uuid == deviceInfoCharUUID {
            request.value = createDeviceInfoData()
            peripheral.respond(to: request, withResult: .success)
        } else {
            peripheral.respond(to: request, withResult: .attributeNotFound)
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            print("[Bluetooth] 📥 Received write request on characteristic: \(request.characteristic.uuid)")
            if let data = request.value {
                print("[Bluetooth] 📥 Data size: \(data.count) bytes")
                handleReceivedData(data, from: request.characteristic.uuid)
            }
            peripheral.respond(to: request, withResult: .success)
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        print("[Bluetooth] Central subscribed to characteristic: \(characteristic.uuid)")
        if !subscribedCentrals.contains(where: { $0.identifier == central.identifier }) {
            subscribedCentrals.append(central)
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        print("[Bluetooth] Central unsubscribed from characteristic: \(characteristic.uuid)")
        subscribedCentrals.removeAll { $0.identifier == central.identifier }
    }
}
