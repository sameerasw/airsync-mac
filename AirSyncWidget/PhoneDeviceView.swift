//
//  PhoneDeviceView.swift
//  AirSyncWidget
//

import SwiftUI
import AppKit

struct PhoneDeviceView: View {
    let wallpaperImageData: Data?

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
            }
        }
        .aspectRatio(CGSize(width: 60, height: 120), contentMode: .fit)
        .cornerRadius(10)
    }
}

#Preview {
    PhoneDeviceView(wallpaperImageData: nil)
        .frame(height: 100)
}
