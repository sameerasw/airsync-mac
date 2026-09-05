//
//  Constants.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-07-30.
//

import Foundation

// Constants.swift
enum Defaults {
    static let serverPort: UInt16 = 6996
}

enum CallNotificationMode: String, CaseIterable, Identifiable {
    case popup = "popup"
    case notification = "notification"
    case none = "none"
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .popup:
            return "Pop-up"
        case .notification:
            return "Notification"
        case .none:
            return "Nothing"
        }
    }
}

enum CrashReportingMode: String, CaseIterable, Identifiable {
    case manual = "manual"
    case notify = "notify"
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .manual:
            return "Manual"
        case .notify:
            return "Notify"
        }
    }
}


