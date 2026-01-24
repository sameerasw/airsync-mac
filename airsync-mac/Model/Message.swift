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
    case fileTransferCancel
    // wake up / quick connect
    case wakeUpRequest
    // remote control (Mac)
    case remoteControl
    case volumeControl // outgoing from Mac (legacy/other direction)
    case macVolume     // outgoing from Mac
    case toggleAppNotif // outgoing from Mac
    // file browser
    case browseLs
    case browseData
}

struct Message: Codable {
    let type: MessageType
    let data: CodableValue
}
