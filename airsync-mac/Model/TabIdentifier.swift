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
    case transfers = "transfers.tab"
    case calls = "calls.tab"
    case messages = "messages.tab"
    case health = "health.tab"
    case settings = "settings.tab"
    case qr = "qr.tab"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .notifications: return "bell.badge"
        case .apps: return "app"
        case .transfers: return "tray.and.arrow.up"
        case .calls: return "phone.fill"
        case .messages: return "message.fill"
        case .health: return "heart.fill"
        case .settings: return "gear"
        case .qr: return "qrcode"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .notifications: return "1"
        case .apps: return "2"
        case .transfers: return "3"
        case .calls: return "4"
        case .messages: return "5"
        case .health: return "6"
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
            tabs.insert(.transfers, at: 2)
            tabs.insert(.calls, at: 3)
            tabs.insert(.messages, at: 4)
            tabs.insert(.health, at: 5)
        }
        return tabs
    }
}
