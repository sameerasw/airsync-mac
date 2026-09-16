//
//  GlobalHotkeyManager.swift
//  airsync-mac
//
//  Registers a single configurable global keyboard shortcut that triggers Summon Screenshot
//  from anywhere on the system. Uses the KeyboardShortcuts package (wraps the old Carbon
//  RegisterEventHotKey API) instead of an NSEvent global monitor — global key monitors need
//  the app to be Accessibility-trusted to reliably fire, whereas Carbon hotkey registration
//  does not require any special permission.
//

import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let summonScreenshot = Self("summonScreenshot", default: .init(.s, modifiers: [.control, .shift]))
}

enum GlobalHotkeyManager {
    static func registerIfNeeded() {
        KeyboardShortcuts.onKeyUp(for: .summonScreenshot) {
            SummonManager.shared.summonScreenshot()
        }
    }
}
