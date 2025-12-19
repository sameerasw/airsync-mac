//
//  SaveAndRestartButton.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2025-08-04.
//

import SwiftUI


struct SaveAndRestartButton: View {
    let title: String
    let systemImage: String
    let deviceName: String
    let port: String
    let version: String
    let onSave: ((Device) -> Void)?
    let onRestart: ((UInt16) -> Void)?

    @ObservedObject var appState: AppState = .shared

    var body: some View {
        HStack {
            Button(title, systemImage: systemImage) {
                let portNumber = UInt16(port) ?? Defaults.serverPort
                let ipAddress = WebSocketServer.shared.getLocalIPAddress(
                    adapterName: appState.selectedNetworkAdapterName
                ) ?? "N/A"

                let device = Device(
                    name: deviceName,
                    ipAddress: ipAddress,
                    port: Int(portNumber),
                    version: version,
                    adbPorts: []
                )

                // Save
                appState.myDevice = device
                UserDefaults.standard.set(deviceName, forKey: "deviceName")
                UserDefaults.standard.set(port, forKey: "devicePort")

                // Custom hooks
                onSave?(device)

                WebSocketServer.shared.stop()
                WebSocketServer.shared.start(port: portNumber)
                onRestart?(portNumber)

                // Delay QR refresh to ensure server has restarted
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    appState.shouldRefreshQR = true
                }
            }
            .controlSize(.large)
            .applyGlassIfAvailable()
        }
    }
}


extension View {
    @ViewBuilder
    func applyGlassIfAvailable() -> some View {
        if !UIStyle.pretendOlderOS, #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }
}
