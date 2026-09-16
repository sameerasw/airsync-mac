//
//  ShortcutManager.swift
//  AirSync
//
//  Registers every app shortcut's global (KeyboardShortcuts/Carbon) handler exactly once, then
//  enables/disables it based on the user's chosen scope — global handlers never fire while
//  scope is "In-App", so the SwiftUI in-app bindings (see AppShortcut.appShortcut) stay the
//  only thing that responds.
//

import Foundation
import KeyboardShortcuts

enum ShortcutManager {
    private static var didRegisterHandlers = false

    static func registerIfNeeded() {
        guard !didRegisterHandlers else { return }
        didRegisterHandlers = true

        for definition in AppShortcuts.all {
            KeyboardShortcuts.onKeyUp(for: definition.globalName) {
                action(for: definition.id)()
            }
        }

        applyAllScopes()
    }

    static func applyAllScopes() {
        for definition in AppShortcuts.all {
            applyScope(for: definition)
        }
    }

    static func applyScope(for definition: AppShortcutDefinition) {
        if AppState.shared.scope(for: definition.id) == .global {
            KeyboardShortcuts.enable(definition.globalName)
        } else {
            KeyboardShortcuts.disable(definition.globalName)
        }
    }

    private static func action(for id: String) -> () -> Void {
        switch id {
        case AppShortcuts.settings.id: return AppShortcutActions.openSettings
        case AppShortcuts.help.id: return AppShortcutActions.openHelp
        case AppShortcuts.mirrorPrimary.id: return AppShortcutActions.mirrorPrimary
        case AppShortcuts.mirrorAlternate.id: return AppShortcutActions.mirrorAlternate
        case AppShortcuts.desktopPrimary.id: return AppShortcutActions.desktopPrimary
        case AppShortcuts.desktopAlternate.id: return AppShortcutActions.desktopAlternate
        case AppShortcuts.mirrorHere.id: return AppShortcutActions.toggleMirrorHere
        case AppShortcuts.summon.id: return { SummonManager.shared.summonScreenshot() }
        default: return {}
        }
    }
}
