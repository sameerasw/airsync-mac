//
//  AirBridgeModels.swift
//  airsync-mac
//
//  Created by tornado-bunk and an AI Assistant.
//

import Foundation

// MARK: - Actions

/// Actions supported by the AirBridge relay protocol.
enum AirBridgeAction: String, Codable {
    case register       = "register"
    case query          = "query"
    case macInfo        = "mac_info"
    case requestRelay   = "request_relay"
    case relayStarted   = "relay_started"
    case error          = "error"
}

// MARK: - Outgoing Messages

/// Registration message sent by the Mac to the relay server upon connection.
struct AirBridgeRegisterMessage: Codable {
    let action: AirBridgeAction
    let role: String
    let pairingId: String
    let secret: String
    let localIp: String
    let port: Int
}

// MARK: - Incoming Messages

/// Base message for decoding the `action` field from the relay server.
struct AirBridgeBaseMessage: Codable {
    let action: AirBridgeAction
    let pairingId: String?
}

/// Error message received from the relay server.
struct AirBridgeErrorMessage: Codable {
    let action: AirBridgeAction
    let message: String
}

// MARK: - Keychain Config Blob (consolidated storage)

/// All AirBridge credentials stored as a single Keychain entry to minimise password prompts
struct AirBridgeConfigBlob: Codable {
    let url: String
    let pid: String
    let sec: String
}

// MARK: - Connection State

/// Represents the current state of the AirBridge relay connection.
enum AirBridgeConnectionState: Equatable {
    case disconnected
    case connecting
    case registering
    case waitingForPeer
    case relayActive
    case failed(error: String)

    var displayName: String {
        switch self {
        case .disconnected:     return "Disconnected"
        case .connecting:       return "Connecting…"
        case .registering:      return "Registering…"
        case .waitingForPeer:   return "Waiting for Android…"
        case .relayActive:      return "Relay Active"
        case .failed(let err):  return "Error: \(err)"
        }
    }

    var isConnected: Bool {
        switch self {
        case .waitingForPeer, .relayActive: return true
        default: return false
        }
    }
}
