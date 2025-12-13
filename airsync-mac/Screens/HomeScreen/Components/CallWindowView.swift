import SwiftUI

struct CallWindowView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismissWindow) var dismissWindow
    let callEvent: CallEvent
    
    var callDirectionText: String {
        switch callEvent.direction {
        case .incoming:
            return "Incoming Call"
        case .outgoing:
            return "Outgoing Call"
        }
    }
    
    var callStateText: String {
        switch callEvent.state {
        case .ringing:
            return "Ringing..."
        case .offhook:
            return "Ringing..."
        case .accepted:
            return "Accepted"
        case .rejected:
            return "Rejected"
        case .ended:
            return "Ended"
        case .missed:
            return "Missed"
        case .idle:
            return "Idle"
        }
    }
    
    var showActionButtons: Bool {
        callEvent.state == .ringing || callEvent.state == .offhook
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Header with direction
            Text(callDirectionText)
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Contact info
            VStack(spacing: 6) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 128))
                    .foregroundColor(.blue)
                
                Text(callEvent.contactName)
                    .font(.largeTitle)

                if !callEvent.normalizedNumber.isEmpty {
                    Text(callEvent.normalizedNumber)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Call state
            Text(callStateText)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            // Action buttons (only show when ringing/offhook)
            if showActionButtons {
                HStack(spacing: 16) {

                    GlassButtonView(
                        label: "Accept",
                        systemImage: "phone.fill",
                        size: .extraLarge,
                        action: {
                            appState.sendCallAction(callEvent.eventId, action: "accept")
                        }
                    )
                    .tint(.green)
                    .transition(.identity)


                    GlassButtonView(
                        label: "Decline",
                        systemImage: "phone.down.fill",
                        size: .extraLarge,
                        action: {
                            appState.sendCallAction(callEvent.eventId, action: "decline")
                        }
                    )
                    .tint(.red)
                    .transition(.identity)

                }
                .padding(.top, 8)
            }

        }
        .padding(24)
        .frame(minWidth: 320, minHeight: 320)
        .onAppear {
            NSWindow.allowsAutomaticWindowTabbing = false
        }
    }
}
