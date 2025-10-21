//
//  PinnedApp.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-10-22.
//

import Foundation

/// Represents a pinned app in the floating dock
struct PinnedApp: Identifiable, Codable {
    let id = UUID()
    let packageName: String
    let appName: String
    let iconUrl: String?
    
    private enum CodingKeys: String, CodingKey {
        case packageName, appName, iconUrl
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(packageName, forKey: .packageName)
        try container.encode(appName, forKey: .appName)
        try container.encode(iconUrl, forKey: .iconUrl)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.packageName = try container.decode(String.self, forKey: .packageName)
        self.appName = try container.decode(String.self, forKey: .appName)
        self.iconUrl = try container.decode(String?.self, forKey: .iconUrl)
    }
    
    init(packageName: String, appName: String, iconUrl: String?) {
        self.packageName = packageName
        self.appName = appName
        self.iconUrl = iconUrl
    }
}
