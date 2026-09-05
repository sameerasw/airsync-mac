//
//  SettingsTab.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2026-05-20.
//

import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case myMac = "my_mac"
    case sync = "sync"
    case notifications = "notifications"
    case mirroring = "mirroring"
    case quickShare = "quick_share"
    case menubar = "menubar"
    case appleIntelligence = "apple_intelligence"
    case appearance = "appearance"
    case airsyncPlus = "airsync_plus"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .myMac:
            return L("settings.myMac")
        case .sync:
            return L("settings.sync")
        case .notifications:
            return L("settings.notifications")
        case .mirroring:
            return L("settings.mirroring")
        case .quickShare:
            return L("settings.quickshare")
        case .menubar:
            return L("settings.menubar")
        case .appleIntelligence:
            return L("settings.appleIntelligence")
        case .appearance:
            return L("settings.appearance")
        case .airsyncPlus:
            return L("settings.airsyncPlus")
        }
    }

    var icon: String {
        switch self {
        case .myMac:
            return DeviceTypeUtil.deviceIconName()
        case .sync:
            return "arrow.triangle.2.circlepath"
        case .notifications:
            return "bell"
        case .mirroring:
            return "apps.iphone.badge.plus"
        case .quickShare:
            return "laptopcomputer.and.arrow.down"
        case .menubar:
            return "menubar.arrow.up.rectangle"
        case .appleIntelligence:
            return "sparkles"
        case .appearance:
            return "paintbrush"
        case .airsyncPlus:
            return "plus.diamond.fill"
        }
    }
}
