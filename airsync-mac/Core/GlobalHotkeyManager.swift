//
//  GlobalHotkeyManager.swift
//  airsync-mac
//
//  Registers a single configurable global keyboard shortcut that triggers Summon Screenshot
//  from anywhere on the system. Requires the user to grant Input Monitoring permission the
//  first time macOS prompts for it (standard for any app-wide NSEvent global monitor) — if
//  that permission isn't granted, the monitor simply never fires; there's no crash or error.
//

import AppKit

class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()

    private var monitor: Any?
    private let relevantFlags: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    private init() {}

    /// Default: Control+Shift+S
    var keyCode: UInt16 {
        get {
            let stored = UserDefaults.standard.object(forKey: "summonHotkeyKeyCode") as? Int
            return UInt16(stored ?? 1) // 1 = kVK_ANSI_S
        }
        set { UserDefaults.standard.set(Int(newValue), forKey: "summonHotkeyKeyCode") }
    }

    var modifierFlags: NSEvent.ModifierFlags {
        get {
            if let raw = UserDefaults.standard.object(forKey: "summonHotkeyModifiers") as? UInt {
                return NSEvent.ModifierFlags(rawValue: raw)
            }
            return [.control, .shift]
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "summonHotkeyModifiers") }
    }

    func registerIfNeeded() {
        unregister()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return }
            guard event.keyCode == self.keyCode,
                  event.modifierFlags.intersection(self.relevantFlags) == self.modifierFlags else { return }
            DispatchQueue.main.async {
                SummonManager.shared.summonScreenshot()
            }
        }
    }

    func unregister() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    var shortcutDisplayString: String {
        var parts: [String] = []
        if modifierFlags.contains(.control) { parts.append("⌃") }
        if modifierFlags.contains(.option) { parts.append("⌥") }
        if modifierFlags.contains(.shift) { parts.append("⇧") }
        if modifierFlags.contains(.command) { parts.append("⌘") }
        parts.append(Self.keyCodeToString(keyCode))
        return parts.joined()
    }

    /// Minimal keycode->label mapping (ANSI US layout), sufficient for the shortcut recorder
    /// display — good enough since this doesn't need to cover every possible key, just show
    /// back whatever the user just pressed.
    static func keyCodeToString(_ keyCode: UInt16) -> String {
        let map: [UInt16: String] = [
            0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J",
            40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T",
            32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
            18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
            49: "Space", 36: "Return", 48: "Tab", 53: "Escape"
        ]
        return map[keyCode] ?? "Key\(keyCode)"
    }
}
