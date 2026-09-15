//
//  PhoneInfoWidget.swift
//  AirSyncWidget
//
//  Created by Sameera Sandakelum on 2026-09-15.
//

import WidgetKit
import SwiftUI
import AppKit

struct PhoneInfoEntry: TimelineEntry {
    let date: Date
    let deviceName: String
    let batteryLevel: Int
    let isCharging: Bool
    let isPaired: Bool
    let wallpaperImageData: Data?
    let isLocalNetwork: Bool
    let isBLEConnected: Bool
    let isADBConnected: Bool
    let adbMode: String
    let isMusicPlaying: Bool
    let musicTitle: String
    let musicArtist: String
    let musicAlbumArtData: Data?
}

struct PhoneInfoWidgetEntryView: View {
    var entry: PhoneInfoEntry
    @Environment(\.widgetFamily) var widgetFamily
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.widgetContentMargins) private var contentMargins

    var body: some View {
        if entry.isPaired {
            switch widgetFamily {
            case .systemLarge:
                largeLayout
            case .systemMedium:
                mediumLayout
            default:
                smallLayout
            }
        } else {
            disconnectedLayout
        }
    }

    @ViewBuilder
    private var glassBackground: some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(in: .rect(cornerRadius: 0))
        } else {
            Color.clear.background(.ultraThinMaterial)
        }
    }

    private var smallLayout: some View {
        VStack(spacing: 8) {
            PhoneDeviceView(wallpaperImageData: entry.wallpaperImageData)
                .frame(maxHeight: 100)

            VStack(spacing: 2) {
                Text(entry.deviceName)
                    .font(.system(.caption, design: .rounded))
                    .lineLimit(1)
                    .foregroundColor(.primary)

                BatteryIconView(level: entry.batteryLevel, isCharging: entry.isCharging)
            }
            .widgetAccentable()
        }
        .padding(12)
        .padding(contentMargins)
        .containerBackground(for: .widget) { glassBackground }
    }

    private var mediumLayout: some View {
        HStack(spacing: 0) {
            PhoneDeviceView(wallpaperImageData: entry.wallpaperImageData)
                .frame(maxHeight: 110)
                .padding(.trailing, 20)

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                Text(entry.deviceName)
                    .font(.system(.headline, design: .rounded))
                    .lineLimit(2)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.trailing)
                    .widgetAccentable()

                if entry.isMusicPlaying {
                    statusIconsRow
                    Spacer()
                    mediaPlayerRow
                } else {
                    Spacer()
                    statusIconsRow
                }
            }
        }
        .padding(16)
        .padding(contentMargins)
        .containerBackground(for: .widget) { glassBackground }
    }

    private var largeLayout: some View {
        ZStack {
            if let nsImage = largeBackgroundNSImage {
                GeometryReader { geo in
                    ZStack {
                        largeBackgroundImage(nsImage)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()

                        blurredBackgroundLayer(nsImage, size: geo.size, radius: 6, fadeStart: 0.35)
                        blurredBackgroundLayer(nsImage, size: geo.size, radius: 16, fadeStart: 0.55)
                        blurredBackgroundLayer(nsImage, size: geo.size, radius: 32, fadeStart: 0.75)
                    }
                }

                 LinearGradient(
                     colors: [.clear, .black.opacity(0.55)],
                     startPoint: .center,
                     endPoint: .bottom
                 )
                 .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                largeStatusIconsRow

                Spacer()

                if entry.isMusicPlaying {
                    VStack(spacing: 4) {
                        Text(entry.musicTitle)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .foregroundColor(.white)
                        Text(entry.musicArtist)
                            .font(.subheadline)
                            .lineLimit(1)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .multilineTextAlignment(.center)

                    Spacer()
                }

                Text(entry.deviceName)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(contentMargins)
        }
        .containerBackground(for: .widget) { glassBackground }
    }

    private var largeStatusIconsRow: some View {
        HStack(spacing: 6) {
            if entry.isLocalNetwork {
                Image(systemName: "wifi")
                    .font(.system(size: 10))
            }
            if entry.isADBConnected {
                Image(systemName: entry.adbMode == "wired" ? "cable.connector" : "iphone.gen3.crop.circle")
                    .font(.system(size: 10))
            }
            if entry.isBLEConnected {
                Image(systemName: "bluetooth")
                    .font(.system(size: 10))
            }
            BatteryIconView(level: entry.batteryLevel, isCharging: entry.isCharging)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            .black.opacity(0.3)
//            .ultraThinMaterial
            , in: Capsule())
//        .widgetAccentable()
    }

    private var largeBackgroundNSImage: NSImage? {
        if entry.isMusicPlaying, let artData = entry.musicAlbumArtData, let nsImage = NSImage(data: artData) {
            return nsImage
        }
        if let wallpaperData = entry.wallpaperImageData, let nsImage = NSImage(data: wallpaperData) {
            return nsImage
        }
        return nil
    }

    private func blurredBackgroundLayer(
        _ nsImage: NSImage,
        size: CGSize,
        radius: CGFloat,
        fadeStart: CGFloat
    ) -> some View {
        largeBackgroundImage(nsImage)
            .frame(width: size.width, height: size.height)
            .blur(radius: radius)
            .scaleEffect(1.1)
            .clipped()
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: fadeStart),
                        .init(color: .white, location: min(fadeStart + 0.25, 1.0))
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }

    @ViewBuilder
    private func largeBackgroundImage(_ nsImage: NSImage) -> some View {
        if #available(macOS 15.0, *), renderingMode == .accented {
            Image(nsImage: nsImage)
                .resizable()
                .widgetAccentedRenderingMode(.accentedDesaturated)
                .scaledToFill()
        } else {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFill()
        }
    }

    private var statusIconsRow: some View {
        HStack(spacing: 6) {
            if entry.isLocalNetwork {
                Image(systemName: "wifi")
                    .font(.system(size: 10))
            }
            if entry.isADBConnected {
                Image(systemName: entry.adbMode == "wired" ? "cable.connector" : "iphone.gen3.crop.circle")
                    .font(.system(size: 10))
            }
            if entry.isBLEConnected {
                Image(systemName: "bluetooth")
                    .font(.system(size: 10))
            }
            BatteryIconView(level: entry.batteryLevel, isCharging: entry.isCharging)
        }
        .foregroundColor(.secondary)
        .widgetAccentable()
    }

    private var mediaPlayerRow: some View {
        HStack(spacing: 10) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.musicTitle)
                    .font(.system(.caption, design: .rounded))
                    .lineLimit(1)
                    .foregroundColor(.primary)
                Text(entry.musicArtist)
                    .font(.system(.caption2, design: .rounded))
                    .lineLimit(1)
                    .foregroundColor(.secondary)
            }
            .widgetAccentable()

            if let artData = entry.musicAlbumArtData, let nsImage = NSImage(data: artData) {
                renderedAlbumArt(nsImage)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    )
                    .widgetAccentable()
            }
        }
    }

    @ViewBuilder
    private func renderedAlbumArt(_ nsImage: NSImage) -> some View {
        if #available(macOS 15.0, *), renderingMode == .accented {
            Image(nsImage: nsImage)
                .resizable()
                .widgetAccentedRenderingMode(.accentedDesaturated)
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var disconnectedLayout: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                PhoneDeviceView(wallpaperImageData: entry.wallpaperImageData)
                    .frame(maxHeight: 100)
                    .grayscale(1)
                    .opacity(0.6)

                Image(systemName: "iphone.slash")
                    .font(.system(size: 20))
                    .foregroundColor(.gray)
                    .padding(4)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                    .offset(x: 8, y: 8)
                    .widgetAccentable()
            }

            Text(entry.deviceName)
                .font(.system(.caption, design: .rounded))
                .lineLimit(1)
                .foregroundColor(.primary)
                .widgetAccentable()
        }
        .padding(12)
        .padding(contentMargins)
        .containerBackground(for: .widget) { glassBackground }
    }
}

