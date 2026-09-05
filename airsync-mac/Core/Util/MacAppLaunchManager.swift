//
//  MacAppLaunchManager.swift
//  airsync-mac
//

import AppKit
import Foundation

/// Responsible for launching the user-configured Mac app or web URL
/// when a mirrored Android notification is clicked.
struct MacAppLaunchManager {

    /// Open the configured target for the given Android package name.
    /// - Returns: `true` if a preference was found and the launch was attempted.
    @discardableResult
    static func open(package: String) -> Bool {
        // 1. Check user-saved preference (overrides defaults)
        if let pref = AppState.shared.notificationLaunchPreferences[package] {
            switch pref.target {
            case .disabled:
                return false    // user explicitly disabled
            case .macApp, .webURL:
                break    // handled below
            }
            return launch(target: pref.target, package: package)
        }

        // 2. Fall back to pre-configured default (resolved at runtime)
        if let entry = NotificationLaunchDefaults.findDefault(for: package) {
            let target = NotificationLaunchDefaults.resolveTarget(for: entry)
            return launch(target: target, package: package)
        }

        return false
    }

    private static func launch(target: MacAppLaunchPreference.LaunchTarget, package: String) -> Bool {
        switch target {
        case .macApp(let bundleID, _):
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                print("[MacAppLaunchManager] App '\(bundleID)' not found — may have been uninstalled.")
                return false
            }
            NSWorkspace.shared.openApplication(at: appURL, configuration: .init()) { _, error in
                if let error = error {
                    print("[MacAppLaunchManager] Failed to open '\(bundleID)': \(error)")
                }
            }
            return true

        case .webURL(var urlString):
            // Auto-prepend https:// if no scheme present
            if !urlString.lowercased().hasPrefix("http://") && !urlString.lowercased().hasPrefix("https://") {
                urlString = "https://\(urlString)"
            }
            guard let url = URL(string: urlString),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                print("[MacAppLaunchManager] Invalid URL '\(urlString)' for package '\(package)'.")
                return false
            }
            NSWorkspace.shared.open(url)
            return true

        case .disabled:
            return false
        }
    }
}
