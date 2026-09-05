//
//  MacAppLaunchPreference.swift
//  airsync-mac
//

import Foundation

/// Represents the user's configured launch target for a specific Android app's notifications.
struct MacAppLaunchPreference: Codable, Identifiable {

    enum LaunchTarget: Codable {
        case macApp(bundleID: String, appName: String)
        case webURL(urlString: String)
        case disabled

        private enum CodingKeys: String, CodingKey {
            case type, bundleID, appName, urlString
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .macApp(let bundleID, let appName):
                try container.encode("macApp", forKey: .type)
                try container.encode(bundleID, forKey: .bundleID)
                try container.encode(appName, forKey: .appName)
            case .webURL(let urlString):
                try container.encode("webURL", forKey: .type)
                try container.encode(urlString, forKey: .urlString)
            case .disabled:
                try container.encode("disabled", forKey: .type)
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type_ = try container.decode(String.self, forKey: .type)
            switch type_ {
            case "macApp":
                let bundleID = try container.decode(String.self, forKey: .bundleID)
                let appName = try container.decode(String.self, forKey: .appName)
                self = .macApp(bundleID: bundleID, appName: appName)
            case "webURL":
                let urlString = try container.decode(String.self, forKey: .urlString)
                self = .webURL(urlString: urlString)
            case "disabled":
                self = .disabled
            default:
                throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown LaunchTarget type: \(type_)")
            }
        }
    }

    /// The Android package name (e.g. "com.whatsapp")
    let androidPackage: String
    /// Display name of the Android app (stored for UI convenience)
    let androidAppName: String
    /// What to open on macOS when a notification from this app is clicked
    var target: LaunchTarget

    var id: String { androidPackage }

    /// Human-readable description of the configured target
    var targetDisplayName: String {
        switch target {
        case .macApp(_, let appName): return appName
        case .webURL(let urlString): return urlString
        case .disabled: return "Disabled"
        }
    }

    var targetSystemImage: String {
        switch target {
        case .macApp: return "desktopcomputer"
        case .webURL: return "globe"
        case .disabled: return "slash.circle"
        }
    }
}
