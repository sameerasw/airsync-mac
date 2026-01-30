//
//  MacInfo.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-09-18.
//

import Foundation

struct MacInfo: Codable {
    let name: String
    let categoryType: String
    let exactDeviceName: String
    let isPlusSubscription: Bool
    let version: String
    let savedAppPackages: [String]
}