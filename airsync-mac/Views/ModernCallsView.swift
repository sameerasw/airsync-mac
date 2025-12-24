//
//  ModernCallsView.swift
//  airsync-mac
//
//  Modern glassmorphic calls view
//

import SwiftUI
internal import Combine

struct CallsView: View {
    @ObservedObject private var manager = LiveNotificationManager.shared
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Active call banner
                if let call = manager.activeCall, call.state != .ended && call.state != .rejected && call.state != .missed {
                    ActiveCallCard(call: call)
                        .transition(.scale.combined(with: .opacity))
                }
                
                // Call history
                if manager.callLogs.isEmpty {
                    EmptyStateCard(
                        icon: "phone.fill",
                        title: "No Call History",
                        message: "Call logs will appear here"
                    )
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(manager.callLogs) { log in
                            CallLogCard(log: log)
                        }
                    }
                }
            }
            .padding()
        }
        .onAppear {
            // Use caching - this will return cached data immediately and request fresh data if needed
            _ = manager.getCallLogs()
        }
    }
}

struct ActiveCallCard: View {
    let call: LiveCallNotification
    @State private var currentTime = Date()
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 50, height: 50)
                
                Image(systemName: "phone.fill")
                    .font(.title2)
                    .foregroundColor(.green)
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(call.displayName)
                    .font(.headline)
                Text(call.stateDescription)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Duration
            if call.state == .accepted || call.state == .offhook {
                Text(formatDuration(call.duration))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundColor(.green)
                    .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                        currentTime = Date()
                    }
            }
        }
        .padding()
        .background(.background.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct CallLogCard: View {
    let log: CallLogEntry
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.2))
                    .frame(width: 44, height: 44)
                
                Image(systemName: log.typeIcon)
                    .font(.title3)
                    .foregroundColor(iconColor)
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(log.displayName)
                    .font(.headline)
                Text(log.number)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Time & Duration
            VStack(alignment: .trailing, spacing: 4) {
                Text(log.date, style: .time)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(log.durationFormatted)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(.background.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
    }
    
    private var iconColor: Color {
        switch log.type {
        case "incoming": return .blue
        case "outgoing": return .green
        case "missed": return .red
        default: return .gray
        }
    }
}

struct EmptyStateCard: View {
    let icon: String
    let title: String
    let message: String
    
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: icon)
                    .font(.system(size: 36))
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 8) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(.background.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
    }
}
