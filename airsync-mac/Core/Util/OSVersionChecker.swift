//
//  OSVersionChecker.swift
//  airsync-mac
//
//  Created by GitHub Copilot on 2025-11-03.
//

import Foundation

/// Utility for checking macOS version compatibility
struct OSVersionChecker {
    /// Checks if the current system is running macOS 26 (Tahoe) or later
    /// - Returns: true if macOS 26 or later, false otherwise
    static var isMacOS26OrLater: Bool {
        if #available(macOS 15.0, *) {
            if #available(macOS 16.0, *) {
                return true
            }

            // For macOS 15.x (Sequoia) and below, return false
            return ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 15
        }

        // For macOS 14 and earlier
        return false
    }

    /// Human-readable macOS version
    static var osVersionString: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion)"
    }
}
