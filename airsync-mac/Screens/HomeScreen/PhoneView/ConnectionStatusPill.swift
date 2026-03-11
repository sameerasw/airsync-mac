//
//  ConnectionStatusPill.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2026-03-11.
//

import SwiftUI

struct ConnectionStatusPill: View {
    @ObservedObject var appState = AppState.shared
    @State private var showingPopover = false
    @State private var isHovered = false
    
    var body: some View {
        Button(action: {
            showingPopover.toggle()
        }) {
            HStack(spacing: 8) {
                // Network Connection Icon
                Image(systemName: appState.isConnectedOverLocalNetwork ? "wifi" : "globe")
                    .contentTransition(.symbolEffect(.replace))
                    .help(appState.isConnectedOverLocalNetwork ? "Local WiFi" : "Extended Connection (Tailscale)")
                
                if appState.adbConnecting {
                    ProgressView()
                        .controlSize(.small)
                        .transition(.asymmetric(
                            insertion: .scale.combined(with: .opacity),
                            removal: .opacity
                        ))
                } else if appState.adbConnected {
                    // ADB Indicator
                    HStack(spacing: 6) {
                        Image(systemName: "iphone.gen3.crop.circle")
                            .contentTransition(.symbolEffect(.replace))
                        
                        // ADB Mode Icon
                        Image(systemName: adbModeIcon)
                            .contentTransition(.symbolEffect(.replace))
                            .help(adbModeHelp)
                    }
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .opacity
                    ))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .applyGlassViewIfAvailable()
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: appState.adbConnected)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: appState.adbConnectionMode)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: appState.isConnectedOverLocalNetwork)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
        .popover(isPresented: $showingPopover, arrowEdge: .top) {
            ConnectionPillPopover()
        }
    }
    
    private var adbModeIcon: String {
        switch appState.adbConnectionMode {
        case .wired:
            return "cable.connector"
        case .wireless, .none:
            return "airplay.audio"
        }
    }
    
    private var adbModeHelp: String {
        switch appState.adbConnectionMode {
        case .wired:
            return "Wired ADB Connection"
        case .wireless, .none:
            return "Wireless ADB Connection"
        }
    }
}

struct ConnectionPillPopover: View {
    @ObservedObject var appState = AppState.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connection")
                .font(.headline)
            
            if appState.device != nil {
                HStack(spacing: 8) {
                    if appState.adbConnected {
                        GlassButtonView(
                            label: "Disconnect ADB",
                            systemImage: "cable.connector.slash",
                            iconOnly: false,
                            primary: false,
                            action: {
                                ADBConnector.disconnectADB()
                            }
                        )
                        .focusable(false)
                    } else if !appState.adbConnecting {
                        GlassButtonView(
                            label: "Connect ADB",
                            systemImage: "cable.connector",
                            iconOnly: false,
                            primary: false,
                            action: {
                                if !appState.adbConnecting {
                                    appState.adbConnectionResult = "" // Clear console
                                    appState.manualAdbConnectionPending = true
                                    WebSocketServer.shared.sendRefreshAdbPortsRequest()
                                    appState.adbConnectionResult = "Refreshing latest ADB ports from device..."
                                }
                            }
                        )
                        .focusable(false)
                    } else {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Connecting ADB...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    GlassButtonView(
                        label: "Disconnect Device",
                        systemImage: "iphone.slash",
                        iconOnly: false,
                        primary: true,
                        action: {
                            appState.disconnectDevice()
                            ADBConnector.disconnectADB()
                            appState.adbConnected = false
                        }
                    )
                    .focusable(false)
                }
            } else {
                Text("No device connected")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}


#Preview {
    ConnectionStatusPill()
        .padding()
        .background(Color.black.opacity(0.1))
}
