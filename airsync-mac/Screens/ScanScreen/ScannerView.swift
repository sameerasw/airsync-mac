//
//  ScannerView.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-07-28.
//

import SwiftUI
import QRCode
internal import SwiftImageReadWrite

struct ScannerView: View {
    @ObservedObject var appState = AppState.shared
    @State private var qrImage: CGImage?

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
            Text("Scan to connect")
                .padding()

            Spacer()

            if let qrImage = qrImage {
                Image(decorative: qrImage, scale: 1.0)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 190, height: 190)
                    .accessibilityLabel("QR Code")
                    .shadow(radius: 10)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(.clear)
                            .blur(radius: 1)
                    )
            } else {
                ProgressView("Generating QR…")
                    .frame(width: 100, height: 100)
            }

            Spacer()

            if #available(macOS 26.0, *) {
                Label {
                    Text(info.text)
                        .foregroundColor(info.color)
                } icon: {
                    Image(systemName: info.icon)
                        .foregroundColor(info.color)
                }
                .padding()
                .background(.clear)
                .glassEffect(in: .rect(cornerRadius: 20))
                .padding()
            } else {
                Label {
                    Text(info.text)
                        .foregroundColor(info.color)
                } icon: {
                    Image(systemName: info.icon)
                        .foregroundColor(info.color)
                }
                .padding()
            }
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
            ip: getLocalIPAddress(),
            port: UInt16(appState.myDevice?.port ?? Int(Defaults.serverPort)),
            name: appState.myDevice?.name
        ) ?? "That doesn't look right"

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let builder = try QRCode.build
                    .text(text)
                    .quietZonePixelCount(2)
                    .eye.shape(QRCode.EyeShape.RoundedPointingIn())
                    .onPixels.shape(QRCode.PixelShape.Blob())
                    .foregroundColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1.0))
                    .backgroundColor(CGColor(srgbRed: 0.0, green: 0.0, blue: 0.0, alpha: 1.0))
                    .background.cornerRadius(4)

                let imageData = try builder.generate.image(dimension: 200, representation: .png())

                guard let provider = CGDataProvider(data: imageData as CFData),
                      let cgImage = CGImage(
                        pngDataProviderSource: provider,
                        decode: nil,
                        shouldInterpolate: false,
                        intent: .defaultIntent
                      ) else {
                    print("Failed to convert PNG data to CGImage")
                    return
                }

                DispatchQueue.main.async {
                    self.qrImage = cgImage
                }
            } catch {
                print("❌ QR generation failed: \(error)")
            }
        }
    }
}

func generateQRText(ip: String?, port: UInt16?, name: String?) -> String? {
    guard let ip = ip, let port = port else {
        return nil
    }

    let encodedName = name?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Unknown"
    return "airsync://\(ip):\(port)?name=\(encodedName)?plus=\(AppState.shared.isPlus)"
}



#Preview {
    ScannerView()
}
