//
//  Device.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-07-28.
//

import Foundation

struct Device: Codable, Hashable, Identifiable {
    let id = UUID()
    
    let name: String
    let ipAddress: String
    let port: Int
    let version: String
    let adbPorts: [String]

    private enum CodingKeys: String, CodingKey {
        case name, ipAddress, port, version, adbPorts
    }
}

struct MockData{
    static let sampleDevice = Device(
        name: "Test Device",
        ipAddress: "192.168.1.100",
        port: 8080,
        version: "2.0.0",
        adbPorts: ["5555"]
    )

    static let sampleNotificaiton = Notification(
        title: "Sample title",
        body: "Sample text body",
        app: "AirSync",
        nid: "23987423984789234",
        package: "sameerasw.airsync",
        actions: []
    )

    static let sampleMusic: DeviceStatus.Music = .init(
        isPlaying: true,
        title: "Sample Music Title",
        artist: "Sample Artist",
        volume: 50,
        isMuted: false,
        albumArt: "",
        likeStatus: "none"
    )

    static let sampleDevices = [
        Device(name: "Test Device 1", ipAddress: "192.168.1.101", port: 8080, version: "2.0.0", adbPorts: ["5555"]),
        Device(name: "Test Device 2", ipAddress: "192.168.1.102", port: 8080, version: "2.0.0", adbPorts: ["5555"]),
        Device(name: "Test Device 3", ipAddress: "192.168.1.103", port: 8080, version: "2.0.0", adbPorts: ["5555"])
    ]
}
