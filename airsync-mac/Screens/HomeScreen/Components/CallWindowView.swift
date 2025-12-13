import SwiftUI

struct CallWindowView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismissWindow) var dismissWindow
    let callEvent: CallEvent
    
    var contactImage: NSImage? {
        guard let photoString = callEvent.contactPhoto, !photoString.isEmpty else {
            return nil
        }
        
        // Try to decode the base64 PNG data
        if let photoData = Data(base64Encoded: photoString, options: .ignoreUnknownCharacters) {
            if let image = NSImage(data: photoData) {
                print("[CallWindow] Successfully decoded contact photo, size: \(photoData.count) bytes")
                return image
            } else {
                print("[CallWindow] ERROR: Base64 decoded but NSImage creation failed. Data size: \(photoData.count) bytes")
                print("[CallWindow] First 100 chars of photo string: \(photoString.prefix(100))")
            }
        } else {
            print("[CallWindow] ERROR: Failed to decode base64 photo string. String size: \(photoString.count) chars")
            print("[CallWindow] First 100 chars: \(photoString.prefix(100))")
        }
        
        return nil
    }
    
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
        ZStack {
            // Blurred background image (only if contact photo exists)
            if let contactImage = contactImage {
                Image(nsImage: contactImage)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .blur(radius: 20)
                    .opacity(0.3)
            }
            
            // Content overlay
            VStack(spacing: 12) {
                // Header with direction
                Text(callDirectionText + " ・ " + callStateText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Contact info
                VStack(spacing: 6) {
                    if let contactImage = contactImage {
                        Image(nsImage: contactImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 150, height: 150)
                            .clipShape(FlowerShape())
                    } else {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 128))
                            .foregroundColor(.blue)
                    }
                    
                    Text(callEvent.contactName)
                        .font(.largeTitle)

                    if !callEvent.normalizedNumber.isEmpty {
                        Text(callEvent.normalizedNumber)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
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
                        .foregroundStyle(.green)
                        .transition(.identity)


                        GlassButtonView(
                            label: "Decline",
                            systemImage: "phone.down.fill",
                            size: .extraLarge,
                            action: {
                                appState.sendCallAction(callEvent.eventId, action: "decline")
                            }
                        )
                        .foregroundStyle(.red)
                        .transition(.identity)

                    }
                    .padding(.top, 8)
                }

            }
            .padding(24)
        }
        .frame(minWidth: 320, minHeight: 320)
        .onAppear {
            NSWindow.allowsAutomaticWindowTabbing = false
        }
    }
}
