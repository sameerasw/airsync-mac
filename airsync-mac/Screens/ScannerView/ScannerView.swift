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
    @State private var qrImage: CGImage?
    @State private var copyStatus: String?
    @State private var hasValidIP: Bool = true
    @State private var showConfirmReset = false

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
            } else if let qrImage = qrImage {
                HStack{
                    Text("Scan to connect")
                        .font(.title)
                        .padding()

                    if !UIStyle.pretendOlderOS, #available(macOS 26.0, *) {
                        Label {
                            Text(info.text)
                                .foregroundColor(info.color)
                        } icon: {
                            Image(systemName: info.icon)
                                .foregroundColor(info.color)
                        }
                        .padding(10)
                        .background(.clear)
                        .glassEffect(in: .rect(cornerRadius: 20))
                    } else {
                        Label {
                            Text(info.text)
                                .foregroundColor(info.color)
                        } icon: {
                            Image(systemName: info.icon)
                                .foregroundColor(info.color)
                        }
                        .padding(10)
                        .background(.thinMaterial, in: .rect(cornerRadius: 20))
                    }
                }
                .padding(.bottom, 8)

                Image(decorative: qrImage, scale: 1.0)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 250, height: 250)
                    .accessibilityLabel("QR Code")
                    .shadow(radius: 20)
                    .padding()
                    .background(.black.opacity(0.6), in: .rect(cornerRadius: 30))
            } else {
                ProgressView("Generating QR…")
                    .frame(width: 100, height: 100)
            }

            // --- Copy Key Button ---
            if hasValidIP,
               let key = WebSocketServer.shared.getSymmetricKeyBase64(),
               !key.isEmpty {
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

                // Confirmation popup
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

            Spacer()

            // --- Quick Connect Button ---
            if let lastDevice = quickConnectManager.getLastConnectedDevice() {
                VStack(spacing: 8) {
                    Text("Last connected device:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lastDevice.name)
                                .font(.system(size: 14, weight: .medium))
                            Text("\(lastDevice.ipAddress)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.trailing, 16)

                        GlassButtonView(
                            label: "Reconnect",
                            systemImage: "bolt.circle",
                            action: {
                                quickConnectManager.wakeUpLastConnectedDevice()
                            }
                        )

                        GlassButtonView(
                            label: "Clear",
                            systemImage: "xmark.circle",
                            iconOnly: true,
                            action: {
                                quickConnectManager.clearLastConnectedDevice()
                            }
                        )
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: .rect(cornerRadius: 16))
                }
                .padding(.top, 12)
            }
                Spacer()
        }
        .onAppear {
            generateQRAsync()
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
