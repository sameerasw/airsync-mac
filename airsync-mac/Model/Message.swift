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
    // file transfer
    case fileTransferInit
    case fileChunk
    case fileTransferComplete
    case fileChunkAck
    case transferVerified
    // call state / control
    case callState
    case callControlResponse
    // wake up / quick connect
    case wakeUpRequest
}

struct Message: Codable {
    let type: MessageType
    let data: CodableValue
}
