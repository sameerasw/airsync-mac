//
//  MenubarDeviceDiscoveryView.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2026-05-07.
//

import SwiftUI

struct MenubarDeviceDiscoveryView: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var udpDiscovery = DiscoveryManager.shared
    @ObservedObject private var quickConnectManager = QuickConnectManager.shared
    @ObservedObject private var bleManager = BLECentralManager.shared
    
    private var allDiscoveredDevices: [DiscoveredDevice] {
        var mergedDevices: [DiscoveredDevice] = []
        
        // Start with UDP (Wi-Fi/Network) discovered devices
        for udpDevice in udpDiscovery.discoveredDevices {
            mergedDevices.append(udpDevice)
        }
        
        // If BLE is enabled, merge or append BLE devices
        if appState.isBLEEnabled {
            let bleDevices = bleManager.discoveredBLEDevices
            for bleDevice in bleDevices {
                if let index = mergedDevices.firstIndex(where: { ScannerView.namesAreSimilar($0.name, bleDevice.name) }) {
                    var matchedDevice = mergedDevices[index]
                    matchedDevice.ips.insert("Bluetooth LE")
                    mergedDevices[index] = matchedDevice
                } else {
                    let cleanedName = ScannerView.cleanDeviceName(bleDevice.name)
                    let cleanedBLEDevice = DiscoveredDevice(
                        deviceId: bleDevice.deviceId,
                        name: cleanedName,
                        ips: bleDevice.ips,
                        port: bleDevice.port,
                        type: bleDevice.type,
                        lastSeen: bleDevice.lastSeen
                    )
                    mergedDevices.append(cleanedBLEDevice)
                }
            }
        }
        
        return mergedDevices
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let devices = allDiscoveredDevices
            if !devices.isEmpty {
                Text("Nearby Devices")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        let lastConnected = quickConnectManager.getLastConnectedDevice()
                        ForEach(devices) { device in
                            CompactDeviceCard(
                                device: device,
                                isLastConnected: lastConnected != nil && ScannerView.namesAreSimilar(lastConnected!.name, device.name),
                                connectAction: {
                                    if device.type == "ble" {
                                        bleManager.connectManually(toUuid: device.deviceId)
                                    } else {
                                        quickConnectManager.connect(to: device)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 4)
                }
            }
        }
    }
}

struct CompactDeviceCard: View {
    let device: DiscoveredDevice
    let isLastConnected: Bool
    let connectAction: () -> Void
    
    @ObservedObject private var quickConnectManager = QuickConnectManager.shared
    @ObservedObject private var bleManager = BLECentralManager.shared
    
    private var isLoading: Bool {
        if device.type == "ble" {
            return bleManager.connectingDeviceUUID == device.deviceId
        }
        return quickConnectManager.connectingDeviceID == device.id
    }
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "iphone")
                .font(.system(size: 24))
                .foregroundColor(.secondary)
                .padding(.top, 8)
            
            Text(device.name)
                .font(.system(size: 11, weight: .bold))
                .lineLimit(1)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 4) {
                if device.type == "ble" {
                    Image("logo.bluetooth")
                        .foregroundColor(.accentColor)
                } else {
                    if device.ips.contains("Bluetooth LE") {
                        Image("logo.bluetooth")
                    }
                    if device.ips.contains(where: { $0 != "Bluetooth LE" && !$0.hasPrefix("100.") }) {
                        Image(systemName: "wifi")
                    }
                    if device.ips.contains(where: { $0 != "Bluetooth LE" && $0.hasPrefix("100.") }) {
                        Image(systemName: "globe")
                    }
                }

                if isLastConnected {
                    Text("Last connected")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.15), in: .capsule)
                }
                
                if device.type != "ble" {
                    Text(device.discoverySource == .mdns ? "mDNS" : "UDP")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(device.discoverySource == .mdns ? .accentColor : .secondary)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 0.5)
                        .background(
                            (device.discoverySource == .mdns ? Color.accentColor : Color.secondary).opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 2)
                        )
                }
            }
            .font(.system(size: 8))
            .foregroundColor(.secondary)
            

            
            Spacer()

            GlassButtonView(
                label: "Connect",
                systemImage: "bolt.circle.fill",
                primary: device.isActive,
                isLoading: isLoading,
                action: connectAction
            )
            .frame(maxWidth: .infinity)

        }
        .padding(8)
        .frame(width: 125, height: 135)
        .glassBoxIfAvailable(radius: 12)
    }
}

#Preview {
    MenubarDeviceDiscoveryView()
        .frame(width: 320)
        .background(Color.black.opacity(0.8))
}
