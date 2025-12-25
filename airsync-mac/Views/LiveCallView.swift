//
//  LiveCallView.swift
//  airsync-mac
//
//  Live call notification view
//

import SwiftUI
internal import Combine

#if canImport(SwiftUI)
struct LiveCallView: View {
    @ObservedObject private var manager = LiveNotificationManager.shared
    let call: LiveCallNotification
    
    @State private var currentTime = Date()
    
    var body: some View {
        VStack(spacing: 20) {
            // Call state
            Text(call.stateDescription)
                .font(.headline)
                .foregroundColor(.secondary)
            
            // Contact/Number
            VStack(spacing: 4) {
                if let contactName = call.contactName {
                    Text(contactName)
                        .font(.title)
                        .fontWeight(.semibold)
                    Text(call.number)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Text(call.number)
                        .font(.title)
                        .fontWeight(.semibold)
                }
            }
            
            // Duration (for active calls)
            if call.state == .accepted || call.state == .offhook {
                Text(formatDuration(currentTime.timeIntervalSince(call.startTime)))
                    .font(.title2)
                    .monospacedDigit()
                    .foregroundColor(.green)
                    .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { time in
                        currentTime = time
                    }
            }
            
            Spacer()
            
            // Actions
            if call.state == .ringing && call.isIncoming {
                HStack(spacing: 20) {
                    Button(action: {
                        manager.declineCall()
                    }) {
                        VStack {
                            Image(systemName: "phone.down.fill")
                                .font(.title2)
                            Text("Decline")
                                .font(.caption)
                        }
                        .frame(width: 80, height: 60)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        manager.answerCall()
                    }) {
                        VStack {
                            Image(systemName: "phone.fill")
                                .font(.title2)
                            Text("Answer")
                                .font(.caption)
                        }
                        .frame(width: 80, height: 60)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
            } else if call.state == .accepted || call.state == .offhook {
                Button(action: {
                    manager.declineCall()
                }) {
                    VStack {
                        Image(systemName: "phone.down.fill")
                            .font(.title2)
                        Text("End Call")
                            .font(.caption)
                    }
                    .frame(width: 100, height: 60)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
#endif
