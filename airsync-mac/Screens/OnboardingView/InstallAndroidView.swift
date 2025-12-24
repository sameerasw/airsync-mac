//
//  InstallAndroidView.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2025-09-02.
//

import SwiftUI
import QRCode
internal import SwiftImageReadWrite

struct InstallAndroidView: View {

    let onNext: () -> Void
    @State private var qrImage: CGImage?

    var body: some View {
        VStack {
            Text("Get started by installing the app on your Android device.")
                .font(.title)
                .multilineTextAlignment(.center)
                .padding()

            if let qrImage = qrImage {
                Image(decorative: qrImage, scale: 1.0)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 190, height: 190)
                    .accessibilityLabel("QR Code to download AirSync Android app")
                    .shadow(radius: 10)
                    .padding()
                    .background(.black.opacity(0.6), in: .rect(cornerRadius: 30))
            } else {
                ProgressView("Generating QR…")
                    .frame(width: 100, height: 100)
            }

            Text("Scan the QR code to download the app from Google Play or use the below link.")
                .multilineTextAlignment(.center)
                .padding()


            GlassButtonView(
                label: "Install from web",
                size: .extraLarge,
                action: {
                    if let url = URL(string: "https://play.google.com/store/apps/details?id=com.sameerasw.airsync") {
                        NSWorkspace.shared.open(url)
                    }
                }
            )
            .transition(.identity)

            GlassButtonView(
                label: "I'm ready",
                systemImage: "apps.iphone.badge.checkmark",
                size: .extraLarge,
                primary: true,
                action: onNext
            )
            .transition(.identity)
        }
        .onAppear {
            if qrImage == nil {
                generateQRAsync()
            }
        }
    }

    /// Generates a QR code for the Android app download link
    func generateQRAsync() {
        let text = "https://play.google.com/store/apps/details?id=com.sameerasw.airsync"

        Task {
            if let cgImage = await QRCodeGenerator.generateQRCode(for: text) {
                DispatchQueue.main.async {
                    self.qrImage = cgImage
                }
            }
        }
    }
}

#Preview {
    InstallAndroidView(onNext: {})
}
