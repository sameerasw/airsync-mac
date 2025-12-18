//
//  CallEvent.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-12-13.
//

import Foundation

enum CallState: String, Codable {
    case ringing
    case accepted
    case rejected
    case ended
    case missed
    case offhook
    case idle
}

enum CallDirection: String, Codable {
    case incoming
    case outgoing
}

struct CallEvent: Codable, Identifiable, Equatable {
    let eventId: String
    let contactName: String
    let number: String
    let normalizedNumber: String
    let direction: CallDirection
    let state: CallState
    let timestamp: Int64
    let deviceId: String
    let contactPhoto: String? // Base64 encoded image
    
    var id: String { eventId }

    private enum CodingKeys: String, CodingKey {
        case eventId
        case contactName
        case number
        case normalizedNumber
        case direction
        case state
        case timestamp
        case deviceId
        case contactPhoto
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(eventId)
    }
}
