//
//  ContentView.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-07-27.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState = AppState.shared

    @State private var deviceName: String = ""
    @State private var port: String = "6996"
    @State private var licenseKey: String = ""
    @State private var adbPortString: String = ""

    @State private var isCheckingLicense = false
    @State private var licenseValid: Bool? = nil

    @State private var isExpanded: Bool = false
    @State private var isLicenseVisible = false
    @State private var showingPlusPopover = false



    var body: some View {
        NavigationStack {
            ScrollView {
                VStack {
                    // Name Field
                    VStack {
                        HStack {
                            Label("Device Name", systemImage: "pencil")
                            Spacer()
                        }
                        TextField("Device Name", text: $deviceName)
                    }
                    .padding()


                    VStack{
                        HStack {
                            Label("Connect ADB", systemImage: "bolt.horizontal.circle")
                            Spacer()

                            ZStack {
                                Toggle(
                                    "",
                                    isOn: $appState.adbEnabled
                                )
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                                    .disabled(!AppState.shared.isPlus && AppState.shared.licenseCheck)

                                // Transparent tap area on top to show popover even if disabled
                                if !AppState.shared.isPlus && AppState.shared.licenseCheck {
                                    Rectangle()
                                        .fill(Color.clear)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            showingPlusPopover = true
                                        }
                                }
                            }
                            .frame(width: 55)
                        }
                        .popover(isPresented: $showingPlusPopover, arrowEdge: .bottom) {
                            PlusFeaturePopover(message: "Wireless ADB features are available in AirSync+")
                                .onTapGesture {
                                    showingPlusPopover = false
                                }
                        }

                        // Show port field if ADB toggle is on
                        if appState.isPlus, appState.adbEnabled{
                            HStack {
                                Label("ADB Port", systemImage: "arrow.left.arrow.right")
                                Spacer()
                                TextField("ADB Port", text: $adbPortString)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 100)
                                    .onChange(of: adbPortString) { _, newValue in
                                        adbPortString = newValue.filter { "0123456789".contains($0) }
                                    }

                                if #available(macOS 26.0, *) {
                                    GlassButtonView(
                                        label: "Set",
                                        systemImage: "checkmark.circle",
                                        action: {
                                            if let port = UInt16(adbPortString), port > 0 && port < 65535 {
                                                appState.adbPort = port
                                                UserDefaults.standard.set(port, forKey: "adbPort")
                                            }
                                        }
                                    )
                                    .buttonStyle(.glass)
                                    .disabled(adbPortString.isEmpty)
                                } else {
                                    GlassButtonView(
                                        label: "Set",
                                        systemImage: "checkmark.circle",
                                        action: {
                                            if let port = UInt16(adbPortString), port > 0 && port < 65535 {
                                                appState.adbPort = port
                                                UserDefaults.standard.set(port, forKey: "adbPort")
                                            }
                                        }
                                    )
                                    .disabled(adbPortString.isEmpty)
                                }

                                if appState.adbConnected {
                                    if #available(macOS 26.0, *) {
                                        GlassButtonView(
                                            label: "Disconnect ADB",
                                            systemImage: "stop.circle",
                                            action: {
                                                ADBConnector.disconnectADB()
                                                appState.adbConnected = false
                                            }
                                        )
                                        .buttonStyle(.glass)
                                    } else {
                                        GlassButtonView(
                                            label: "Disconnect ADB",
                                            systemImage: "stop.circle",
                                            action: {
                                                ADBConnector.disconnectADB()
                                                appState.adbConnected = false
                                            }
                                        )
                                    }
                                } else {
                                    if #available(macOS 26.0, *) {
                                        GlassButtonView(
                                            label: "Connect ADB",
                                            systemImage: "play.circle",
                                            action: {
                                                let ip = appState.device?.ipAddress ?? ""
                                                let port = appState.adbPort
                                                ADBConnector.connectToADB(ip: ip, port: port)
                                            }
                                        )
                                        .buttonStyle(.glass)
                                        .disabled(
                                            adbPortString.isEmpty || appState.device == nil
                                        )
                                    } else {
                                        GlassButtonView(
                                            label: "Connect ADB",
                                            systemImage: "play.circle",
                                            action: {
                                                let ip = appState.device?.ipAddress ?? ""
                                                let port = appState.adbPort
                                                ADBConnector.connectToADB(ip: ip, port: port)
                                            }
                                        )
                                        .disabled(
                                            adbPortString.isEmpty || appState.device == nil
                                        )
                                    }

                                }



                            }



                            HStack{
                                Label("App Mirroring", systemImage: "apps.iphone.badge.plus")
                                Spacer()
                                Toggle("", isOn: $appState.mirroringPlus)
                                    .toggleStyle(.switch)
                            }

                            if let result = appState.adbConnectionResult {
                                VStack(alignment: .leading, spacing: 4) {
                                    ExpandableLicenseSection(title: "ADB Console", content: result)
                                }
                                .padding()
                                .transition(.opacity)
                            }

                        }


                        HStack{
                            Label("Sync device status", systemImage: "battery.75percent")
                            Spacer()
                            Toggle("", isOn: .constant(false))
                                .toggleStyle(.switch)
                                .disabled(true)
                        }

                        HStack{
                            Label("Sync clipboard", systemImage: "clipboard")
                            Spacer()
                            Toggle("", isOn: $appState.isClipboardSyncEnabled)
                                .toggleStyle(.switch)
                        }

                    }
                    .padding()

                    // Info Section
                    VStack {
                        ConnectionInfoText(label: "IP Address", icon: "wifi", text: getLocalIPAddress() ?? "N/A")

                        HStack {
                            Label("Server Port", systemImage: "rectangle.connected.to.line.below")
                                .padding(.trailing, 20)
                            Spacer()
                            TextField("Server Port", text: $port)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: port) { oldValue, newValue in
                                    // Only allow digits
                                    port = newValue.filter { "0123456789".contains($0) }
                                }
                        }

                        ConnectionInfoText(
                            label: "Plus features",
                            icon: "plus.app",
                            text: appState.isPlus ? "Active" : "Not active"
                        )

                    }
                    .padding()
                    HStack{
                        Spacer()

                        if #available(macOS 26.0, *) {
                            Button(
                                "Save and Restart the Server",
                                systemImage: "square.and.arrow.down.badge.checkmark"
                            ) {
                                let portNumber = UInt16(
                                    port
                                ) ?? Defaults.serverPort
                                let ipAddress = getLocalIPAddress() ?? "N/A"
    
                                appState.myDevice = Device(
                                    name: deviceName,
                                    ipAddress: ipAddress,
                                    port: Int(portNumber)
                                )
    
                                UserDefaults.standard
                                    .set(deviceName, forKey: "deviceName")
                                UserDefaults.standard
                                    .set(port, forKey: "devicePort")
    
                                WebSocketServer.shared.stop()
                                WebSocketServer.shared.start(port: portNumber)
    
                                appState.shouldRefreshQR = true
                            }
                            .controlSize(.large)
                            .buttonStyle(.glass)
                        } else {
                            Button(
                                "Save and Restart the Server",
                                systemImage: "square.and.arrow.down.badge.checkmark"
                            ) {
                                let portNumber = UInt16(
                                    port
                                ) ?? Defaults.serverPort
                                let ipAddress = getLocalIPAddress() ?? "N/A"

                                appState.myDevice = Device(
                                    name: deviceName,
                                    ipAddress: ipAddress,
                                    port: Int(portNumber)
                                )

                                UserDefaults.standard
                                    .set(deviceName, forKey: "deviceName")
                                UserDefaults.standard
                                    .set(port, forKey: "devicePort")

                                WebSocketServer.shared.stop()
                                WebSocketServer.shared.start(port: portNumber)

                                appState.shouldRefreshQR = true
                            }
                            .controlSize(.large)
                        }

                    }
                    .padding()

                    HStack {
                        Text("Liquid Opacity")
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
                    .padding()

                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("AirSync+", systemImage: "key")
                            Spacer()
                        }
                        .padding()

                        TextField("Enter license key", text: $licenseKey)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isCheckingLicense)

                        HStack{
                            if #available(macOS 26.0, *) {
                                Button("Check License") {
                                    Task {
                                        isCheckingLicense = true
                                        licenseValid = nil
                                        let result = try? await checkLicenseKeyValidity(
                                            key: licenseKey
                                        )
                                        licenseValid = result ?? false
                                        isCheckingLicense = false
                                    }
                                }
                                .disabled(
                                    licenseKey.isEmpty || isCheckingLicense
                                )
                                .buttonStyle(.glass)
                                .controlSize(.large)
                            } else {
                                Button("Check License") {
                                    Task {
                                        isCheckingLicense = true
                                        licenseValid = nil
                                        let result = try? await checkLicenseKeyValidity(
                                            key: licenseKey
                                        )
                                        licenseValid = result ?? false
                                        isCheckingLicense = false
                                    }
                                }
                                .disabled(
                                    licenseKey.isEmpty || isCheckingLicense
                                )
                            }


                            if isCheckingLicense {
                                ProgressView()
                                    .scaleEffect(0.6)
                            } else if let valid = licenseValid {
                                Image(systemName: valid ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                    .foregroundColor(valid ? .green : .red)
                                    .transition(.scale)
                            }

                            if #available(macOS 26.0, *), !appState.isPlus {
                                GlassButtonView(
                                    label: "Get AirSync+",
                                    systemImage: "link",
                                    action: {
                                        if let url = URL(string: "https://airsync.sameerasw.com") {
                                            NSWorkspace.shared.open(url)
                                        }
                                    }
                                )
                                .buttonStyle(.glass)
                            } else if !appState.isPlus {
                                GlassButtonView(
                                    label: "Get AirSync+",
                                    systemImage: "link",
                                    action: {
                                        if let url = URL(string: "https://airsync.sameerasw.com") {
                                            NSWorkspace.shared.open(url)
                                        }
                                    }
                                )
                            }

                            Spacer()
                        }

                            if let details = appState.licenseDetails {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack{
                                        Text("License Info")
                                            .font(.headline)
                                            .padding(.bottom, 4)

                                        Spacer()

                                        Text("Thank you <3")
                                            .font(.subheadline)
                                            .padding(.bottom, 4)
                                    }

                                    Divider()
                                    
                                    HStack {
                                        Label("Email", systemImage: "envelope")
                                        Spacer()
                                        Text(details.email)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    HStack {
                                        Label("Product", systemImage: "shippingbox")
                                        Spacer()
                                        Text(details.productName)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    HStack {
                                        Label("Order #", systemImage: "number")
                                        Spacer()
                                        Text("\(details.orderNumber)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    HStack {
                                        Label("Purchaser ID", systemImage: "person.fill")
                                        Spacer()
                                        Text(details.purchaserID)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    HStack {
                                        Label("License Key", systemImage: "key")
                                        Spacer()
                                        Group {
                                            if isLicenseVisible {
                                                Text(details.key)
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                    .textSelection(.enabled)
                                            } else {
                                                Text(String(repeating: "•", count: max(6, min(details.key.count, 12))))
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        .onTapGesture {
                                            withAnimation {
                                                isLicenseVisible.toggle()
                                            }
                                        }
                                    }

                                }
                                .padding()
                                .background(Color.secondary.opacity(0.05))
                                .cornerRadius(10)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                                .animation(.easeInOut(duration: 0.3), value: appState.licenseDetails)
                            }

                        }


                        DisclosureGroup(isExpanded: $isExpanded) {
                            Text(
                            """
Keeps me inspired to continue and maybe even to publish to the Apple app store and google play store. Think of it as a little donation to keep this project alive and evolving.
That said, I know not everyone who wants the full experience can afford it. If that’s you, please don’t hesitate to reach out. 😊

The source code is available on GitHub, and you're more than welcome to build with all Plus features free—for personal use which also opens for contributions which is a win win!.
As a thank-you for supporting the app, AirSync+ unlocks some nice extras: media controls, synced widgets, low battery alerts, wireless ADB, and more to come as I keep adding new features.

Enjoy the app!
(っ◕‿◕)っ
"""
                            )
                                .font(.footnote)
                                .multilineTextAlignment(.leading)
                                .padding()
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(8)
                        } label: {
                            Text("Why plus?")
                                .font(.subheadline)
                                .bold()
                        }
                        .padding(.horizontal)
                        .focusEffectDisabled()

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

                    adbPortString = String(appState.adbPort)
                }

            }


}

#Preview {
    SettingsView()
}


