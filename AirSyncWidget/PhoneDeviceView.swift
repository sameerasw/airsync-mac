//
//  PhoneDeviceView.swift
//  AirSyncWidget
//

import SwiftUI
import AppKit
import WidgetKit

struct PhoneDeviceView: View {
    let wallpaperImageData: Data?

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.3))

            if let imageData = wallpaperImageData,
               let nsImage = NSImage(data: imageData) {
                renderedWallpaper(nsImage)
            }
        }
        .aspectRatio(CGSize(width: 60, height: 120), contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func renderedWallpaper(_ nsImage: NSImage) -> some View {
        if #available(macOS 15.0, *), renderingMode == .accented {
            Image(nsImage: nsImage)
                .resizable()
                .widgetAccentedRenderingMode(.accentedDesaturated)
                .scaledToFill()
                .clipped()
        } else {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFill()
                .clipped()
        }
    }
}

#Preview {
    PhoneDeviceView(wallpaperImageData: nil)
        .frame(height: 100)
}
