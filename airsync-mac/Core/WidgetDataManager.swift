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

        shared.synchronize()

        print("[Widget] Updated: \(deviceName), Battery: \(batteryLevel)%, Paired: \(isPaired)")

        DispatchQueue.main.async {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func getWidgetData() -> (deviceName: String, batteryLevel: Int, isCharging: Bool, isPaired: Bool) {
        guard let shared = sharedDefaults else {
            return ("Unknown", 0, false, false)
        }

        let deviceName = shared.string(forKey: "deviceName") ?? "Unknown"
        let batteryLevel = shared.integer(forKey: "batteryLevel")
        let isCharging = shared.bool(forKey: "isCharging")
        let isPaired = shared.bool(forKey: "isPaired")

        return (deviceName, batteryLevel, isCharging, isPaired)
    }
}
