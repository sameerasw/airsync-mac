//
//  Message.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-07-29.
//
import Foundation

enum MessageType: String, Codable {
    case device
    case macInfo
    case notification
    case notificationAction
    case notificationActionResponse
    case notificationUpdate
    case status
    case dismissalResponse
    case mediaControlResponse
    case macMediaControl
    case macMediaControlResponse
    case mirrorRequest
    case mirrorResponse
    case appIcons
    case clipboardUpdate
    case callEvent = "call_event"
    case callControl
    case callControlResponse
    // file transfer
    case fileTransferInit
    case fileChunk
    case fileTransferComplete
    case fileChunkAck
    case transferVerified
    // wake up / quick connect
    case wakeUpRequest
    case wallpaperResponse
    // ADB-less mirroring
    case mirrorStart
    case mirrorStop
    case mirrorFrame
    // remote connect event exchange
    case remoteConnectRequest
    case remoteConnectResponse
    case inputEvent
    case navAction
    case launchApp
    case screenshotRequest
    case screenshotResponse
}

struct Message: Codable {
    let type: MessageType
    let data: CodableValue
}
