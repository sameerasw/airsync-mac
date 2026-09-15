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

    var body: some View {
        if entry.isPaired {
            if widgetFamily == .systemMedium {
                mediumLayout
            } else {
                smallLayout
            }
        } else {
            disconnectedLayout
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

                HStack(spacing: 4) {
                    Image(systemName: "battery.100percent")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                    Text("\(entry.batteryLevel)%")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundColor(.secondary)

                    if entry.isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.green)
                    }
                }
            }
        }
        .padding(12)
        .containerBackground(Color(nsColor: .controlBackgroundColor), for: .widget)
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
        .containerBackground(Color(nsColor: .controlBackgroundColor), for: .widget)
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

            if let artData = entry.musicAlbumArtData, let nsImage = NSImage(data: artData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    )
            }
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
            }

            Text(entry.deviceName)
                .font(.system(.caption, design: .rounded))
                .lineLimit(1)
                .foregroundColor(.primary)
        }
        .padding(12)
        .containerBackground(Color(nsColor: .controlBackgroundColor), for: .widget)
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
        .supportedFamilies([.systemSmall, .systemMedium])
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
        if let base64String = shared?.string(forKey: "wallpaperBase64") {
            wallpaperData = Data(base64Encoded: base64String)
        }

        let isLocalNetwork = shared?.bool(forKey: WIDGET_DATA_KEYS.isLocalNetwork) ?? false
        let isBLEConnected = shared?.bool(forKey: WIDGET_DATA_KEYS.isBLEConnected) ?? false
        let isADBConnected = shared?.bool(forKey: WIDGET_DATA_KEYS.isADBConnected) ?? false
        let adbMode = shared?.string(forKey: WIDGET_DATA_KEYS.adbMode) ?? "wireless"

        let isMusicPlaying = shared?.bool(forKey: "isMusicPlaying") ?? false
        let musicTitle = shared?.string(forKey: "musicTitle") ?? ""
        let musicArtist = shared?.string(forKey: "musicArtist") ?? ""
        var musicAlbumArtData: Data? = nil
        if let albumArtBase64 = shared?.string(forKey: "musicAlbumArt"), !albumArtBase64.isEmpty {
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
