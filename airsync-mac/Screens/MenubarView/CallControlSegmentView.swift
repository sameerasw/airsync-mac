//
//  CallControlSegmentView.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2026-05-23.
//

import SwiftUI

struct CallControlSegmentView: View {
    @ObservedObject var appState = AppState.shared
    
    var body: some View {
        if let callEvent = appState.activeCall {
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    if let photoString = callEvent.contactPhoto,
                       !photoString.isEmpty,
                       let photoData = Data(base64Encoded: photoString, options: .ignoreUnknownCharacters) ?? Data(base64Encoded: photoString),
                       let image = NSImage(data: photoData) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 48, height: 48)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                            .foregroundColor(.blue)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(callEvent.contactName)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        
                        Text(callDirectionText(callEvent) + " • " + callStateText(callEvent))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                }
                
                if appState.isPlus && appState.licenseCheck {
                    HStack(spacing: 16) {
                        if callEvent.direction == .incoming {
                            if isCallAccepted(callEvent) {
                                GlassButtonView(
                                    label: L("menubar.call.end"),
                                    systemImage: "phone.down.fill",
                                    size: .large,
                                    action: {
                                        appState.sendCallAction(callEvent.eventId, action: "end")
                                    }
                                )
                                .foregroundStyle(.red)
                            } else {
                                GlassButtonView(
                                    label: L("menubar.call.accept"),
                                    systemImage: "phone.fill",
                                    size: .large,
                                    action: {
                                        appState.sendCallAction(callEvent.eventId, action: "accept")
                                    }
                                )
                                .foregroundStyle(.green)
                                
                                GlassButtonView(
                                    label: L("menubar.call.decline"),
                                    systemImage: "phone.down.fill",
                                    size: .large,
                                    action: {
                                        appState.sendCallAction(callEvent.eventId, action: "decline")
                                    }
                                )
                                .foregroundStyle(.red)
                            }
                        } else if callEvent.direction == .outgoing {
                            GlassButtonView(
                                label: L("menubar.call.end"),
                                systemImage: "phone.down.fill",
                                size: .large,
                                action: {
                                    appState.sendCallAction(callEvent.eventId, action: "end")
                                }
                            )
                            .foregroundStyle(.red)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(12)
            .segmentStyle()
        }
    }
    
    private func callDirectionText(_ callEvent: CallEvent) -> String {
        switch callEvent.direction {
        case .incoming:
            return L("menubar.call.incomingCall")
        case .outgoing:
            return L("menubar.call.outgoingCall")
        }
    }
    
    private func callStateText(_ callEvent: CallEvent) -> String {
        switch callEvent.state {
        case .ringing:
            return L("menubar.call.ringing")
        case .offhook:
            return callEvent.direction == .incoming ? L("menubar.call.accepted") : L("menubar.call.ringing")
        case .accepted:
            return L("menubar.call.accepted")
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
    
    private func isCallAccepted(_ callEvent: CallEvent) -> Bool {
        callEvent.state == .offhook && callEvent.direction == .incoming
    }
}