struct PhoneInfoWidget: Widget {
    let kind: String = "PhoneInfoWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PhoneInfoProvider()) { entry in
            PhoneInfoWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Phone Info")
        .description("Display your connected phone's battery and status")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct PhoneInfoProvider: TimelineProvider {
    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: APP_GROUP_IDENTIFIER)
    }

    private func getSharedData() -> PhoneInfoEntry {
        let shared = sharedDefaults
        let deviceName = shared?.string(forKey: WIDGET_DATA_KEYS.deviceName) ?? "Unknown"
        let batteryLevel = shared?.integer(forKey: WIDGET_DATA_KEYS.batteryLevel) ?? 0
        let isCharging = shared?.bool(forKey: WIDGET_DATA_KEYS.isCharging) ?? false
        let isPaired = shared?.bool(forKey: WIDGET_DATA_KEYS.isPaired) ?? false

        var wallpaperData: Data? = nil
        if let base64String = shared?.string(forKey: WIDGET_DATA_KEYS.wallpaperBase64) {
            wallpaperData = Data(base64Encoded: base64String)
        }

        let isLocalNetwork = shared?.bool(forKey: WIDGET_DATA_KEYS.isLocalNetwork) ?? false
        let isBLEConnected = shared?.bool(forKey: WIDGET_DATA_KEYS.isBLEConnected) ?? false
        let isADBConnected = shared?.bool(forKey: WIDGET_DATA_KEYS.isADBConnected) ?? false
        let adbMode = shared?.string(forKey: WIDGET_DATA_KEYS.adbMode) ?? "wireless"

        let isMusicPlaying = shared?.bool(forKey: WIDGET_DATA_KEYS.isMusicPlaying) ?? false
        let musicTitle = shared?.string(forKey: WIDGET_DATA_KEYS.musicTitle) ?? ""
        let musicArtist = shared?.string(forKey: WIDGET_DATA_KEYS.musicArtist) ?? ""
        var musicAlbumArtData: Data? = nil
        if let albumArtBase64 = shared?.string(forKey: WIDGET_DATA_KEYS.musicAlbumArt), !albumArtBase64.isEmpty {
            musicAlbumArtData = Data(base64Encoded: albumArtBase64)
        }

        return PhoneInfoEntry(
            date: Date(),
            deviceName: deviceName,
            batteryLevel: batteryLevel,
            isCharging: isCharging,
            isPaired: isPaired,
            wallpaperImageData: wallpaperData,
            isLocalNetwork: isLocalNetwork,
            isBLEConnected: isBLEConnected,
            isADBConnected: isADBConnected,
            adbMode: adbMode,
            isMusicPlaying: isMusicPlaying,
            musicTitle: musicTitle,
            musicArtist: musicArtist,
            musicAlbumArtData: musicAlbumArtData
        )
    }

    func placeholder(in context: Context) -> PhoneInfoEntry {
        PhoneInfoEntry(
            date: Date(),
            deviceName: "Loading...",
            batteryLevel: 0,
            isCharging: false,
            isPaired: false,
            wallpaperImageData: nil,
            isLocalNetwork: false,
            isBLEConnected: false,
            isADBConnected: false,
            adbMode: "wireless",
            isMusicPlaying: false,
            musicTitle: "",
            musicArtist: "",
            musicAlbumArtData: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (PhoneInfoEntry) -> ()) {
        completion(getSharedData())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PhoneInfoEntry>) -> ()) {
        let currentDate = Date()
        let refreshDate = Calendar.current.date(byAdding: .second, value: 30, to: currentDate)!

        let entry = getSharedData()
        let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
        completion(timeline)
    }
}

