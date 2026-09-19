//
//  AppShortcut.swift
//  AirSync
//

import SwiftUI
import KeyboardShortcuts

enum ShortcutScope: String, Hashable {
    case inApp
    case global

    var label: String {
        switch self {
        case .inApp: return "In-App"
        case .global: return "Global"
        }
    }
}

struct AppShortcutDefinition: Identifiable {
    let id: String
    let name: String
    let icon: String
    let key: KeyEquivalent
    let modifiers: EventModifiers
    let globalName: KeyboardShortcuts.Name
    let defaultScope: ShortcutScope

    var displayString: String {
        var symbols = ""
        if modifiers.contains(.control) { symbols += "⌃" }
        if modifiers.contains(.option) { symbols += "⌥" }
        if modifiers.contains(.shift) { symbols += "⇧" }
        if modifiers.contains(.command) { symbols += "⌘" }
        symbols += String(key.character).uppercased()
        return symbols
    }
}

extension KeyboardShortcuts.Name {
    static let summonScreenshot = Self("summonScreenshot", default: .init(.s, modifiers: [.control, .shift]))
    static let shortcutSettings = Self("shortcutSettings", default: .init(.comma, modifiers: [.command]))
    static let shortcutHelp = Self("shortcutHelp", default: .init(.slash, modifiers: [.command]))
    static let shortcutMirrorPrimary = Self("shortcutMirrorPrimary", default: .init(.p, modifiers: [.command]))
    static let shortcutMirrorAlternate = Self("shortcutMirrorAlternate", default: .init(.p, modifiers: [.command, .shift]))
    static let shortcutDesktopPrimary = Self("shortcutDesktopPrimary", default: .init(.d, modifiers: [.command]))
    static let shortcutDesktopAlternate = Self("shortcutDesktopAlternate", default: .init(.d, modifiers: [.command, .shift]))
    static let shortcutMirrorHere = Self("shortcutMirrorHere", default: .init(.s, modifiers: [.command, .shift]))
}

enum AppShortcuts {
    static let settings = AppShortcutDefinition(
        id: "settings", name: "Settings", icon: "gearshape",
        key: ",", modifiers: [.command],
        globalName: .shortcutSettings, defaultScope: .inApp
    )
    static let help = AppShortcutDefinition(
        id: "help", name: "Help", icon: "questionmark.circle",
        key: "/", modifiers: [.command],
        globalName: .shortcutHelp, defaultScope: .inApp
    )
    static let mirrorPrimary = AppShortcutDefinition(
        id: "mirror_primary", name: "Mirror (Primary)", icon: "apps.iphone",
        key: "p", modifiers: [.command],
        globalName: .shortcutMirrorPrimary, defaultScope: .inApp
    )
    static let mirrorAlternate = AppShortcutDefinition(
        id: "mirror_alternate", name: "Mirror (Alternate)", icon: "apps.iphone",
        key: "p", modifiers: [.command, .shift],
        globalName: .shortcutMirrorAlternate, defaultScope: .inApp
    )
    static let desktopPrimary = AppShortcutDefinition(
        id: "desktop_primary", name: "Desktop Mirror (Primary)", icon: "desktopcomputer",
        key: "d", modifiers: [.command],
        globalName: .shortcutDesktopPrimary, defaultScope: .inApp
    )
    static let desktopAlternate = AppShortcutDefinition(
        id: "desktop_alternate", name: "Desktop Mirror (Alternate)", icon: "desktopcomputer",
        key: "d", modifiers: [.command, .shift],
        globalName: .shortcutDesktopAlternate, defaultScope: .inApp
    )
    static let mirrorHere = AppShortcutDefinition(
        id: "mirror_here", name: "Mirror Here (Sidebar)", icon: "sidebar.right",
        key: "s", modifiers: [.command, .shift],
        globalName: .shortcutMirrorHere, defaultScope: .inApp
    )
    static let summon = AppShortcutDefinition(
        id: "summon", name: "Summon Screenshot", icon: "camera.viewfinder",
        key: "s", modifiers: [.control, .shift],
        globalName: .summonScreenshot, defaultScope: .global
    )

    static let all: [AppShortcutDefinition] = [
        settings, help, mirrorPrimary, mirrorAlternate, desktopPrimary, desktopAlternate, mirrorHere, summon
    ]
}

extension View {
    @ViewBuilder
    func appShortcut(_ definition: AppShortcutDefinition, appState: AppState) -> some View {
        if appState.scope(for: definition.id) == .inApp {
            self.keyboardShortcut(definition.key, modifiers: definition.modifiers)
        } else {
            self
        }
    }
}
