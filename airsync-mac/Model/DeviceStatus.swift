//
//  DeviceStatus.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-07-28.
//

import Foundation

struct DeviceStatus: Codable {
    struct Battery: Codable {
        let level: Int
        let isCharging: Bool
    }

    struct Music: Codable {
        let isPlaying: Bool
        let title: String
        let artist: String
        let volume: Int
        let isMuted: Bool
        let albumArt: String
        let likeStatus: String
        /// Total track duration in seconds. -1 means not available.
        let duration: Double
        /// Current playback position in seconds (corrected for network transit on Mac side).
        let position: Double
        /// True when Android is buffering — position is frozen, Mac timer should pause.
        let isBuffering: Bool
    }

    let battery: Battery
    let isPaired: Bool
    let music: Music
}
