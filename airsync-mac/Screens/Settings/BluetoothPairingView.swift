//
//  BluetoothPairingView.swift
//  airsync-mac
//
//  Bluetooth device discovery and pairing UI with 3-option code verification
//

import SwiftUI
import CoreBluetooth

struct BluetoothPairingView: View {
    @StateObject private var bluetoothManager = BluetoothManager.shared
    @State private var isExpanded: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: headerIcon)
                    .foregroundColor(headerColor)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bluetooth Connection")
                        .font(.headline)
                    
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if case .connected = bluetoothManager.connectionState {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
                
                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .contentShape(Rectangle())
            .onTapGesture { isExpanded.toggle() }
            
            if isExpanded {
                Divider()
                
                if !bluetoothManager.isBluetoothEnabled {
                    BluetoothDisabledView()
                } else {
                    // Paired device section
                    if let paired = bluetoothManager.pairedDevice {
                        let isConnected: Bool = {
                            if case .connected = bluetoothManager.connectionState { return true }
                            return false
                        }()
                        let isConnecting: Bool = {
                            if case .connecting = bluetoothManager.connectionState { return true }
                            return false
                        }()
                        
                        PairedDeviceSection(
                            deviceName: paired.name,
                            isConnected: isConnected,
                            isConnecting: isConnecting,
                            autoConnectEnabled: bluetoothManager.autoConnectEnabled,
                            onConnect: { bluetoothManager.tryAutoConnect() },
                            onDisconnect: { bluetoothManager.disconnect() },
                            onForget: { bluetoothManager.forgetPairedDevice() },
                            onAutoConnectChanged: { bluetoothManager.setAutoConnect($0) }
                        )
                        
                        Divider()
                    }
                    
                    // Scan controls
                    HStack {
                        Button(action: toggleScan) {
                            HStack {
                                if bluetoothManager.isScanning {
                                    ProgressView()
                                        .controlSize(.small)
                                        .frame(width: 16, height: 16)
                                } else {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                }
                                Text(bluetoothManager.isScanning ? "Stop Scan" : "Scan for Devices")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button(action: toggleAdvertising) {
                            HStack {
                                if bluetoothManager.isAdvertising {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                } else {
                                    Image(systemName: "antenna.radiowaves.left.and.right.circle")
                                }
                                Text(bluetoothManager.isAdvertising ? "Visible" : "Make Discoverable")
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    // Pairing state indicator
                    PairingStateView(state: bluetoothManager.pairingState)
                    
                    // Discovered devices
                    DiscoveredDevicesSection(
                        devices: bluetoothManager.discoveredDevices.filter { $0.isAirSyncDevice },
                        isScanning: bluetoothManager.isScanning,
                        connectionState: bluetoothManager.connectionState,
                        onPair: { device in
                            bluetoothManager.initiatePairing(with: device)
                        }
                    )
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        .cornerRadius(12)
        .onAppear {
            bluetoothManager.initialize()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if bluetoothManager.isBluetoothEnabled && !bluetoothManager.isAdvertising {
                    bluetoothManager.startAdvertising()
                }
            }
            
            if bluetoothManager.autoConnectEnabled && bluetoothManager.pairedDevice != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    bluetoothManager.tryAutoConnect()
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { 
                if case .confirmationRequired = bluetoothManager.pairingState { return true }
                return false
            },
            set: { if !$0 { bluetoothManager.cancelPairing() } }
        )) {
            if case .confirmationRequired(let code) = bluetoothManager.pairingState {
                PairingConfirmationSheet(
                    code: code,
                    onConfirm: {
                        bluetoothManager.acceptPairing()
                    },
                    onCancel: {
                        bluetoothManager.rejectPairing()
                    }
                )
            }
        }
    }
    
    private var headerIcon: String {
        switch bluetoothManager.connectionState {
        case .connected: return "dot.radiowaves.left.and.right"
        case .scanning: return "antenna.radiowaves.left.and.right"
        default: return "wave.3.right"
        }
    }
    
    private var headerColor: Color {
        switch bluetoothManager.connectionState {
        case .connected: return .blue
        default: return .secondary
        }
    }
    
    private var statusText: String {
        if !bluetoothManager.isBluetoothEnabled {
            return "Bluetooth is off"
        }
        
        switch bluetoothManager.connectionState {
        case .connected:
            return "Connected to \(bluetoothManager.connectedDevice?.name ?? "device")"
        case .connecting:
            return "Connecting..."
        case .scanning:
            return "Scanning..."
        case .failed(let error):
            return "Failed: \(error)"
        case .disconnected:
            if let paired = bluetoothManager.pairedDevice {
                return "Paired: \(paired.name)"
            }
            return "No device paired"
        }
    }
    
    private func toggleScan() {
        if bluetoothManager.isScanning {
            bluetoothManager.stopScanning()
        } else {
            bluetoothManager.startScanning()
        }
    }
    
    private func toggleAdvertising() {
        if bluetoothManager.isAdvertising {
            bluetoothManager.stopAdvertising()
        } else {
            bluetoothManager.startAdvertising()
        }
    }
}

// MARK: - Subviews

struct BluetoothDisabledView: View {
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text("Bluetooth is turned off")
                .font(.subheadline)
            Spacer()
            Button("Enable") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preferences.Bluetooth") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(8)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
}

struct PairedDeviceSection: View {
    let deviceName: String
    let isConnected: Bool
    let isConnecting: Bool
    let autoConnectEnabled: Bool
    let onConnect: () -> Void
    let onDisconnect: () -> Void
    let onForget: () -> Void
    let onAutoConnectChanged: (Bool) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Paired Device")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack {
                Image(systemName: isConnected ? "iphone.radiowaves.left.and.right" : "iphone")
                    .foregroundColor(isConnected ? .blue : .secondary)
                
                VStack(alignment: .leading) {
                    Text(deviceName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text(isConnected ? "Connected" : isConnecting ? "Connecting..." : "Not connected")
                        .font(.caption)
                        .foregroundColor(isConnected ? .green : .secondary)
                }
                
                Spacer()
                
                if isConnected {
                    Button("Disconnect", action: onDisconnect)
                        .buttonStyle(.bordered)
                } else if isConnecting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("Connect", action: onConnect)
                        .buttonStyle(.borderedProminent)
                }
                
                Button(action: onForget) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("Forget this device")
            }
            .padding(8)
            .background(isConnected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
            .cornerRadius(8)
            
            Toggle("Auto-connect on launch", isOn: Binding(
                get: { autoConnectEnabled },
                set: { onAutoConnectChanged($0) }
            ))
            .font(.subheadline)
        }
    }
}

struct PairingStateView: View {
    let state: BluetoothManager.PairingState
    
    var body: some View {
        switch state {
        case .confirmationRequired:
            // Handled by sheet
            EmptyView()
            
        case .waitingForConfirmation(let code):
            VStack(spacing: 8) {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Waiting for confirmation on other device...")
                        .font(.subheadline)
                }
                Text(code)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(8)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
            
        case .success:
            Text("✓ Pairing successful!")
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            
        case .failed(let reason):
            Text("✗ Pairing failed: \(reason)")
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            
        default:
            EmptyView()
        }
    }
}

struct DiscoveredDevicesSection: View {
    let devices: [BluetoothManager.DiscoveredDevice]
    let isScanning: Bool
    let connectionState: BluetoothManager.ConnectionState
    let onPair: (BluetoothManager.DiscoveredDevice) -> Void
    
    var body: some View {
        if !devices.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("AirSync Devices (\(devices.count))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(devices) { device in
                            DiscoveredDeviceRow(
                                device: device,
                                isConnecting: isConnecting(to: device),
                                onPair: { onPair(device) }
                            )
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        } else if isScanning {
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Searching for AirSync devices...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
        } else {
            Text("Tap 'Scan for Devices' to find nearby AirSync-enabled Android devices")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .padding()
        }
    }
    
    private func isConnecting(to device: BluetoothManager.DiscoveredDevice) -> Bool {
        if case .connecting = connectionState {
            return true
        }
        return false
    }
}

struct DiscoveredDeviceRow: View {
    let device: BluetoothManager.DiscoveredDevice
    let isConnecting: Bool
    let onPair: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "iphone")
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(device.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("AirSync")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(4)
                }
                
                Text(signalStrengthText)
                    .font(.caption)
                    .foregroundColor(signalColor)
            }
            
            Spacer()
            
            SignalStrengthIndicator(rssi: device.rssi)
            
            if isConnecting {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 60)
            } else {
                Button("Pair", action: onPair)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var signalStrengthText: String {
        if device.rssi >= -50 {
            return "Excellent signal"
        } else if device.rssi >= -60 {
            return "Good signal"
        } else if device.rssi >= -70 {
            return "Fair signal"
        } else {
            return "Weak signal"
        }
    }
    
    private var signalColor: Color {
        if device.rssi >= -50 {
            return .green
        } else if device.rssi >= -60 {
            return .blue
        } else if device.rssi >= -70 {
            return .orange
        } else {
            return .red
        }
    }
}

struct SignalStrengthIndicator: View {
    let rssi: Int
    
    private var bars: Int {
        if rssi >= -50 {
            return 4
        } else if rssi >= -60 {
            return 3
        } else if rssi >= -70 {
            return 2
        } else {
            return 1
        }
    }
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(index < bars ? Color.blue : Color.gray.opacity(0.3))
                    .frame(width: 3, height: CGFloat(4 + index * 3))
            }
        }
        .frame(width: 20, height: 16)
    }
}

struct PairingConfirmationSheet: View {
    let code: String
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Bluetooth Pairing Request")
                .font(.title2)
                .fontWeight(.bold)
            
            VStack(spacing: 8) {
                Text("Does this code match the one on your other device?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Text(code)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(.blue)
                    .padding(.vertical, 8)
            }
            
            HStack(spacing: 16) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                
                Button("Pair", action: onConfirm)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(width: 350)
    }
}

#Preview {
    BluetoothPairingView()
        .frame(width: 400)
        .padding()
}
