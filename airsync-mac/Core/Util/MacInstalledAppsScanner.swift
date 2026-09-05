//
//  MacInstalledAppsScanner.swift
//  airsync-mac
//

import AppKit
import Foundation

/// Represents a Mac app installed on this machine.
struct InstalledMacApp: Identifiable, Hashable {
    let id: String          // bundleIdentifier (unique)
    let bundleID: String
    let name: String        // Display name
    let icon: NSImage?

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: InstalledMacApp, rhs: InstalledMacApp) -> Bool { lhs.id == rhs.id }
}

/// Scans installed Mac applications from well-known directories.
/// Results are cached for the app session. Call `invalidateCache()` to force a re-scan.
actor MacInstalledAppsScanner {
    static let shared = MacInstalledAppsScanner()

    private var cache: [InstalledMacApp]? = nil

    private static let searchDirectories: [String] = [
        "/Applications",
        "\(NSHomeDirectory())/Applications",
        "/System/Applications",
        "/System/Applications/Utilities"
    ]

    /// Returns all installed apps, using a cached result if available.
    func getInstalledApps() async -> [InstalledMacApp] {
        if let cached = cache { return cached }
        let apps = await Task.detached(priority: .userInitiated) {
            MacInstalledAppsScanner.scanApps()
        }.value
        self.cache = apps
        return apps
    }

    func invalidateCache() {
        cache = nil
    }

    private static func scanApps() -> [InstalledMacApp] {
        let fm = FileManager.default
        var seen = Set<String>()
        var results: [InstalledMacApp] = []

        for dir in searchDirectories {
            let dirURL = URL(fileURLWithPath: dir)
            guard let contents = try? fm.contentsOfDirectory(
                at: dirURL,
                includingPropertiesForKeys: [.isApplicationKey],
                options: .skipsHiddenFiles
            ) else { continue }

            for url in contents where url.pathExtension == "app" {
                guard let bundle = Bundle(url: url),
                      let bundleID = bundle.bundleIdentifier,
                      !seen.contains(bundleID) else { continue }

                seen.insert(bundleID)

                let name = bundle.localizedInfoDictionary?["CFBundleName"] as? String
                    ?? bundle.infoDictionary?["CFBundleName"] as? String
                    ?? url.deletingPathExtension().lastPathComponent

                let icon = NSWorkspace.shared.icon(forFile: url.path)

                results.append(InstalledMacApp(
                    id: bundleID,
                    bundleID: bundleID,
                    name: name,
                    icon: icon
                ))
            }
        }

        return results.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
}
