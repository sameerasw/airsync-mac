import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState = AppState.shared
    @AppStorage("SUEnableAutomaticChecks") private var automaticallyChecksForUpdates = true
    @AppStorage("SUAutomaticallyUpdate") private var automaticallyDownloadsUpdates = false

    @State private var deviceName: String = ""
    @State private var port: String = "6996"
    @State private var availableAdapters: [(name: String, address: String)] = []
    @State private var currentIPAddress: String = "N/A"


    var body: some View {
            ScrollView {
                VStack {
                    // Device Name Field
                    DeviceNameView(deviceName: $deviceName)
                    .background(.background.opacity(0.3))
                    .cornerRadius(12.0)

                    // Info Section
                    VStack {
                        HStack {
                            Label("Network", systemImage: "rectangle.connected.to.line.below")
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
                            // Update IP address immediately
                            currentIPAddress = WebSocketServer.shared.getLocalIPAddress(adapterName: appState.selectedNetworkAdapterName) ?? "N/A"

                            WebSocketServer.shared.stop()
                            if let port = UInt16(port) {
                                WebSocketServer.shared.start(port: port)
                            } else {
                                WebSocketServer.shared.start()
                            }
                            // Refresh QR code since IP address may have changed
                            appState.shouldRefreshQR = true
                        }

                        ConnectionInfoText(
                            label: "IP Address",
                            icon: "wifi",
                            text: currentIPAddress
                        )

                        HStack {
                            Label("Server Port", systemImage: "rectangle.connected.to.line.below")
                                .padding(.trailing, 20)
                            Spacer()
                            TextField("Server Port", text: $port)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: port) { oldValue, newValue in
                                    port = newValue.filter { "0123456789".contains($0) }
                                }
                                .frame(maxWidth: 100)
                        }

                        HStack {
                            Label("Fallback to mdns services", systemImage: "antenna.radiowaves.left.and.right")
                            Spacer()
                            Toggle("", isOn: $appState.fallbackToMdns)
                                .toggleStyle(.switch)
                        }
                    }
                    .padding()
                    .background(.background.opacity(0.3))
                    .cornerRadius(12.0)

                    HStack{
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

                    Spacer(minLength: 32)


                    SettingsFeaturesView()
                        .background(.background.opacity(0.3))
                        .cornerRadius(12.0)

                    Spacer(minLength: 32)

                    // App icons
                    AppIconView()


                    VStack {

                        HStack{
                            Label("Liquid Opacity", systemImage: "app.background.dotted")
                            Spacer()
                            Slider(
                                value: $appState.windowOpacity,
                                in: 0...1.0
                            )
                            .frame(width: 200)
                        }

                        HStack{
                            Label("Hide Dock Icon", systemImage: "dock.rectangle")
                            Spacer()
                            Toggle("", isOn: $appState.hideDockIcon)
                                .toggleStyle(.switch)
                        }

                        HStack{
                            Label("Always Open Window", systemImage: "macwindow")
                            Spacer()
                            Toggle("", isOn: $appState.alwaysOpenWindow)
                                .toggleStyle(.switch)
                        }
                    }
                    .padding()
                    .background(.background.opacity(0.3))
                    .cornerRadius(12.0)

                    VStack {

                        HStack{
                            Label("Menubar text", systemImage: "menubar.arrow.up.rectangle")
                            Spacer()
                            Toggle("", isOn: $appState.showMenubarText)
                                .toggleStyle(.switch)
                        }

                        if appState.showMenubarText {
                            HStack {
                                Label("Menubar Text length", systemImage: "textformat.123")
                                Spacer()
                                Slider(
                                    value: Binding(
                                        get: { Double(appState.menubarTextMaxLength) },
                                        set: { appState.menubarTextMaxLength = Int($0) }
                                    ),
                                    in: 10...80,
                                    step: 5
                                )
                                .frame(width: 200)
                                .controlSize(.small)
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            .animation(.easeInOut(duration: 0.3), value: appState.showMenubarText)

                            HStack{
                                Label {
                                    Text("Show device name")
                                } icon: {
                                    Image(systemName: "iphone.gen3")
                                        .imageScale(.medium)
                                        .frame(width: 18, alignment: .center)
                                }
                                Spacer()
                                Toggle("", isOn: $appState.showMenubarDeviceName)
                                    .toggleStyle(.switch)
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            .animation(.easeInOut(duration: 0.3), value: appState.showMenubarText)

                        }
                    }
                    .padding()
                    .background(.background.opacity(0.3))
                    .cornerRadius(12.0)

                    VStack {
                        SettingsToggleView(name: "Check for updates automatically", icon: "sparkles", isOn: $automaticallyChecksForUpdates)
                        SettingsToggleView(name: "Download updates automatically", icon: "arrow.down.circle", isOn: $automaticallyDownloadsUpdates)
                    }
                    .padding()
                    .background(.background.opacity(0.3))
                    .cornerRadius(12.0)

                    Spacer(minLength: 32)

                    SettingsPlusView()
                        .padding()
                        .background(.background.opacity(0.3))
                        .cornerRadius(12.0)
                }
                .padding()

            }
        .frame(minWidth: 300)
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
