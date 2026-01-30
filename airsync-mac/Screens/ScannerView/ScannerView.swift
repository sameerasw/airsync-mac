//
//  ScannerView.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-07-28.
//

import SwiftUI
import QRCode
internal import SwiftImageReadWrite
import CryptoKit

struct ScannerView: View {
    @ObservedObject var appState = AppState.shared
    @StateObject private var quickConnectManager = QuickConnectManager.shared
    @StateObject private var udpDiscovery = UDPDiscoveryManager.shared
    @State private var qrImage: CGImage?
    @State private var showQR = true
    @State private var copyStatus: String?
    @State private var hasValidIP: Bool = true
    @State private var showConfirmReset = false
    @Namespace private var animation

    private func statusInfo(for status: WebSocketStatus) -> (text: String, icon: String, color: Color) {
        switch status {
        case .stopped:
            return ("Stopped", "xmark.circle", .gray)
        case .starting:
            return ("Starting...", "clock", .orange)
        case .started:
            return ("Ready", "checkmark.circle", .green)
        case .failed(let error):
            return ("Failed: \(error)", "exclamationmark.triangle", .red)
        }
    }

    var body: some View {

        let info = statusInfo(for: appState.webSocketStatus)

        VStack {
            Spacer()

            if !hasValidIP {
                VStack {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 30))
                        .foregroundColor(.gray)
                        .padding()

                    Text("No local IP found")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .frame(width: 250, height: 250)
                .padding()
            } else {
                
                // --- QR Code & Encryption Key Section ---
                if showQR {
                    VStack {
                        if let qrImage = qrImage {
                            HStack{
                                Text("Scan to connect")
                                    .font(.title3)
                                    .padding()

                                    Label {
                                        Text(info.text)
                                            .foregroundColor(info.color)
                                    } icon: {
                                        Image(systemName: info.icon)
                                            .foregroundColor(info.color)
                                    }
                                    .padding(6)
                                    .glassBoxIfAvailable(radius: 20)

                            }
                            .padding(.bottom, 4)

                            Image(decorative: qrImage, scale: 1.0)
                                .resizable()
                                .interpolation(.none)
                                .frame(width: 240, height: 240)
                                .accessibilityLabel("QR Code")
                                .shadow(radius: 20)
                                .padding()
                                .background(.black.opacity(0.6), in: .rect(cornerRadius: 30))
                        } else {
                            ProgressView("Generating QR…")
                                .frame(width: 100, height: 100)
                        }

                        // Copy Key Button
                        if let key = WebSocketServer.shared.getSymmetricKeyBase64(), !key.isEmpty {
                            HStack {
                                GlassButtonView(
                                    label: "Copy Key",
                                    systemImage: "key",
                                    action: {
                                        copyToClipboard(key)
                                    }
                                )

                                GlassButtonView(
                                    label: "Re-generate key",
                                    systemImage: "repeat.badge.xmark",
                                    iconOnly: true,
                                    action: {
                                        showConfirmReset = true
                                    }
                                )
                            }
                            .padding(.top, 8)
                            .confirmationDialog(
                                "Are you sure you want to reset the key? You will have to re-auth all the devices.",
                                isPresented: $showConfirmReset
                            ) {
                                Button("Reset key", role: .destructive) {
                                    WebSocketServer.shared.resetSymmetricKey()
                                    generateQRAsync()
                                }
                                Button("Cancel", role: .cancel) { }
                            }

                            if let status = copyStatus {
                                Text(status)
                                    .font(.caption)
                                    .foregroundColor(.green)
                                    .transition(.opacity)
                            }
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                } else {
                     Spacer()
                }

                Spacer()

                // --- Nearby Devices (UDP Discovery) ---
                if !udpDiscovery.discoveredDevices.isEmpty {
                     VStack(spacing: 12) {
                        // Toggle Button
                        HStack {
                            Spacer()
                            GlassButtonView(
                                label: showQR ? "Hide QR Code" : "Show QR Code",
                                systemImage: showQR ? "chevron.up" : "chevron.down",
                                action: {
                                    withAnimation(.spring()) {
                                        showQR.toggle()
                                    }
                                }
                            )
                            Spacer()
                        }
                        .padding(.horizontal, 16)

                        // Title
                        HStack {
                            Spacer()
                            Text("Available Devices")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        
                        // Device List
                         ScrollView {
                             HStack(spacing: showQR ? 10 : 12) {
                                 ForEach(udpDiscovery.discoveredDevices) { device in
                                     let lastConnected = quickConnectManager.getLastConnectedDevice()
                                     DeviceCard(
                                         device: device,
                                         isLastConnected: lastConnected?.name == device.name && (lastConnected != nil && device.ips.contains(lastConnected!.ipAddress)),
                                         isCompact: showQR,
                                         connectAction: {
                                              quickConnectManager.connect(to: device)
                                         },
                                         namespace: animation
                                     )
                                     .transition(.scale.combined(with: .opacity))
                                 }
                             }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .padding(.bottom, showQR ? 0 : 16)
                        }
                        .scrollClipDisabled()
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: udpDiscovery.discoveredDevices)
                        .frame(maxWidth: .infinity)
                        .frame(height: showQR ? 100 : nil)
                        .frame(maxHeight: showQR ? 100 : 400)
                    }
                    .padding(.top, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .onAppear {
            generateQRAsync()
            udpDiscovery.start()
        }
        .onDisappear {
            udpDiscovery.stop()
        }
        .onTapGesture {
            generateQRAsync()
        }
        .onChange(of: appState.shouldRefreshQR) { _, newValue in
            if newValue {
                generateQRAsync()
                appState.shouldRefreshQR = false
            }
        }
        .onChange(of: appState.selectedNetworkAdapterName) { _, _ in
            // Network adapter changed, regenerate QR with new IP
            generateQRAsync()
            // Refresh device info for new network
            quickConnectManager.refreshDeviceForCurrentNetwork()
        }
        .onChange(of: appState.myDevice?.port) { _, _ in
            // Port changed, regenerate QR
            generateQRAsync()
        }
        .onChange(of: appState.myDevice?.name) { _, _ in
            // Device name changed, regenerate QR
            generateQRAsync()
        }
        .onChange(of: udpDiscovery.discoveredDevices) { oldDevices, newDevices in
            if oldDevices.isEmpty && !newDevices.isEmpty {
                // First device discovered, collapse QR if it's showing
                if showQR {
                    withAnimation(.spring()) {
                        showQR = false
                    }
                }
            } else if newDevices.isEmpty {
                 // All devices gone, show QR
                 withAnimation(.spring()) {
                    showQR = true
                 }
            }
        }

    }

     func generateQRAsync() {
        let ip = WebSocketServer.shared
            .getLocalIPAddress(
                adapterName: appState.selectedNetworkAdapterName
            )

        // Check if we have a valid IP address
        guard let validIP = ip else {
            DispatchQueue.main.async {
                self.hasValidIP = false
                self.qrImage = nil
            }
            return
        }

        // If we have a valid IP, proceed with QR generation
        DispatchQueue.main.async {
            self.hasValidIP = true
            self.qrImage = nil // Reset to show progress view
        }

        let text = generateQRText(
            ip: validIP,
            port: UInt16(appState.myDevice?.port ?? Int(Defaults.serverPort)),
            name: appState.myDevice?.name,
            key: WebSocketServer.shared.getSymmetricKeyBase64() ?? ""
        ) ?? "That doesn't look right, QR Generation failed"

        Task {
            if let cgImage = await QRCodeGenerator.generateQRCode(for: text) {
                DispatchQueue.main.async {
                    self.qrImage = cgImage
                }
            }
        }
    }


    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        withAnimation {
            copyStatus = "Copied! Keep it safe"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                copyStatus = nil
            }
        }
    }
}

func generateQRText(ip: String?, port: UInt16?, name: String?, key: String) -> String? {
    guard let ip = ip, let port = port else {
        return nil
    }

    let encodedName = name?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "My Mac"
    return "airsync://\(ip):\(port)?name=\(encodedName)?plus=\(AppState.shared.isPlus)?key=\(key)"
}

#Preview {
    ScannerView()
}
