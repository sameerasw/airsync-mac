//
//  NotificationLaunchDefaults.swift
//  airsync-mac
//

import Foundation
import AppKit

struct NotificationAppDefault {
    let androidPackage: String
    let androidAppName: String
    let macBundleID: String?        // nil = no Mac app exists
    let webFallbackURL: String
    var packagePattern: String? = nil
}

struct NotificationLaunchDefaults {
    /// All pre-configured apps. Ordered by display importance.
    static let all: [NotificationAppDefault] = [
        .init(androidPackage: "com.whatsapp",             androidAppName: "WhatsApp",
              macBundleID: "net.whatsapp.WhatsApp",       webFallbackURL: "https://web.whatsapp.com"),
        .init(androidPackage: "com.whatsapp.w4b",         androidAppName: "WhatsApp Business",
              macBundleID: "net.whatsapp.WhatsApp",       webFallbackURL: "https://web.whatsapp.com"),
        .init(androidPackage: "org.telegram.messenger",   androidAppName: "Telegram",
              macBundleID: "ru.keepcoder.Telegram",       webFallbackURL: "https://web.telegram.org"),
        .init(androidPackage: "com.instagram.android",    androidAppName: "Instagram",
              macBundleID: nil,                            webFallbackURL: "https://www.instagram.com"),
        .init(androidPackage: "com.twitter.android",      androidAppName: "X (Twitter)",
              macBundleID: "com.twitter.twitter-mac",     webFallbackURL: "https://x.com"),
        .init(androidPackage: "com.google.android.gm",   androidAppName: "Gmail",
              macBundleID: nil,                            webFallbackURL: "https://mail.google.com"),
        .init(androidPackage: "com.Slack",                androidAppName: "Slack",
              macBundleID: "com.tinyspeck.slackmacgap",   webFallbackURL: "https://app.slack.com"),
        .init(androidPackage: "com.discord",              androidAppName: "Discord",
              macBundleID: "com.hammerandchisel.discord",  webFallbackURL: "https://discord.com"),
        .init(androidPackage: "com.facebook.orca",        androidAppName: "Messenger",
              macBundleID: "com.facebook.Messenger",      webFallbackURL: "https://www.messenger.com"),
        .init(androidPackage: "com.spotify.music",        androidAppName: "Spotify",
              macBundleID: "com.spotify.client",          webFallbackURL: "https://open.spotify.com"),
        .init(androidPackage: "com.microsoft.office.outlook", androidAppName: "Outlook",
              macBundleID: "com.microsoft.Outlook",       webFallbackURL: "https://outlook.live.com"),
        .init(androidPackage: "notion.id",                androidAppName: "Notion",
              macBundleID: "notion.id",                   webFallbackURL: "https://notion.so"),
        .init(androidPackage: "com.netflix.mediaclient",  androidAppName: "Netflix",
              macBundleID: nil,                            webFallbackURL: "https://www.netflix.com"),
        .init(androidPackage: "com.amazon.mShop.android.shopping", androidAppName: "Amazon",
              macBundleID: nil,                            webFallbackURL: "https://www.amazon.in",
              packagePattern: "^.*amazon\\.mShop\\.android\\.shopping$"),
        .init(androidPackage: "com.amazon.avod.thirdpartyclient", androidAppName: "Prime Video",
              macBundleID: "com.amazon.aiv.us",           webFallbackURL: "https://www.primevideo.com"),
        .init(androidPackage: "com.flipkart.android",     androidAppName: "Flipkart",
              macBundleID: nil,                            webFallbackURL: "https://www.flipkart.com"),
        .init(androidPackage: "in.startv.hotstar",        androidAppName: "JioHotstar",
              macBundleID: nil,                            webFallbackURL: "https://www.hotstar.com"),
        .init(androidPackage: "com.linkedin.android",     androidAppName: "LinkedIn",
              macBundleID: nil,                            webFallbackURL: "https://www.linkedin.com"),
        .init(androidPackage: "com.google.android.youtube", androidAppName: "YouTube",
              macBundleID: nil,                            webFallbackURL: "https://www.youtube.com"),
        .init(androidPackage: "com.google.android.apps.youtube.music", androidAppName: "YouTube Music",
              macBundleID: nil,                            webFallbackURL: "https://music.youtube.com"),
        .init(androidPackage: "com.goibibo",              androidAppName: "Goibibo",
              macBundleID: nil,                            webFallbackURL: "https://www.goibibo.com"),
        .init(androidPackage: "com.makemytrip",           androidAppName: "MakeMyTrip",
              macBundleID: nil,                            webFallbackURL: "https://www.makemytrip.com"),
        .init(androidPackage: "net.blip.android",          androidAppName: "Blip",
              macBundleID: "net.blip.macos",              webFallbackURL: "https://blip.net"),
        .init(androidPackage: "com.google.android.apps.classroom", androidAppName: "Google Classroom",
              macBundleID: nil,                            webFallbackURL: "https://classroom.google.com"),
        .init(androidPackage: "com.anthropic.claude",     androidAppName: "Claude",
              macBundleID: "com.anthropic.claudefordesktop", webFallbackURL: "https://claude.ai"),
        .init(androidPackage: "com.openai.chatgpt",       androidAppName: "ChatGPT",
              macBundleID: "com.openai.chat",             webFallbackURL: "https://chatgpt.com"),
        .init(androidPackage: "com.google.android.apps.bard", androidAppName: "Gemini",
              macBundleID: "com.google.gemini",           webFallbackURL: "https://gemini.google.com"),
        .init(androidPackage: "com.reddit.frontpage",      androidAppName: "Reddit",
              macBundleID: nil,                            webFallbackURL: "https://www.reddit.com"),
    ]

    static let byPackage: [String: NotificationAppDefault] = 
        Dictionary(uniqueKeysWithValues: all.map { ($0.androidPackage, $0) })

    static func findDefault(for package: String) -> NotificationAppDefault? {
        if let exact = byPackage[package] {
            return exact
        }
        for entry in all {
            if let pattern = entry.packagePattern,
               let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(location: 0, length: package.utf16.count)
                if regex.firstMatch(in: package, options: [], range: range) != nil {
                    return entry
                }
            }
        }
        return nil
    }

    /// Resolve at runtime: check if Mac app is installed, else use web fallback.
    static func resolveTarget(for entry: NotificationAppDefault) -> MacAppLaunchPreference.LaunchTarget {
        if let bundleID = entry.macBundleID,
           NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil {
            return .macApp(bundleID: bundleID, appName: entry.androidAppName)
        }
        return .webURL(urlString: entry.webFallbackURL)
    }

    /// Build a synthetic AndroidApp for sheet presentation when real app hasn't appeared yet.
    static func syntheticAndroidApp(for entry: NotificationAppDefault) -> AndroidApp {
        AndroidApp(packageName: entry.androidPackage, name: entry.androidAppName,
                   iconUrl: nil, listening: false, systemApp: false)
    }
}
