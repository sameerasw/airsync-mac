import SwiftUI
import UserNotifications

struct SettingsView: View {
    @ObservedObject var appState = AppState.shared

    @State private var deviceName: String = ""
    @State private var port: String = "6996"
    @State private var availableAdapters: [(name: String, address: String)] = []

    // New state for notification permissions
    @State private var notificationsGranted = false
    @State private var notificationsChecked = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack {
                    // Device Name Field
                    VStack {
                        HStack {
                            Label("Rename your \(DeviceTypeUtil.deviceTypeDescription())", systemImage: "pencil")
                            Spacer()
                        }
                        TextField("Device Name", text: $deviceName)
                    }
                    .padding()
                    .background(.background.opacity(0.3))
                    .cornerRadius(12.0)

                    SettingsFeaturesView()
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
                        }
                        .onChange(of: appState.selectedNetworkAdapterName) { _, _ in
                            WebSocketServer.shared.stop()
                            if let port = UInt16(port) {
                                WebSocketServer.shared.start(port: port)
                            } else {
                                WebSocketServer.shared.start()
                            }
                        }

                        ConnectionInfoText(
                            label: "IP Address",
                            icon: "wifi",
                            text: WebSocketServer.shared.getLocalIPAddress(adapterName: appState.selectedNetworkAdapterName) ?? "N/A"
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

                        ConnectionInfoText(
                            label: "Plus features (session)",
                            icon: "plus.app",
                            text: appState.isPlus ? "Active" : "Not active"
                        )
                    }
                    .padding()
                    .background(.background.opacity(0.3))
                    .cornerRadius(12.0)

                    HStack{
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

                    // UI Tweaks Section
                    VStack {
                        HStack {
                            Label("System Notifications", systemImage: "bell.badge")

                            Spacer()

                            GlassButtonView(
                                label: notificationsGranted ? "Enabled" : "Grant Permission",
                                systemImage: notificationsGranted ? "checkmark.circle.fill" : "bell.badge",
                                primary: !notificationsGranted,
                                action: {
                                        openNotificationSettings()
                                }
                            )
                            .disabled(notificationsGranted)
                            .transition(.identity)
                        }

                        HStack{
                            Label("Liquid Opacity", systemImage: "app.background.dotted")
                            Spacer()
                            Slider(
                                value: $appState.windowOpacity,
                                in: 0...1.0
                            )
                            .frame(width: 200)
                            HStack{
                                Spacer()
                                Text(appState.windowOpacity == 0.0 ? "Liquid AF" : String(format: "%.0f%%", appState.windowOpacity * 100))
                                    .font(.caption)
                            }
                            .frame(width: 75)
                        }

                        HStack{
                            Label("Toolbar contrast", systemImage: "uiwindow.split.2x1")
                            Spacer()
                            Toggle("", isOn: $appState.toolbarContrast)
                                .toggleStyle(.switch)
                        }

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
                                Label("Hide Dock Icon", systemImage: "dock.rectangle")
                                Spacer()
                                Toggle("", isOn: $appState.hideDockIcon)
                                    .toggleStyle(.switch)
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            .animation(.easeInOut(duration: 0.3), value: appState.showMenubarText)
                        }
                    }
                    .padding()
                    .background(.background.opacity(0.3))
                    .cornerRadius(12.0)

                    SettingsPlusView()
                        .padding()
                        .background(.background.opacity(0.3))
                        .cornerRadius(12.0)
                }
                .padding()
            }
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
            checkNotificationPermissions()
        }
    }

    // MARK: - Notification Permission Helpers
    func checkNotificationPermissions() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                notificationsGranted = (settings.authorizationStatus == .authorized)
                notificationsChecked = true
            }
        }
    }

    func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }
}
