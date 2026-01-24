//
//  LiveNotification.swift
//  airsync-mac
//
//  Live notification models for real-time updates
//

import Foundation

// MARK: - Live Notification Types

enum LiveNotificationType: String, Codable {
    case call
    case sms
    case health
    case custom
}

// Use CallState from CallEvent.swift - no duplicate definition needed

// MARK: - Live Call Notification

struct LiveCallNotification: Codable, Identifiable {
    let id: String
    let number: String
    let contactName: String?
    let state: CallState
    let startTime: Date
    let isIncoming: Bool
    var duration: TimeInterval {
        Date().timeIntervalSince(startTime)
    }
    
    var displayName: String {
        contactName ?? number
    }
    
    var stateDescription: String {
        switch state {
        case .ringing:
            return isIncoming ? "Incoming Call" : "Calling..."
        case .offhook, .accepted:
            return "In Call"
        case .idle:
            return "On Hold"
        case .ended, .rejected, .missed:
            return "Call Ended"
        }
    }
}

// MARK: - Live SMS Notification

struct LiveSmsNotification: Codable, Identifiable {
    let id: String
    let threadId: String
    let address: String
    let contactName: String?
    let body: String
    let date: Date
    let read: Bool
    
    var displayName: String {
        contactName ?? address
    }
    
    var preview: String {
        if body.count > 100 {
            return String(body.prefix(100)) + "..."
        }
        return body
    }
}

// MARK: - Live Health Update

struct LiveHealthUpdate: Codable {
    let timestamp: Date
    let dataType: String
    let value: Double
    let unit: String
    let source: String?
    
    var displayValue: String {
        switch dataType {
        case "STEPS":
            return "\(Int(value)) steps"
        case "HEART_RATE":
            return "\(Int(value)) bpm"
        case "DISTANCE":
            return String(format: "%.1f km", value)
        case "CALORIES":
            return "\(Int(value)) kcal"
        default:
            return "\(value) \(unit)"
        }
    }
}

// MARK: - Health Summary

struct HealthSummary: Codable {
    let date: Date
    let steps: Int?
    let distance: Double?
    let calories: Int?
    let activeMinutes: Int?
    let heartRateAvg: Int?
    let heartRateMin: Int?
    let heartRateMax: Int?
    let sleepDuration: Int?
    
    // Additional health metrics from Android
    let floorsClimbed: Int?
    let weight: Double?
    let bloodPressureSystolic: Int?
    let bloodPressureDiastolic: Int?
    let oxygenSaturation: Double?
    let restingHeartRate: Int?
    let vo2Max: Double?
    let bodyTemperature: Double?
    let bloodGlucose: Double?
    let hydration: Double?
    
    var stepsProgress: Double {
        guard let steps = steps else { return 0 }
        return min(Double(steps) / 10000.0, 1.0)
    }
    
    var caloriesProgress: Double {
        guard let calories = calories else { return 0 }
        return min(Double(calories) / 2000.0, 1.0)
    }
    
    var hasExtendedMetrics: Bool {
        floorsClimbed != nil || weight != nil || bloodPressureSystolic != nil || 
        bloodPressureDiastolic != nil || oxygenSaturation != nil || restingHeartRate != nil ||
        vo2Max != nil || bodyTemperature != nil || bloodGlucose != nil || hydration != nil
    }
}

// MARK: - SMS Thread

struct SmsThread: Codable, Identifiable, Hashable {
    let threadId: String
    let address: String
    let contactName: String?
    let messageCount: Int
    let snippet: String
    let date: Date
    let unreadCount: Int
    
    var id: String { threadId }
    
    var displayName: String {
        contactName ?? address
    }
    
    var hasUnread: Bool {
        unreadCount > 0
    }
    
    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(threadId)
    }
    
    static func == (lhs: SmsThread, rhs: SmsThread) -> Bool {
        lhs.threadId == rhs.threadId
    }
}

// MARK: - SMS Message

struct SmsMessage: Codable, Identifiable {
    let id: String
    let threadId: String
    let address: String
    let body: String
    let date: Date
    let type: Int // 1 = received, 2 = sent
    let read: Bool
    let contactName: String?
    
    var isReceived: Bool {
        type == 1
    }
    
    var isSent: Bool {
        type == 2
    }
    
    var displayName: String {
        contactName ?? address
    }
}

// MARK: - Call Log Entry

struct CallLogEntry: Codable, Identifiable {
    let id: String
    let number: String
    let contactName: String?
    let type: String // incoming, outgoing, missed, voicemail, rejected, blocked
    let date: Date
    let duration: Int // seconds
    let isRead: Bool
    
    var displayName: String {
        contactName ?? number
    }
    
    var typeIcon: String {
        switch type {
        case "incoming":
            return "phone.arrow.down.left"
        case "outgoing":
            return "phone.arrow.up.right"
        case "missed":
            return "phone.down"
        case "voicemail":
            return "voicemail"
        case "rejected":
            return "phone.down.fill"
        case "blocked":
            return "phone.badge.xmark"
        default:
            return "phone"
        }
    }
    
    var durationFormatted: String {
        let minutes = duration / 60
        let seconds = duration % 60
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        }
        return "\(seconds)s"
    }
}
