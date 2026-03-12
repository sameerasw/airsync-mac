//
//  TabIdentifier.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2025-09-20.
//

import SwiftUI

enum TabIdentifier: String, CaseIterable, Identifiable {
    case notifications = "notifications.tab"
    case apps = "apps.tab"
    case settings = "settings.tab"
    case qr = "qr.tab"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .notifications: return "bell.badge"
        case .apps: return "app"
        case .settings: return "gear"
        case .qr: return "qrcode"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .notifications: return "1"
        case .apps: return "2"
        case .settings: return ","
        case .qr: return "."
        }
    }

    static var availableTabs: [TabIdentifier] {
        var tabs: [TabIdentifier] = [.qr, .settings]
        if AppState.shared.device != nil {
            tabs.remove(at: 0)
            tabs.insert(.notifications, at: 0)
            tabs.insert(.apps, at: 1)
        }
        return tabs
    }
}