#Preview("Small - Connected", as: .systemSmall) {
    PhoneInfoWidget()
} timeline: {
    PhoneInfoEntry(
        date: .now,
        deviceName: "Pixel 8",
        batteryLevel: 75,
        isCharging: false,
        isPaired: true,
        wallpaperImageData: nil,
        isLocalNetwork: false,
        isBLEConnected: false,
        isADBConnected: false,
        adbMode: "wireless",
        isMusicPlaying: false,
        musicTitle: "",
        musicArtist: "",
        musicAlbumArtData: nil
    )
}

#Preview("Small - Low Battery", as: .systemSmall) {
    PhoneInfoWidget()
} timeline: {
    PhoneInfoEntry(
        date: .now,
        deviceName: "Galaxy S24",
        batteryLevel: 15,
        isCharging: false,
        isPaired: true,
        wallpaperImageData: nil,
        isLocalNetwork: false,
        isBLEConnected: false,
        isADBConnected: false,
        adbMode: "wireless",
        isMusicPlaying: false,
        musicTitle: "",
        musicArtist: "",
        musicAlbumArtData: nil
    )
}

#Preview("Small - Charging", as: .systemSmall) {
    PhoneInfoWidget()
} timeline: {
    PhoneInfoEntry(
        date: .now,
        deviceName: "iPhone 15",
        batteryLevel: 45,
        isCharging: true,
        isPaired: true,
        wallpaperImageData: nil,
        isLocalNetwork: false,
        isBLEConnected: false,
        isADBConnected: false,
        adbMode: "wireless",
        isMusicPlaying: false,
        musicTitle: "",
        musicArtist: "",
        musicAlbumArtData: nil
    )
}

