//
//  DeviceStatus.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-07-28.
//

import Foundation

struct DeviceStatus: Codable {
    struct Battery: Codable {
        var level: Int
        var isCharging: Bool
    }

    struct Music: Codable {
        var isPlaying: Bool
        var title: String
        var artist: String
        var volume: Int
        var isMuted: Bool
        var albumArt: String
        var likeStatus: String
        /// Total track duration in seconds. -1 means not available.
        var duration: Double
        /// Current playback position in seconds (corrected for network transit on Mac side).
        var position: Double
        /// True when Android is buffering — position is frozen, Mac timer should pause.
        var isBuffering: Bool
    }

    var battery: Battery
    var isPaired: Bool
    var music: Music?
}
