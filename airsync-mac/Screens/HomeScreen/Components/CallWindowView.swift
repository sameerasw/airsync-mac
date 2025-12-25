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
            // For incoming calls, offhook means accepted; for outgoing, it's still ringing
            return callEvent.direction == .incoming ? "Accepted" : "Ringing..."
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
        // Show buttons when ringing or offhook
        callEvent.state == .ringing || callEvent.state == .offhook
    }
    
    var isCallAccepted: Bool {
        // Call is accepted when it's offhook for an incoming call
        callEvent.state == .offhook && callEvent.direction == .incoming
    }
    
    var displayName: String {
        // If contact name exists, use it
        if !callEvent.contactName.isEmpty {
            return callEvent.contactName
        }
        // Prefer original number over normalized if available
        if !callEvent.number.isEmpty {
            return callEvent.number
        }
        return callEvent.normalizedNumber
    }
    
    var displayNumber: String {
        // Show original number for display (more recognizable to user)
        callEvent.number.isEmpty ? callEvent.normalizedNumber : callEvent.number
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

                    Text(displayName)
                        .font(.largeTitle)

                    if !displayNumber.isEmpty {
                        Text(displayNumber)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .onAppear {
                                print("[CallWindow] Displaying number: '\(self.displayNumber)'")
                            }
                    }
                }

                // Action buttons (show when ringing/offhook - works via WebSocket or ADB)
                if showActionButtons {
                    VStack(spacing: 12) {
                        HStack(spacing: 16) {

                            if callEvent.direction == .incoming {
                                if isCallAccepted {
                                    // Call is accepted - show End button and audio controls
                                    
                                    // Mic toggle
                                    GlassButtonView(
                                        label: CallAudioManager.shared.isMicEnabled ? "Mute" : "Mic",
                                        systemImage: CallAudioManager.shared.isMicEnabled ? "mic.fill" : "mic.slash.fill",
                                        size: .large,
                                        action: {
                                            CallAudioManager.shared.toggleMic()
                                        }
                                    )
                                    .foregroundStyle(CallAudioManager.shared.isMicEnabled ? .blue : .secondary)
                                    .transition(.identity)
                                    
                                    GlassButtonView(
                                        label: "End",
                                        systemImage: "phone.down.fill",
                                        size: .extraLarge,
                                        action: {
                                            appState.sendCallAction(callEvent.eventId, action: "end")
                                        }
                                    )
                                    .foregroundStyle(.red)
                                    .transition(.identity)
                                } else {
                                    // Call is ringing - show Accept and Decline buttons
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

                            } else if callEvent.direction == .outgoing {
                                
                                // Mic toggle for outgoing calls
                                GlassButtonView(
                                    label: CallAudioManager.shared.isMicEnabled ? "Mute" : "Mic",
                                    systemImage: CallAudioManager.shared.isMicEnabled ? "mic.fill" : "mic.slash.fill",
                                    size: .large,
                                    action: {
                                        CallAudioManager.shared.toggleMic()
                                    }
                                )
                                .foregroundStyle(CallAudioManager.shared.isMicEnabled ? .blue : .secondary)
                                .transition(.identity)

                                GlassButtonView(
                                    label: "End",
                                    systemImage: "phone.down.fill",
                                    size: .extraLarge,
                                    action: {
                                        appState.sendCallAction(callEvent.eventId, action: "end")
                                    }
                                )
                                .foregroundStyle(.red)
                                .transition(.identity)
                            }
                        }
                        
                        // Note about call audio feature
                        if isCallAccepted || callEvent.direction == .outgoing {
                            Text("Tap mic to use Mac audio for call")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 8)
                }

            }
            .padding(24)
        }
        .frame(minWidth: 320, minHeight: 320)
        .onAppear {
            NSWindow.allowsAutomaticWindowTabbing = false
            
            // Make call window float above all apps
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "callWindow" || $0.title == "Call" }) {
                    window.level = .floating
                    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
                    window.isMovableByWindowBackground = true
                    window.backgroundColor = NSColor.clear
                    window.titlebarAppearsTransparent = true
                    window.titleVisibility = .hidden
                    window.styleMask.insert(.fullSizeContentView)
                    window.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                    print("[CallWindow] Set window level to floating, visible on all spaces")
                }
            }
        }
    }
}
