//
//  WidgetDataManager.swift
//  airsync-mac
//
//  Manages shared data between the main app and widgets using App Groups.

import Foundation
import WidgetKit

class WidgetDataManager {
    static let shared = WidgetDataManager()

    private let appGroupIdentifier = "group.sameerasw.airsync-mac.widget"

    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    private struct Snapshot: Equatable {
        let deviceName: String
        let batteryLevel: Int
        let isCharging: Bool
        let isPaired: Bool
        let wallpaperBase64: String?
        let isLocalNetwork: Bool
        let isBLEConnected: Bool
        let isADBConnected: Bool
        let adbMode: String
        let isMusicPlaying: Bool
        let musicTitle: String
        let musicArtist: String
        let musicAlbumArt: String
    }

    private var lastSnapshot: Snapshot?

    func updateWidgetData(deviceStatus: DeviceStatus?, deviceName: String, wallpaperBase64: String? = nil, isLocalNetwork: Bool = false, isBLEConnected: Bool = false, isADBConnected: Bool = false, adbMode: String = "wireless") {
        guard let shared = sharedDefaults else {
            print("[Widget] App Groups container not available - check App Groups capability")
            return
        }

        let isPaired = deviceStatus?.isPaired ?? false
        let batteryLevel = deviceStatus?.battery.level ?? 0
        let isCharging = deviceStatus?.battery.isCharging ?? false
        let isMusicPlaying = deviceStatus?.music?.isPlaying ?? false
        let musicTitle = deviceStatus?.music?.title ?? ""
        let musicArtist = deviceStatus?.music?.artist ?? ""
        let musicAlbumArt = deviceStatus?.music?.albumArt ?? ""

        let snapshot = Snapshot(
            deviceName: deviceName,
            batteryLevel: batteryLevel,
            isCharging: isCharging,
            isPaired: isPaired,
            wallpaperBase64: wallpaperBase64,
            isLocalNetwork: isLocalNetwork,
            isBLEConnected: isBLEConnected,
            isADBConnected: isADBConnected,
            adbMode: adbMode,
            isMusicPlaying: isMusicPlaying,
            musicTitle: musicTitle,
            musicArtist: musicArtist,
            musicAlbumArt: musicAlbumArt
        )

        guard snapshot != lastSnapshot else {
            return
        }
        lastSnapshot = snapshot

        shared.set(deviceName, forKey: "deviceName")
        shared.set(batteryLevel, forKey: "batteryLevel")
        shared.set(isCharging, forKey: "isCharging")
        shared.set(isPaired, forKey: "isPaired")

        if let base64 = wallpaperBase64 {
            shared.set(base64, forKey: "wallpaperBase64")
        }

        shared.set(isLocalNetwork, forKey: "isLocalNetwork")
        shared.set(isBLEConnected, forKey: "isBLEConnected")
        shared.set(isADBConnected, forKey: "isADBConnected")
        shared.set(adbMode, forKey: "adbMode")

        shared.set(isMusicPlaying, forKey: "isMusicPlaying")
        shared.set(musicTitle, forKey: "musicTitle")
        shared.set(musicArtist, forKey: "musicArtist")
        shared.set(musicAlbumArt, forKey: "musicAlbumArt")

        shared.synchronize()

        print("[Widget] Updated: \(deviceName), Battery: \(batteryLevel)%, Paired: \(isPaired)")

        DispatchQueue.main.async {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
