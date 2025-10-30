//
//  LiveActivitiesView.swift
//  airsync-mac
//
//  Live Activities UI components for Dynamic Island and Notification Center
//

import SwiftUI

@available(macOS 13.0, *)
struct LiveActivitiesView: View {
    @ObservedObject private var manager = LiveActivitiesManager.shared
    
    var body: some View {
        VStack(spacing: 8) {
            // Active Call
            if let call = manager.activeCallActivity {
                LiveCallCard(activity: call)
            }
            
            // Active SMS
            if let sms = manager.activeSmsActivity {
                LiveSmsCard(activity: sms)
            }
            
            // Active Health
            if let health = manager.activeHealthActivity {
                LiveHealthCard(activity: health)
            }
        }
    }
}

@available(macOS 13.0, *)
struct LiveCallCard: View {
    let activity: LiveCallActivity
    
    var body: some View {
        HStack(spacing: 12) {
            // Call Icon
            ZStack {
                Circle()
                    .fill(callStateColor.opacity(0.2))
                    .frame(width: 40, height: 40)
                
                Image(systemName: callStateIcon)
                    .font(.title3)
                    .foregroundColor(callStateColor)
            }
            
            // Call Info
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.contactName)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                HStack {
                    Text(activity.state.rawValue.capitalized)
                        .font(.subheadline)
                        .foregroundColor(callStateColor)
                    
                    if activity.state == .active {
                        Text("•")
                            .foregroundColor(.secondary)
                        
                        Text(formatDuration(activity.duration))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Call Actions
            HStack(spacing: 8) {
                if activity.state == .ringing && activity.isIncoming {
                    // Answer button
                    Button(action: { answerCall() }) {
                        Image(systemName: "phone.fill")
                            .font(.title3)
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.green)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                
                // End call button
                Button(action: { endCall() }) {
                    Image(systemName: "phone.down.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.red)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(callStateColor.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var callStateColor: Color {
        switch activity.state {
        case .ringing:
            return activity.isIncoming ? .blue : .orange
        case .active:
            return .green
        case .held:
            return .yellow
        case .disconnected:
            return .gray
        }
    }
    
    private var callStateIcon: String {
        switch activity.state {
        case .ringing:
            return activity.isIncoming ? "phone.arrow.down.left" : "phone.arrow.up.right"
        case .active:
            return "phone.fill"
        case .held:
            return "phone.badge.pause"
        case .disconnected:
            return "phone.down"
        }
    }
    
    private func answerCall() {
        WebSocketServer.shared.sendCallAction("answer")
    }
    
    private func endCall() {
        WebSocketServer.shared.sendCallAction("hangup")
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

@available(macOS 13.0, *)
struct LiveSmsCard: View {
    let activity: LiveSmsActivity
    
    var body: some View {
        HStack(spacing: 12) {
            // SMS Icon
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 40, height: 40)
                
                Image(systemName: "message.fill")
                    .font(.title3)
                    .foregroundColor(.blue)
            }
            
            // SMS Info
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(activity.contactName)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    if activity.messageCount > 1 {
                        Text("(\(activity.messageCount))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Text(activity.lastMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            // SMS Actions
            HStack(spacing: 8) {
                // Reply button
                Button(action: { openSmsReply() }) {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.blue)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                
                // Mark as read button
                Button(action: { markAsRead() }) {
                    Image(systemName: "checkmark")
                        .font(.title3)
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.green)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
    }
    
    private func openSmsReply() {
        // Navigate to SMS detail view
        // This would need to be implemented based on your navigation structure
        print("[live-activities] Opening SMS reply for thread: \(activity.threadId)")
    }
    
    private func markAsRead() {
        WebSocketServer.shared.markSmsAsRead(messageId: activity.id)
        LiveActivitiesManager.shared.endSmsActivity(activity.threadId)
    }
}

@available(macOS 13.0, *)
struct LiveHealthCard: View {
    let activity: LiveHealthActivity
    
    var body: some View {
        HStack(spacing: 12) {
            // Health Icon
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 40, height: 40)
                
                Image(systemName: "heart.fill")
                    .font(.title3)
                    .foregroundColor(.green)
            }
            
            // Health Info
            VStack(alignment: .leading, spacing: 2) {
                Text("Health Update")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                HStack(spacing: 16) {
                    if activity.steps > 0 {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(activity.steps)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("steps")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if activity.calories > 0 {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(activity.calories)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("cal")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let heartRate = activity.heartRate {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(heartRate)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("bpm")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            Spacer()
            
            // Health Actions
            Button(action: { openHealthView() }) {
                Image(systemName: "arrow.right")
                    .font(.title3)
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.green)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
    }
    
    private func openHealthView() {
        // Navigate to health view
        print("[live-activities] Opening health view")
    }
}

// MARK: - Compact Live Activities for Menu Bar

@available(macOS 13.0, *)
struct CompactLiveActivitiesView: View {
    @ObservedObject private var manager = LiveActivitiesManager.shared
    
    var body: some View {
        HStack(spacing: 4) {
            if let call = manager.activeCallActivity {
                CompactCallIndicator(activity: call)
            }
            
            if let sms = manager.activeSmsActivity {
                CompactSmsIndicator(activity: sms)
            }
            
            if let health = manager.activeHealthActivity {
                CompactHealthIndicator(activity: health)
            }
        }
    }
}

@available(macOS 13.0, *)
struct CompactCallIndicator: View {
    let activity: LiveCallActivity
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "phone.fill")
                .font(.caption)
                .foregroundColor(activity.state == .active ? .green : .orange)
            
            if activity.state == .active {
                Text(formatDuration(activity.duration))
                    .font(.caption)
                    .monospacedDigit()
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

@available(macOS 13.0, *)
struct CompactSmsIndicator: View {
    let activity: LiveSmsActivity
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "message.fill")
                .font(.caption)
                .foregroundColor(.blue)
            
            if activity.messageCount > 1 {
                Text("\(activity.messageCount)")
                    .font(.caption)
                    .fontWeight(.medium)
            }
        }
    }
}

@available(macOS 13.0, *)
struct CompactHealthIndicator: View {
    let activity: LiveHealthActivity
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "heart.fill")
                .font(.caption)
                .foregroundColor(.green)
            
            if activity.steps > 0 {
                Text("\(activity.steps)")
                    .font(.caption)
                    .fontWeight(.medium)
            }
        }
    }
}