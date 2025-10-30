# Quick Integration Guide - Live Notifications

## 🚀 Get Started in 5 Minutes

### Step 1: Add to Your Main View
```swift
import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Your existing views
            PhoneView()
                .tabItem {
                    Label("Phone", systemImage: "iphone")
                }
                .tag(0)
            
            // NEW: Add Live Notifications tab
            LiveNotificationsView()
                .tabItem {
                    Label("Live", systemImage: "bell.badge")
                }
                .tag(1)
        }
    }
}
```

### Step 2: Test It!
1. Build and run the Mac app
2. Connect your Android device
3. Make a test call to your Android device
4. Send a test SMS to your Android device
5. Watch the live notifications appear!

## 📱 What You Get

### Automatic Features
- ✅ Incoming call notifications (floating window)
- ✅ SMS notifications (with reply action)
- ✅ Call history view
- ✅ SMS thread list
- ✅ Health data dashboard

### No Additional Code Needed
Everything is handled automatically by `LiveNotificationManager`:
- Call state tracking
- SMS notifications
- Health data updates
- Native macOS notifications

## 🎯 Quick Test Commands

### Test Call Notification
From Android, the app will automatically send when a call comes in.

### Test SMS
From Android, the app will automatically send when an SMS is received.

### Request Data Manually
```swift
// Request SMS threads
WebSocketServer.shared.requestSmsThreads()

// Request call logs
WebSocketServer.shared.requestCallLogs()

// Request health summary
WebSocketServer.shared.requestHealthSummary()
```

## 🔔 Notification Actions

Users can interact with notifications:
- **Call:** Answer or Decline
- **SMS:** Reply or Mark as Read

All actions are handled automatically!

## 📊 Access Live Data

```swift
// Get active call
if let call = LiveNotificationManager.shared.activeCall {
    print("Call with: \(call.displayName)")
}

// Get recent SMS
let sms = LiveNotificationManager.shared.recentSms

// Get health data
if let health = LiveNotificationManager.shared.healthSummary {
    print("Steps: \(health.steps ?? 0)")
}
```

## ✅ That's It!

You now have:
- Live call notifications
- SMS messaging
- Health data tracking
- Call history
- All with native macOS notifications

See `LIVE_NOTIFICATIONS_MAC_IMPLEMENTATION.md` for detailed documentation.
