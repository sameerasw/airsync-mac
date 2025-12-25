//
//  LiveActivitiesManager.swift
//  airsync-mac
//
//  Live Activities manager for macOS Dynamic Island and Notification Center
//

import Foundation
import UserNotifications
import SwiftUI
internal import Combine

@available(macOS 13.0, *)
class LiveActivitiesManager: ObservableObject {
    static let shared = LiveActivitiesManager()
    
    @Published var activeCallActivity: LiveCallActivity?
    @Published var activeSmsActivity: LiveSmsActivity?
    @Published var activeHealthActivity: LiveHealthActivity?
    
    private init() {
        setupLiveActivities()
    }
    
    private func setupLiveActivities() {
        // Request enhanced notification permissions for Live Activities
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge, .provisional, .criticalAlert]
        ) { granted, error in
            if let error = error {
                print("[live-activities] Permission error: \(error)")
            } else {
                print("[live-activities] Enhanced permissions granted: \(granted)")
            }
        }
    }
    
    // MARK: - Call Activities
    
    func startCallActivity(_ call: LiveCallNotification) {
        print("[live-activities] 📞 Starting call activity for \(call.displayName)")
        
        let activity = LiveCallActivity(
            id: call.id,
            contactName: call.displayName,
            phoneNumber: call.number,
            state: call.state,
            startTime: call.startTime,
            isIncoming: call.isIncoming
        )
        
        DispatchQueue.main.async {
            self.activeCallActivity = activity
        }
        
        // Create persistent notification with live updates
        createCallLiveNotification(activity)
    }
    
    func updateCallActivity(_ call: LiveCallNotification) {
        guard var activity = activeCallActivity, activity.id == call.id else { return }
        
        print("[live-activities] 📞 Updating call activity: \(call.state)")
        
        activity.state = call.state
        // Duration is computed property, no need to set it
        
        DispatchQueue.main.async {
            self.activeCallActivity = activity
        }
        
        // Update the live notification
        updateCallLiveNotification(activity)
    }
    
    func endCallActivity(_ callId: String) {
        guard let activity = activeCallActivity, activity.id == callId else { return }
        
        print("[live-activities] 📞 Ending call activity")
        
        DispatchQueue.main.async {
            self.activeCallActivity = nil
        }
        
        // Remove the live notification
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["live-call-\(callId)"])
    }
    
    // MARK: - SMS Activities
    
    func startSmsActivity(_ sms: LiveSmsNotification) {
        print("[live-activities] 💬 Starting SMS activity from \(sms.displayName)")
        
        let activity = LiveSmsActivity(
            id: sms.id,
            threadId: sms.threadId,
            contactName: sms.displayName,
            phoneNumber: sms.address,
            lastMessage: sms.body,
            messageCount: 1,
            timestamp: sms.date
        )
        
        DispatchQueue.main.async {
            self.activeSmsActivity = activity
        }
        
        createSmsLiveNotification(activity)
    }
    
    func updateSmsActivity(_ sms: LiveSmsNotification) {
        guard var activity = activeSmsActivity, activity.threadId == sms.threadId else {
            // Start new activity if none exists for this thread
            startSmsActivity(sms)
            return
        }
        
        print("[live-activities] 💬 Updating SMS activity: new message")
        
        activity.lastMessage = sms.body
        activity.messageCount += 1
        activity.timestamp = sms.date
        
        DispatchQueue.main.async {
            self.activeSmsActivity = activity
        }
        
        updateSmsLiveNotification(activity)
    }
    
    func endSmsActivity(_ threadId: String) {
        guard let activity = activeSmsActivity, activity.threadId == threadId else { return }
        
        print("[live-activities] 💬 Ending SMS activity")
        
        DispatchQueue.main.async {
            self.activeSmsActivity = nil
        }
        
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["live-sms-\(threadId)"])
    }
    
    // MARK: - Health Activities
    
    func startHealthActivity(_ summary: HealthSummary) {
        print("[live-activities] 📊 Starting health activity")
        
        let activity = LiveHealthActivity(
            id: UUID().uuidString,
            date: summary.date,
            steps: summary.steps ?? 0,
            calories: summary.calories ?? 0,
            heartRate: summary.heartRateAvg,
            lastUpdate: Date()
        )
        
        DispatchQueue.main.async {
            self.activeHealthActivity = activity
        }
        
        createHealthLiveNotification(activity)
    }
    
    func updateHealthActivity(_ summary: HealthSummary) {
        guard var activity = activeHealthActivity else {
            startHealthActivity(summary)
            return
        }
        
        print("[live-activities] 📊 Updating health activity")
        
        activity.steps = summary.steps ?? activity.steps
        activity.calories = summary.calories ?? activity.calories
        activity.heartRate = summary.heartRateAvg ?? activity.heartRate
        activity.lastUpdate = Date()
        
        DispatchQueue.main.async {
            self.activeHealthActivity = activity
        }
        
        updateHealthLiveNotification(activity)
    }
    
    // MARK: - Live Notification Creation
    
    private func createCallLiveNotification(_ activity: LiveCallActivity) {
        let content = UNMutableNotificationContent()
        content.title = "📞 \(activity.contactName)"
        content.body = activity.state.rawValue.capitalized
        content.categoryIdentifier = "LIVE_CALL"
        content.threadIdentifier = "live-call-\(activity.id)"
        content.interruptionLevel = .critical
        
        // Add custom data for live updates
        content.userInfo = [
            "type": "live_call",
            "callId": activity.id,
            "contactName": activity.contactName,
            "phoneNumber": activity.phoneNumber,
            "state": activity.state.rawValue,
            "isIncoming": activity.isIncoming,
            "startTime": activity.startTime.timeIntervalSince1970
        ]
        
        let request = UNNotificationRequest(
            identifier: "live-call-\(activity.id)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[live-activities] Failed to create call live notification: \(error)")
            }
        }
    }
    
    private func updateCallLiveNotification(_ activity: LiveCallActivity) {
        let content = UNMutableNotificationContent()
        content.title = "📞 \(activity.contactName)"
        
        let durationText = formatDuration(activity.duration)
        content.body = "\(activity.state.rawValue.capitalized) • \(durationText)"
        content.categoryIdentifier = "LIVE_CALL"
        content.threadIdentifier = "live-call-\(activity.id)"
        content.interruptionLevel = .critical
        
        content.userInfo = [
            "type": "live_call",
            "callId": activity.id,
            "contactName": activity.contactName,
            "phoneNumber": activity.phoneNumber,
            "state": activity.state.rawValue,
            "duration": activity.duration,
            "isIncoming": activity.isIncoming
        ]
        
        let request = UNNotificationRequest(
            identifier: "live-call-\(activity.id)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    private func createSmsLiveNotification(_ activity: LiveSmsActivity) {
        let content = UNMutableNotificationContent()
        content.title = "💬 \(activity.contactName)"
        content.body = activity.lastMessage
        content.categoryIdentifier = "LIVE_SMS"
        content.threadIdentifier = "live-sms-\(activity.threadId)"
        content.interruptionLevel = .active
        
        content.userInfo = [
            "type": "live_sms",
            "threadId": activity.threadId,
            "contactName": activity.contactName,
            "phoneNumber": activity.phoneNumber,
            "messageCount": activity.messageCount,
            "lastMessage": activity.lastMessage
        ]
        
        let request = UNNotificationRequest(
            identifier: "live-sms-\(activity.threadId)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    private func updateSmsLiveNotification(_ activity: LiveSmsActivity) {
        let content = UNMutableNotificationContent()
        content.title = "💬 \(activity.contactName)"
        
        let messageText = activity.messageCount > 1 
            ? "\(activity.messageCount) messages • \(activity.lastMessage)"
            : activity.lastMessage
        content.body = messageText
        content.categoryIdentifier = "LIVE_SMS"
        content.threadIdentifier = "live-sms-\(activity.threadId)"
        content.interruptionLevel = .active
        
        content.userInfo = [
            "type": "live_sms",
            "threadId": activity.threadId,
            "contactName": activity.contactName,
            "phoneNumber": activity.phoneNumber,
            "messageCount": activity.messageCount,
            "lastMessage": activity.lastMessage
        ]
        
        let request = UNNotificationRequest(
            identifier: "live-sms-\(activity.threadId)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    private func createHealthLiveNotification(_ activity: LiveHealthActivity) {
        let content = UNMutableNotificationContent()
        content.title = "📊 Health Update"
        
        var bodyParts: [String] = []
        if activity.steps > 0 { bodyParts.append("\(activity.steps) steps") }
        if activity.calories > 0 { bodyParts.append("\(activity.calories) cal") }
        if let hr = activity.heartRate { bodyParts.append("\(hr) bpm") }
        
        content.body = bodyParts.joined(separator: " • ")
        content.categoryIdentifier = "LIVE_HEALTH"
        content.threadIdentifier = "live-health"
        content.interruptionLevel = .passive
        
        content.userInfo = [
            "type": "live_health",
            "steps": activity.steps,
            "calories": activity.calories,
            "heartRate": activity.heartRate ?? 0,
            "lastUpdate": activity.lastUpdate.timeIntervalSince1970
        ]
        
        let request = UNNotificationRequest(
            identifier: "live-health",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    private func updateHealthLiveNotification(_ activity: LiveHealthActivity) {
        createHealthLiveNotification(activity) // Same as create for health updates
    }
    
    // MARK: - Helper Methods
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Live Activity Models

struct LiveCallActivity {
    let id: String
    let contactName: String
    let phoneNumber: String
    var state: CallState
    let startTime: Date
    let isIncoming: Bool
    var duration: TimeInterval {
        Date().timeIntervalSince(startTime)
    }
}

struct LiveSmsActivity {
    let id: String
    let threadId: String
    let contactName: String
    let phoneNumber: String
    var lastMessage: String
    var messageCount: Int
    var timestamp: Date
}

struct LiveHealthActivity {
    let id: String
    let date: Date
    var steps: Int
    var calories: Int
    var heartRate: Int?
    var lastUpdate: Date
}