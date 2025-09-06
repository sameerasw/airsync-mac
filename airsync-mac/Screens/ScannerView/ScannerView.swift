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
    @State private var qrImage: CGImage?
    @State private var copyStatus: String?

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

            Text("Scan to connect")
                .font(.title)
                .padding()

            Spacer()

            if let qrImage = qrImage {
                Image(decorative: qrImage, scale: 1.0)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 250, height: 250)
                    .accessibilityLabel("QR Code")
                    .shadow(radius: 20)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 40)
                            .fill(.clear)
                            .blur(radius: 1)
                    )
            } else {
                ProgressView("Generating QR…")
                    .frame(width: 100, height: 100)
            }

            // --- Copy Key Button ---
            if let key = WebSocketServer.shared.getSymmetricKeyBase64(), !key.isEmpty {
                GlassButtonView(
                    label: "Copy Key",
                    systemImage: "key",
                    action: {
                        copyToClipboard(key)
                    }
                )
                .padding(.top, 8)
                .contextMenu {
                    Button("Reset key - Devices will need to reAuth") {
                        WebSocketServer.shared.resetSymmetricKey()
                        generateQRAsync()
                    }
                }

                if let status = copyStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundColor(.green)
                        .transition(.opacity)
                }
            }


            if !UIStyle.pretendOlderOS, #available(macOS 26.0, *) {
                Label {
                    Text(info.text)
                        .foregroundColor(info.color)
                } icon: {
                    Image(systemName: info.icon)
                        .foregroundColor(info.color)
                }
                .padding()
                .background(.clear)
                // TODO: Restore glass effects when using Xcode 26.0+
                // .glassEffect(in: .rect(cornerRadius: 20))
                .background(.thinMaterial, in: .rect(cornerRadius: 20))
                .padding()
            } else {
                Label {
                    Text(info.text)
                        .foregroundColor(info.color)
                } icon: {
                    Image(systemName: info.icon)
                        .foregroundColor(info.color)
                }
                .background(.thinMaterial, in: .rect(cornerRadius: 20))
                .padding()
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

    }

     func generateQRAsync() {
        let text = generateQRText(
            ip: WebSocketServer.shared
                .getLocalIPAddress(
                    adapterName: appState.selectedNetworkAdapterName
                ),
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
