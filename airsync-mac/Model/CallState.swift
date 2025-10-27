//
//  CallState.swift
//  airsync-mac
//
//  Generated for Android -> Mac call notifications
//

import Foundation

enum CallType: String, Codable {
    case incoming = "INCOMING"
    case outgoing = "OUTGOING"
}

enum CallStatus: String, Codable {
    case ringing = "RINGING"
    case active = "ACTIVE"
    case held = "HELD"
    case disconnected = "DISCONNECTED"
}

struct CallState: Codable, Identifiable {
    var id: String? = nil

    var phoneNumber: String?
    var callerName: String?
    var callType: CallType?
    var callStatus: CallStatus
    var durationSeconds: Int?

    var idForIdentifiable: UUID { UUID() }

    var identifier: String { id ?? (phoneNumber ?? UUID().uuidString) }
}