#Preview("Medium - Connected", as: .systemMedium) {
    PhoneInfoWidget()
} timeline: {
    PhoneInfoEntry(
        date: .now,
        deviceName: "Pixel 8 Pro",
        batteryLevel: 82,
        isCharging: true,
        isPaired: true,
        wallpaperImageData: nil,
        isLocalNetwork: true,
        isBLEConnected: false,
        isADBConnected: false,
        adbMode: "wireless",
        isMusicPlaying: false,
        musicTitle: "",
        musicArtist: "",
        musicAlbumArtData: nil
    )
}

#Preview("Medium - Playing Music", as: .systemMedium) {
    PhoneInfoWidget()
} timeline: {
    PhoneInfoEntry(
        date: .now,
        deviceName: "Pixel 8 Pro",
        batteryLevel: 82,
        isCharging: false,
        isPaired: true,
        wallpaperImageData: nil,
        isLocalNetwork: true,
        isBLEConnected: false,
        isADBConnected: true,
        adbMode: "wireless",
        isMusicPlaying: true,
        musicTitle: "Blinding Lights",
        musicArtist: "The Weeknd",
        musicAlbumArtData: nil
    )
}

#Preview("Large - Connected", as: .systemLarge) {
    PhoneInfoWidget()
} timeline: {
    PhoneInfoEntry(
        date: .now,
        deviceName: "Pixel 8 Pro",
        batteryLevel: 82,
        isCharging: true,
        isPaired: true,
        wallpaperImageData: nil,
        isLocalNetwork: true,
        isBLEConnected: false,
        isADBConnected: false,
        adbMode: "wireless",
        isMusicPlaying: false,
        musicTitle: "",
        musicArtist: "",
        musicAlbumArtData: nil
    )
}

#Preview("Large - Playing Music", as: .systemLarge) {
    PhoneInfoWidget()
} timeline: {
    PhoneInfoEntry(
        date: .now,
        deviceName: "Pixel 8 Pro",
        batteryLevel: 82,
        isCharging: false,
        isPaired: true,
        wallpaperImageData: nil,
        isLocalNetwork: true,
        isBLEConnected: false,
        isADBConnected: true,
        adbMode: "wireless",
        isMusicPlaying: true,
        musicTitle: "Blinding Lights",
        musicArtist: "The Weeknd",
        musicAlbumArtData: nil
    )
}

#Preview("Disconnected", as: .systemSmall) {
    PhoneInfoWidget()
} timeline: {
    PhoneInfoEntry(
        date: .now,
        deviceName: "Unknown",
        batteryLevel: 0,
        isCharging: false,
        isPaired: false,
        wallpaperImageData: nil,
        isLocalNetwork: false,
        isBLEConnected: false,
        isADBConnected: false,
        adbMode: "wireless",
        isMusicPlaying: false,
        musicTitle: "",
        musicArtist: "",
        musicAlbumArtData: nil
    )
}
