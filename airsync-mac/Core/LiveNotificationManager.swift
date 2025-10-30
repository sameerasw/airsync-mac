//
//  LiveNotificationManager.swift
//  airsync-mac
//
//  Manages live notifications and real-time updates
//

import Foundation
import UserNotifications
import AppKit
internal import Combine
import SwiftUI

class LiveNotificationManager: ObservableObject {
    static let shared = LiveNotificationManager()
    
    @Published var activeCall: LiveCallNotification?
    @Published var recentSms: [LiveSmsNotification] = []
    @Published var healthSummary: HealthSummary?
    @Published var smsThreads: [SmsThread] = []
    @Published var smsMessagesByThread: [String: [SmsMessage]] = [:]
    @Published var callLogs: [CallLogEntry] = []
    
    private var callNotificationWindow: NSWindow?
    private var callTimer: Timer?
    
    private init() {
        setupNotificationCategories()
    }
    
    // MARK: - Notification Categories Setup
    
    private func setupNotificationCategories() {
        let center = UNUserNotificationCenter.current()
        
        // Live Activities categories
        setupLiveActivitiesCategories()
        
        // Call notification actions
        let answerAction = UNNotificationAction(
            identifier: "ANSWER_CALL",
            title: "Answer",
            options: [.foreground]
        )
        let declineAction = UNNotificationAction(
            identifier: "DECLINE_CALL",
            title: "Decline",
            options: [.destructive]
        )
        let callCategory = UNNotificationCategory(
            identifier: "CALL_CATEGORY",
            actions: [answerAction, declineAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        // SMS notification actions
        let replyAction = UNTextInputNotificationAction(
            identifier: "REPLY_SMS",
            title: "Reply",
            options: [],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Type a message..."
        )
        let markReadAction = UNNotificationAction(
            identifier: "MARK_READ_SMS",
            title: "Mark as Read",
            options: []
        )
        let smsCategory = UNNotificationCategory(
            identifier: "SMS_CATEGORY",
            actions: [replyAction, markReadAction],
            intentIdentifiers: [],
            options: []
        )
        
        center.setNotificationCategories([callCategory, smsCategory])
    }
    
    private func setupLiveActivitiesCategories() {
        let center = UNUserNotificationCenter.current()
        
        // Live Call Actions
        let answerAction = UNNotificationAction(
            identifier: "LIVE_CALL_ANSWER",
            title: "Answer",
            options: [.foreground]
        )
        let declineAction = UNNotificationAction(
            identifier: "LIVE_CALL_DECLINE",
            title: "Decline",
            options: [.destructive]
        )
        let liveCallCategory = UNNotificationCategory(
            identifier: "LIVE_CALL",
            actions: [answerAction, declineAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        // Live SMS Actions
        let replyAction = UNTextInputNotificationAction(
            identifier: "LIVE_SMS_REPLY",
            title: "Reply",
            options: [.foreground],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Type your message..."
        )
        let markReadAction = UNNotificationAction(
            identifier: "LIVE_SMS_MARK_READ",
            title: "Mark as Read",
            options: []
        )
        let liveSmsCategory = UNNotificationCategory(
            identifier: "LIVE_SMS",
            actions: [replyAction, markReadAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        // Live Health Actions
        let viewHealthAction = UNNotificationAction(
            identifier: "LIVE_HEALTH_VIEW",
            title: "View Details",
            options: [.foreground]
        )
        let liveHealthCategory = UNNotificationCategory(
            identifier: "LIVE_HEALTH",
            actions: [viewHealthAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        center.setNotificationCategories([
            liveCallCategory, liveSmsCategory, liveHealthCategory
        ])
    }
    
    // MARK: - Call Notifications
    
    func handleCallNotification(_ call: LiveCallNotification) {
        DispatchQueue.main.async {
            self.activeCall = call
            
            switch call.state {
            case .ringing:
                if call.isIncoming {
                    self.showIncomingCallNotification(call)
                    self.showCallWindow(call)
                }
            case .active:
                self.updateCallNotification(call)
                self.updateCallWindow(call)
            case .held:
                self.updateCallNotification(call)
            case .disconnected:
                self.dismissCallNotification(call)
                self.hideCallWindow()
                self.activeCall = nil
            }
        }
    }
    
    private func showIncomingCallNotification(_ call: LiveCallNotification) {
        let content = UNMutableNotificationContent()
        content.title = "📞 Incoming Call"
        content.body = call.displayName
        content.sound = .default
        content.categoryIdentifier = "CALL_CATEGORY"
        content.userInfo = [
            "callId": call.id,
            "type": "call",
            "number": call.number
        ]
        
        let request = UNNotificationRequest(
            identifier: "call-\(call.id)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[live-notif] Failed to show call notification: \(error)")
            }
        }
    }
    
    private func updateCallNotification(_ call: LiveCallNotification) {
        let content = UNMutableNotificationContent()
        content.title = call.stateDescription
        content.body = "\(call.displayName) • \(formatDuration(call.duration))"
        content.categoryIdentifier = "CALL_CATEGORY"
        content.userInfo = ["callId": call.id, "type": "call"]
        
        let request = UNNotificationRequest(
            identifier: "call-\(call.id)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    private func dismissCallNotification(_ call: LiveCallNotification) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: ["call-\(call.id)"]
        )
    }
    
    // MARK: - Call Window (Floating Window)
    
    private func showCallWindow(_ call: LiveCallNotification) {
        #if os(macOS)
        guard callNotificationWindow == nil else {
            updateCallWindow(call)
            return
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Incoming Call"
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.titlebarAppearsTransparent = true
        
        #if canImport(SwiftUI)
        let callView = LiveCallView(call: call)
        window.contentView = NSHostingView(rootView: callView)
        #endif
        
        // Position in top-right corner
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - window.frame.width - 20
            let y = screenFrame.maxY - window.frame.height - 20
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        window.makeKeyAndOrderFront(nil)
        callNotificationWindow = window
        
        // Start timer to update duration
        startCallTimer()
        #endif
    }
    
    private func updateCallWindow(_ call: LiveCallNotification) {
        // Window will update automatically via @ObservedObject
    }
    
    private func hideCallWindow() {
        callNotificationWindow?.close()
        callNotificationWindow = nil
        stopCallTimer()
    }
    
    private func startCallTimer() {
        callTimer?.invalidate()
        callTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, self.activeCall != nil else { return }
            self.objectWillChange.send()
        }
    }
    
    private func stopCallTimer() {
        callTimer?.invalidate()
        callTimer = nil
    }
    
    // MARK: - SMS Notifications
    
    func handleSmsReceived(_ sms: LiveSmsNotification) {
        DispatchQueue.main.async {
            self.recentSms.insert(sms, at: 0)
            if self.recentSms.count > 50 {
                self.recentSms.removeLast()
            }
            self.showSmsNotification(sms)
        }
    }
    
    private func showSmsNotification(_ sms: LiveSmsNotification) {
        let content = UNMutableNotificationContent()
        content.title = "💬 \(sms.displayName)"
        content.body = sms.preview
        content.sound = .default
        content.categoryIdentifier = "SMS_CATEGORY"
        content.userInfo = [
            "smsId": sms.id,
            "threadId": sms.threadId,
            "address": sms.address,
            "type": "sms"
        ]
        
        let request = UNNotificationRequest(
            identifier: "sms-\(sms.id)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[live-notif] Failed to show SMS notification: \(error)")
            }
        }
    }
    
    func handleSmsThreads(_ threads: [SmsThread]) {
        DispatchQueue.main.async {
            self.smsThreads = threads
        }
    }
    
    func handleSmsMessages(_ messages: [SmsMessage]) {
        DispatchQueue.main.async {
            // Store messages by thread ID for the detail view
            for message in messages {
                if self.smsMessagesByThread[message.threadId] == nil {
                    self.smsMessagesByThread[message.threadId] = []
                }
                // Avoid duplicates
                if !self.smsMessagesByThread[message.threadId]!.contains(where: { $0.id == message.id }) {
                    self.smsMessagesByThread[message.threadId]!.append(message)
                }
            }
            
            // Sort messages by date for each thread
            for threadId in self.smsMessagesByThread.keys {
                self.smsMessagesByThread[threadId]?.sort { $0.date < $1.date }
            }
            
            print("[LiveNotificationManager] 📱 Stored \(messages.count) SMS messages")
        }
    }
    
    // MARK: - Call Logs
    
    func handleCallLogs(_ logs: [CallLogEntry]) {
        DispatchQueue.main.async {
            self.callLogs = logs
        }
    }
    
    // MARK: - Health Updates
    
    func handleHealthSummary(_ summary: HealthSummary) {
        print("[live-notif] 📊 Received health summary: steps=\(summary.steps ?? 0), calories=\(summary.calories ?? 0), distance=\(summary.distance ?? 0)")
        DispatchQueue.main.async {
            print("[live-notif] 📊 Updating healthSummary on main thread")
            self.healthSummary = summary
            print("[live-notif] 📊 Health summary updated, objectWillChange triggered")
            self.showHealthUpdateIfNeeded(summary)
        }
    }
    
    private func showHealthUpdateIfNeeded(_ summary: HealthSummary) {
        // Show notification for milestones
        if let steps = summary.steps, steps >= 10000 {
            let content = UNMutableNotificationContent()
            content.title = "🎉 Goal Achieved!"
            content.body = "You've reached 10,000 steps today!"
            content.sound = .default
            
            let request = UNNotificationRequest(
                identifier: "health-milestone-steps",
                content: content,
                trigger: nil
            )
            
            UNUserNotificationCenter.current().add(request)
        }
    }
    
    // MARK: - Actions
    
    func answerCall() {
        guard let call = activeCall else { return }
        WebSocketServer.shared.sendCallAction("answer")
        print("[live-notif] Answer call action sent for \(call.id)")
    }
    
    func declineCall() {
        guard let call = activeCall else { return }
        WebSocketServer.shared.sendCallAction("reject")
        hideCallWindow()
        activeCall = nil
        print("[live-notif] Decline call action sent for \(call.id)")
    }
    
    func replySms(to address: String, message: String) {
        WebSocketServer.shared.sendSms(to: address, message: message)
        print("[live-notif] SMS reply sent to \(address)")
    }
    
    func markSmsAsRead(messageId: String) {
        WebSocketServer.shared.markSmsAsRead(messageId: messageId)
        print("[live-notif] Marked SMS \(messageId) as read")
    }
    
    // MARK: - Helpers
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
