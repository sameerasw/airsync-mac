//
//  PhoneDeviceView.swift
//  AirSyncWidget
//

import SwiftUI
import AppKit

struct PhoneDeviceView: View {
    let wallpaperImageData: Data?
    let isGrayscale: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.3))

            if let imageData = wallpaperImageData,
               let nsImage = NSImage(data: imageData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .clipped()
                    .grayscale(isGrayscale ? 1 : 0)
            }
        }
        .aspectRatio(CGSize(width: 60, height: 120), contentMode: .fit)
        .cornerRadius(10)
        .opacity(isGrayscale ? 0.6 : 1)
    }
}

#Preview {
    PhoneDeviceView(wallpaperImageData: nil)
        .frame(height: 100)
}
