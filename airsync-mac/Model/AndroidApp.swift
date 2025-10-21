//
//  AndroidApp.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-07-28.
//

import Foundation

struct AndroidApp: Hashable, Identifiable, Codable {
    let id = UUID()

    let packageName: String
    let name: String
    var iconUrl: String?
    var listening: Bool
    let systemApp: Bool

    private enum CodingKeys: String, CodingKey {
        case packageName, name, iconUrl, listening, systemApp
    }
}
