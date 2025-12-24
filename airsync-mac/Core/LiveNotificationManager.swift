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
    
    // Health data cache - keyed by date string (yyyy-MM-dd)
    private var healthCache: [String: HealthSummary] = [:]
    private var healthCacheTimestamps: [String: Date] = [:]
    private let healthCacheExpiry: TimeInterval = 300 // 5 minutes for today, longer for past dates
    
    // Pending health requests to prevent duplicate requests
    private var pendingHealthRequests: Set<String> = []
    
    // SMS and Call Log cache timestamps
    private var smsThreadsCacheTimestamp: Date?
    private var callLogsCacheTimestamp: Date?
    private let smsCacheExpiry: TimeInterval = 60 // 1 minute
    private let callLogCacheExpiry: TimeInterval = 60 // 1 minute
    
    // Pending requests to prevent duplicates
    private var isSmsThreadsRequestPending = false
    private var isCallLogsRequestPending = false
    
    private var callNotificationWindow: NSWindow?
    private var callTimer: Timer?
    
    private init() {
        setupNotificationCategories()
        loadHealthCacheFromDisk()
        loadSmsCacheFromDisk()
        loadCallLogsCacheFromDisk()
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
            case .accepted, .offhook:
                self.updateCallNotification(call)
                self.updateCallWindow(call)
            case .idle:
                self.updateCallNotification(call)
            case .ended, .rejected, .missed:
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
            self.smsThreadsCacheTimestamp = Date()
            self.isSmsThreadsRequestPending = false
            self.saveSmsCacheToDisk()
            print("[live-notif] 📱 Cached \(threads.count) SMS threads")
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
            
            self.saveSmsCacheToDisk()
            print("[LiveNotificationManager] 📱 Stored \(messages.count) SMS messages")
        }
    }
    
    /// Get SMS threads with caching
    func getSmsThreads(forceRefresh: Bool = false) -> [SmsThread] {
        // Check if cache is valid
        if !forceRefresh, let timestamp = smsThreadsCacheTimestamp {
            let cacheAge = Date().timeIntervalSince(timestamp)
            if cacheAge < smsCacheExpiry && !smsThreads.isEmpty {
                print("[live-notif] 📱 Using cached SMS threads (age: \(Int(cacheAge))s)")
                return smsThreads
            }
        }
        
        // Request from Android if not cached or expired
        requestSmsThreadsFromAndroid()
        return smsThreads
    }
    
    private func requestSmsThreadsFromAndroid() {
        guard !isSmsThreadsRequestPending else {
            print("[live-notif] 📱 SMS threads request already pending")
            return
        }
        
        isSmsThreadsRequestPending = true
        print("[live-notif] 📱 Requesting SMS threads from Android")
        WebSocketServer.shared.requestSmsThreads()
        
        // Clear pending flag after timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.isSmsThreadsRequestPending = false
        }
    }
    
    // MARK: - Call Logs
    
    func handleCallLogs(_ logs: [CallLogEntry]) {
        DispatchQueue.main.async {
            self.callLogs = logs
            self.callLogsCacheTimestamp = Date()
            self.isCallLogsRequestPending = false
            self.saveCallLogsCacheToDisk()
            print("[live-notif] 📞 Cached \(logs.count) call logs")
        }
    }
    
    /// Get call logs with caching
    func getCallLogs(forceRefresh: Bool = false) -> [CallLogEntry] {
        // Check if cache is valid
        if !forceRefresh, let timestamp = callLogsCacheTimestamp {
            let cacheAge = Date().timeIntervalSince(timestamp)
            if cacheAge < callLogCacheExpiry && !callLogs.isEmpty {
                print("[live-notif] 📞 Using cached call logs (age: \(Int(cacheAge))s)")
                return callLogs
            }
        }
        
        // Request from Android if not cached or expired
        requestCallLogsFromAndroid()
        return callLogs
    }
    
    private func requestCallLogsFromAndroid() {
        guard !isCallLogsRequestPending else {
            print("[live-notif] 📞 Call logs request already pending")
            return
        }
        
        isCallLogsRequestPending = true
        print("[live-notif] 📞 Requesting call logs from Android")
        WebSocketServer.shared.requestCallLogs()
        
        // Clear pending flag after timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.isCallLogsRequestPending = false
        }
    }
    
    // MARK: - Health Updates
    
    func handleHealthSummary(_ summary: HealthSummary) {
        print("[live-notif] 📊 Received health summary: steps=\(summary.steps ?? 0), calories=\(summary.calories ?? 0), distance=\(summary.distance ?? 0)")
        
        // Cache the health data
        let dateKey = dateKeyFromTimestamp(summary.date)
        healthCache[dateKey] = summary
        healthCacheTimestamps[dateKey] = Date()
        pendingHealthRequests.remove(dateKey)
        
        // Save to disk for persistence
        saveHealthCacheToDisk()
        
        DispatchQueue.main.async {
            print("[live-notif] 📊 Updating healthSummary on main thread")
            self.healthSummary = summary
            print("[live-notif] 📊 Health summary updated, objectWillChange triggered")
            self.showHealthUpdateIfNeeded(summary)
        }
    }
    
    /// Get cached health data for a date, or request from Android if not cached
    func getHealthSummary(for date: Date, forceRefresh: Bool = false) -> HealthSummary? {
        let dateKey = dateKeyFromDate(date)
        
        // Check if we have cached data
        if let cached = healthCache[dateKey], !forceRefresh {
            let isToday = Calendar.current.isDateInToday(date)
            let cacheAge = Date().timeIntervalSince(healthCacheTimestamps[dateKey] ?? .distantPast)
            
            // For today, cache expires after 5 minutes; for past dates, cache is valid for 1 hour
            let maxAge: TimeInterval = isToday ? healthCacheExpiry : 3600
            
            if cacheAge < maxAge {
                print("[live-notif] 📊 Using cached health data for \(dateKey) (age: \(Int(cacheAge))s)")
                return cached
            }
        }
        
        // Request from Android if not cached or expired
        requestHealthFromAndroid(for: date)
        
        // Return cached data while waiting for fresh data (if available)
        return healthCache[dateKey]
    }
    
    /// Request health data from Android (with deduplication)
    private func requestHealthFromAndroid(for date: Date) {
        let dateKey = dateKeyFromDate(date)
        
        // Prevent duplicate requests
        guard !pendingHealthRequests.contains(dateKey) else {
            print("[live-notif] 📊 Health request already pending for \(dateKey)")
            return
        }
        
        pendingHealthRequests.insert(dateKey)
        print("[live-notif] 📊 Requesting health data from Android for \(dateKey)")
        
        WebSocketServer.shared.requestHealthSummary(for: date)
        
        // Clear pending flag after timeout (10 seconds)
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.pendingHealthRequests.remove(dateKey)
        }
    }
    
    /// Check if health data is being requested
    func isHealthRequestPending(for date: Date) -> Bool {
        let dateKey = dateKeyFromDate(date)
        return pendingHealthRequests.contains(dateKey)
    }
    
    // MARK: - Health Cache Persistence
    
    private func dateKeyFromDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    private func dateKeyFromTimestamp(_ timestamp: Date) -> String {
        return dateKeyFromDate(timestamp)
    }
    
    private var healthCacheURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("AirSync", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("health_cache.json")
    }
    
    private func saveHealthCacheToDisk() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            
            do {
                var cacheData: [[String: Any]] = []
                
                for (dateKey, summary) in self.healthCache {
                    var entry: [String: Any] = [
                        "dateKey": dateKey,
                        "date": summary.date.timeIntervalSince1970,
                        "cachedAt": self.healthCacheTimestamps[dateKey]?.timeIntervalSince1970 ?? 0
                    ]
                    
                    if let steps = summary.steps { entry["steps"] = steps }
                    if let calories = summary.calories { entry["calories"] = calories }
                    if let distance = summary.distance { entry["distance"] = distance }
                    if let heartRateAvg = summary.heartRateAvg { entry["heartRateAvg"] = heartRateAvg }
                    if let heartRateMin = summary.heartRateMin { entry["heartRateMin"] = heartRateMin }
                    if let heartRateMax = summary.heartRateMax { entry["heartRateMax"] = heartRateMax }
                    if let sleepDuration = summary.sleepDuration { entry["sleepDuration"] = sleepDuration }
                    if let activeMinutes = summary.activeMinutes { entry["activeMinutes"] = activeMinutes }
                    if let floorsClimbed = summary.floorsClimbed { entry["floorsClimbed"] = floorsClimbed }
                    if let weight = summary.weight { entry["weight"] = weight }
                    if let bloodPressureSystolic = summary.bloodPressureSystolic { entry["bloodPressureSystolic"] = bloodPressureSystolic }
                    if let bloodPressureDiastolic = summary.bloodPressureDiastolic { entry["bloodPressureDiastolic"] = bloodPressureDiastolic }
                    if let oxygenSaturation = summary.oxygenSaturation { entry["oxygenSaturation"] = oxygenSaturation }
                    if let restingHeartRate = summary.restingHeartRate { entry["restingHeartRate"] = restingHeartRate }
                    if let vo2Max = summary.vo2Max { entry["vo2Max"] = vo2Max }
                    if let bodyTemperature = summary.bodyTemperature { entry["bodyTemperature"] = bodyTemperature }
                    if let bloodGlucose = summary.bloodGlucose { entry["bloodGlucose"] = bloodGlucose }
                    if let hydration = summary.hydration { entry["hydration"] = hydration }
                    
                    cacheData.append(entry)
                }
                
                let jsonData = try JSONSerialization.data(withJSONObject: cacheData, options: [.prettyPrinted])
                try jsonData.write(to: self.healthCacheURL)
                print("[live-notif] 📊 Saved \(cacheData.count) health entries to disk")
            } catch {
                print("[live-notif] ❌ Failed to save health cache: \(error)")
            }
        }
    }
    
    private func loadHealthCacheFromDisk() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            
            do {
                guard FileManager.default.fileExists(atPath: self.healthCacheURL.path) else {
                    print("[live-notif] 📊 No health cache file found")
                    return
                }
                
                let jsonData = try Data(contentsOf: self.healthCacheURL)
                guard let cacheData = try JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
                    return
                }
                
                var loadedCache: [String: HealthSummary] = [:]
                var loadedTimestamps: [String: Date] = [:]
                
                for entry in cacheData {
                    guard let dateKey = entry["dateKey"] as? String,
                          let dateTimestamp = entry["date"] as? TimeInterval,
                          let cachedAt = entry["cachedAt"] as? TimeInterval else {
                        continue
                    }
                    
                    let summary = HealthSummary(
                        date: Date(timeIntervalSince1970: dateTimestamp),
                        steps: entry["steps"] as? Int,
                        distance: entry["distance"] as? Double,
                        calories: entry["calories"] as? Int,
                        activeMinutes: entry["activeMinutes"] as? Int,
                        heartRateAvg: entry["heartRateAvg"] as? Int,
                        heartRateMin: entry["heartRateMin"] as? Int,
                        heartRateMax: entry["heartRateMax"] as? Int,
                        sleepDuration: entry["sleepDuration"] as? Int,
                        floorsClimbed: entry["floorsClimbed"] as? Int,
                        weight: entry["weight"] as? Double,
                        bloodPressureSystolic: entry["bloodPressureSystolic"] as? Int,
                        bloodPressureDiastolic: entry["bloodPressureDiastolic"] as? Int,
                        oxygenSaturation: entry["oxygenSaturation"] as? Double,
                        restingHeartRate: entry["restingHeartRate"] as? Int,
                        vo2Max: entry["vo2Max"] as? Double,
                        bodyTemperature: entry["bodyTemperature"] as? Double,
                        bloodGlucose: entry["bloodGlucose"] as? Double,
                        hydration: entry["hydration"] as? Double
                    )
                    
                    loadedCache[dateKey] = summary
                    loadedTimestamps[dateKey] = Date(timeIntervalSince1970: cachedAt)
                }
                
                DispatchQueue.main.async {
                    self.healthCache = loadedCache
                    self.healthCacheTimestamps = loadedTimestamps
                    print("[live-notif] 📊 Loaded \(loadedCache.count) health entries from disk")
                }
            } catch {
                print("[live-notif] ❌ Failed to load health cache: \(error)")
            }
        }
    }
    
    /// Clear health cache for a specific date
    func clearHealthCache(for date: Date) {
        let dateKey = dateKeyFromDate(date)
        healthCache.removeValue(forKey: dateKey)
        healthCacheTimestamps.removeValue(forKey: dateKey)
        saveHealthCacheToDisk()
    }
    
    /// Clear all health cache
    func clearAllHealthCache() {
        healthCache.removeAll()
        healthCacheTimestamps.removeAll()
        try? FileManager.default.removeItem(at: healthCacheURL)
    }
    
    // MARK: - SMS Cache Persistence
    
    private var smsCacheURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("AirSync", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("sms_cache.json")
    }
    
    private func saveSmsCacheToDisk() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            
            do {
                var cacheData: [String: Any] = [:]
                
                // Save threads
                var threadsData: [[String: Any]] = []
                for thread in self.smsThreads {
                    var threadEntry: [String: Any] = [
                        "threadId": thread.threadId,
                        "address": thread.address,
                        "snippet": thread.snippet,
                        "date": thread.date.timeIntervalSince1970,
                        "messageCount": thread.messageCount,
                        "unreadCount": thread.unreadCount
                    ]
                    if let contactName = thread.contactName {
                        threadEntry["contactName"] = contactName
                    }
                    threadsData.append(threadEntry)
                }
                cacheData["threads"] = threadsData
                
                // Save messages by thread
                var messagesData: [String: [[String: Any]]] = [:]
                for (threadId, messages) in self.smsMessagesByThread {
                    var threadMessages: [[String: Any]] = []
                    for message in messages {
                        var messageEntry: [String: Any] = [
                            "id": message.id,
                            "threadId": message.threadId,
                            "address": message.address,
                            "body": message.body,
                            "date": message.date.timeIntervalSince1970,
                            "type": message.type,
                            "read": message.read
                        ]
                        if let contactName = message.contactName {
                            messageEntry["contactName"] = contactName
                        }
                        threadMessages.append(messageEntry)
                    }
                    messagesData[threadId] = threadMessages
                }
                cacheData["messagesByThread"] = messagesData
                
                // Save timestamp
                if let timestamp = self.smsThreadsCacheTimestamp {
                    cacheData["cachedAt"] = timestamp.timeIntervalSince1970
                }
                
                let jsonData = try JSONSerialization.data(withJSONObject: cacheData, options: [.prettyPrinted])
                try jsonData.write(to: self.smsCacheURL)
                print("[live-notif] 📱 Saved \(threadsData.count) SMS threads to disk")
            } catch {
                print("[live-notif] ❌ Failed to save SMS cache: \(error)")
            }
        }
    }
    
    private func loadSmsCacheFromDisk() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            
            do {
                guard FileManager.default.fileExists(atPath: self.smsCacheURL.path) else {
                    print("[live-notif] 📱 No SMS cache file found")
                    return
                }
                
                let jsonData = try Data(contentsOf: self.smsCacheURL)
                guard let cacheData = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                    return
                }
                
                // Load threads
                var loadedThreads: [SmsThread] = []
                if let threadsData = cacheData["threads"] as? [[String: Any]] {
                    for entry in threadsData {
                        guard let threadId = entry["threadId"] as? String,
                              let address = entry["address"] as? String,
                              let snippet = entry["snippet"] as? String,
                              let dateTimestamp = entry["date"] as? TimeInterval,
                              let messageCount = entry["messageCount"] as? Int,
                              let unreadCount = entry["unreadCount"] as? Int else {
                            continue
                        }
                        
                        let thread = SmsThread(
                            threadId: threadId,
                            address: address,
                            contactName: entry["contactName"] as? String,
                            messageCount: messageCount,
                            snippet: snippet,
                            date: Date(timeIntervalSince1970: dateTimestamp),
                            unreadCount: unreadCount
                        )
                        loadedThreads.append(thread)
                    }
                }
                
                // Load messages by thread
                var loadedMessages: [String: [SmsMessage]] = [:]
                if let messagesData = cacheData["messagesByThread"] as? [String: [[String: Any]]] {
                    for (threadId, messages) in messagesData {
                        var threadMessages: [SmsMessage] = []
                        for entry in messages {
                            guard let id = entry["id"] as? String,
                                  let msgThreadId = entry["threadId"] as? String,
                                  let address = entry["address"] as? String,
                                  let body = entry["body"] as? String,
                                  let dateTimestamp = entry["date"] as? TimeInterval,
                                  let type = entry["type"] as? Int,
                                  let read = entry["read"] as? Bool else {
                                continue
                            }
                            
                            let message = SmsMessage(
                                id: id,
                                threadId: msgThreadId,
                                address: address,
                                body: body,
                                date: Date(timeIntervalSince1970: dateTimestamp),
                                type: type,
                                read: read,
                                contactName: entry["contactName"] as? String
                            )
                            threadMessages.append(message)
                        }
                        loadedMessages[threadId] = threadMessages
                    }
                }
                
                // Load timestamp
                var loadedTimestamp: Date?
                if let cachedAt = cacheData["cachedAt"] as? TimeInterval {
                    loadedTimestamp = Date(timeIntervalSince1970: cachedAt)
                }
                
                DispatchQueue.main.async {
                    self.smsThreads = loadedThreads
                    self.smsMessagesByThread = loadedMessages
                    self.smsThreadsCacheTimestamp = loadedTimestamp
                    print("[live-notif] 📱 Loaded \(loadedThreads.count) SMS threads from disk")
                }
            } catch {
                print("[live-notif] ❌ Failed to load SMS cache: \(error)")
            }
        }
    }
    
    /// Clear all SMS cache
    func clearAllSmsCache() {
        smsThreads.removeAll()
        smsMessagesByThread.removeAll()
        smsThreadsCacheTimestamp = nil
        try? FileManager.default.removeItem(at: smsCacheURL)
    }
    
    // MARK: - Call Logs Cache Persistence
    
    private var callLogsCacheURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("AirSync", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("call_logs_cache.json")
    }
    
    private func saveCallLogsCacheToDisk() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            
            do {
                var cacheData: [String: Any] = [:]
                
                // Save call logs
                var logsData: [[String: Any]] = []
                for log in self.callLogs {
                    var logEntry: [String: Any] = [
                        "id": log.id,
                        "number": log.number,
                        "date": log.date.timeIntervalSince1970,
                        "duration": log.duration,
                        "type": log.type,
                        "isRead": log.isRead
                    ]
                    if let contactName = log.contactName {
                        logEntry["contactName"] = contactName
                    }
                    logsData.append(logEntry)
                }
                cacheData["logs"] = logsData
                
                // Save timestamp
                if let timestamp = self.callLogsCacheTimestamp {
                    cacheData["cachedAt"] = timestamp.timeIntervalSince1970
                }
                
                let jsonData = try JSONSerialization.data(withJSONObject: cacheData, options: [.prettyPrinted])
                try jsonData.write(to: self.callLogsCacheURL)
                print("[live-notif] 📞 Saved \(logsData.count) call logs to disk")
            } catch {
                print("[live-notif] ❌ Failed to save call logs cache: \(error)")
            }
        }
    }
    
    private func loadCallLogsCacheFromDisk() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            
            do {
                guard FileManager.default.fileExists(atPath: self.callLogsCacheURL.path) else {
                    print("[live-notif] 📞 No call logs cache file found")
                    return
                }
                
                let jsonData = try Data(contentsOf: self.callLogsCacheURL)
                guard let cacheData = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                    return
                }
                
                // Load call logs
                var loadedLogs: [CallLogEntry] = []
                if let logsData = cacheData["logs"] as? [[String: Any]] {
                    for entry in logsData {
                        guard let id = entry["id"] as? String,
                              let number = entry["number"] as? String,
                              let dateTimestamp = entry["date"] as? TimeInterval,
                              let duration = entry["duration"] as? Int,
                              let type = entry["type"] as? String,
                              let isRead = entry["isRead"] as? Bool else {
                            continue
                        }
                        
                        let log = CallLogEntry(
                            id: id,
                            number: number,
                            contactName: entry["contactName"] as? String,
                            type: type,
                            date: Date(timeIntervalSince1970: dateTimestamp),
                            duration: duration,
                            isRead: isRead
                        )
                        loadedLogs.append(log)
                    }
                }
                
                // Load timestamp
                var loadedTimestamp: Date?
                if let cachedAt = cacheData["cachedAt"] as? TimeInterval {
                    loadedTimestamp = Date(timeIntervalSince1970: cachedAt)
                }
                
                DispatchQueue.main.async {
                    self.callLogs = loadedLogs
                    self.callLogsCacheTimestamp = loadedTimestamp
                    print("[live-notif] 📞 Loaded \(loadedLogs.count) call logs from disk")
                }
            } catch {
                print("[live-notif] ❌ Failed to load call logs cache: \(error)")
            }
        }
    }
    
    /// Clear all call logs cache
    func clearAllCallLogsCache() {
        callLogs.removeAll()
        callLogsCacheTimestamp = nil
        try? FileManager.default.removeItem(at: callLogsCacheURL)
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

