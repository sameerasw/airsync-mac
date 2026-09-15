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

    func updateWidgetData(deviceStatus: DeviceStatus?, deviceName: String, wallpaperBase64: String? = nil, isLocalNetwork: Bool = false, isBLEConnected: Bool = false, isADBConnected: Bool = false, adbMode: String = "wireless") {
        guard let shared = sharedDefaults else {
            print("[Widget] App Groups container not available - check App Groups capability")
            return
        }

        let isPaired = deviceStatus?.isPaired ?? false
        let batteryLevel = deviceStatus?.battery.level ?? 0
        let isCharging = deviceStatus?.battery.isCharging ?? false

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

        let isMusicPlaying = deviceStatus?.music?.isPlaying ?? false
        shared.set(isMusicPlaying, forKey: "isMusicPlaying")
        shared.set(deviceStatus?.music?.title ?? "", forKey: "musicTitle")
        shared.set(deviceStatus?.music?.artist ?? "", forKey: "musicArtist")
        shared.set(deviceStatus?.music?.albumArt ?? "", forKey: "musicAlbumArt")

        shared.synchronize()

        print("[Widget] Updated: \(deviceName), Battery: \(batteryLevel)%, Paired: \(isPaired)")

        DispatchQueue.main.async {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
