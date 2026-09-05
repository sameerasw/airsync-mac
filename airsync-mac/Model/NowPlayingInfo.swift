//
//  NowPlayingInfo.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2025-09-17.
//
import Foundation

struct NowPlayingInfo {
    var title: String? = "?"
    var artist: String? = "?"
    var album: String? = "?"
    var elapsedTime: Double? = 0
    var duration: Double? = 0
    var isPlaying: Bool? = false
    var artworkData: Data? = nil
    var artworkMimeType: String? = nil
    var bundleIdentifier: String? = nil
    var timestamp: String? = nil
    var playbackRate: Double? = 1.0

    mutating func updateFromPayload(_ payload: [String: Any]) {
        if let title = payload["title"] as? String { self.title = title }
        if let artist = payload["artist"] as? String { self.artist = artist }
        if let album = payload["album"] as? String { self.album = album }
        if let elapsed = payload["elapsedTime"] as? Double { self.elapsedTime = elapsed }
        if let duration = payload["duration"] as? Double { self.duration = duration }
        if let playing = payload["playing"] as? Bool { self.isPlaying = playing }
        if let rate = payload["playbackRate"] as? Double { self.playbackRate = rate }
        if let ts = payload["timestamp"] as? String { self.timestamp = ts }
        if let artworkBase64 = payload["artworkData"] as? String,
           let data = Data(base64Encoded: artworkBase64) {
            self.artworkData = data
        }
        if let mime = payload["artworkMimeType"] as? String { self.artworkMimeType = mime }
        if let bundleId = payload["bundleIdentifier"] as? String { self.bundleIdentifier = bundleId }
    }
}
