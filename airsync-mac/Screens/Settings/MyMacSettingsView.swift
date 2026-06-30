import SwiftUI

struct MyMacSettingsView: View {
    @ObservedObject var appState = AppState.shared

    @State private var deviceName: String = ""
    @State private var port: String = "6996"
    @State private var availableAdapters: [(name: String, address: String)] = []
    @State private var currentIPAddress: String = "N/A"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 1. Device Info
                SettingsHeaderView(title: "Device Name", icon: "iphone")
                VStack {
                    DeviceNameView(deviceName: $deviceName)
                }
                .padding()
                .glassBoxIfAvailable(radius: 18)

                // 2. Server settings
                SettingsHeaderView(title: "Server Configuration", icon: "server.rack")
                VStack(spacing: 12) {
                    HStack {
                        Label("Network adapter", systemImage: "rectangle.connected.to.line.below")
                        Spacer()

                        Picker("", selection: Binding(
                            get: { appState.selectedNetworkAdapterName },
                            set: { appState.selectedNetworkAdapterName = $0 }
                        )) {
                            Text("Auto").tag(nil as String?)
                            ForEach(availableAdapters, id: \.name) { adapter in
                                Text("\(adapter.name) (\(adapter.address))").tag(Optional(adapter.name))
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                    }
                    .onAppear {
                        availableAdapters = WebSocketServer.shared.getAvailableNetworkAdapters()
                        currentIPAddress = WebSocketServer.shared.getLocalIPAddress(adapterName: appState.selectedNetworkAdapterName) ?? "N/A"
                    }
                    .onChange(of: appState.selectedNetworkAdapterName) { _, _ in
                        currentIPAddress = WebSocketServer.shared.getLocalIPAddress(adapterName: appState.selectedNetworkAdapterName) ?? "N/A"
                        WebSocketServer.shared.stop()
                        if let port = UInt16(port) {
                            WebSocketServer.shared.start(port: port)
                        } else {
                            WebSocketServer.shared.start()
                        }
                        appState.shouldRefreshQR = true
                    }

                    ConnectionInfoText(
                        label: "IP address",
                        icon: "wifi",
                        text: currentIPAddress,
                        activeIp: appState.activeMacIp
                    )

                    HStack {
                        Label("Server port", systemImage: "rectangle.connected.to.line.below")
                            .padding(.trailing, 20)
                        Spacer()
                        TextField("Server Port", text: $port)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: port) { oldValue, newValue in
                                port = newValue.filter { "0123456789".contains($0) }
                            }
                            .frame(maxWidth: 100)
                    }
                }
                .padding()
                .glassBoxIfAvailable(radius: 18)

                HStack {
                    Spacer()
                    SaveAndRestartButton(
                        title: "Save and Restart the Server",
                        systemImage: "square.and.arrow.down.badge.checkmark",
                        deviceName: deviceName,
                        port: port,
                        version: appState.device?.version ?? "",
                        onSave: nil,
                        onRestart: nil
                    )
                }
            }
            .padding()
        }
        .onAppear {
            if let device = appState.myDevice {
                deviceName = device.name
                port = String(device.port)
            } else {
                deviceName = UserDefaults.standard.string(forKey: "deviceName")
                ?? (Host.current().localizedName ?? "My Mac")
                port = UserDefaults.standard.string(forKey: "devicePort")
                ?? String(Defaults.serverPort)
            }
        }
    }
}
