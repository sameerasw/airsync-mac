//
//  ConnectionStatusPill.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2026-03-11.
//

import SwiftUI

struct ConnectionStatusPill: View {
    @ObservedObject var appState = AppState.shared
    
    var body: some View {
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
        .applyGlassViewIfAvailable()
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: appState.adbConnected)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: appState.adbConnectionMode)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: appState.isConnectedOverLocalNetwork)
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

#Preview {
    ConnectionStatusPill()
        .padding()
        .background(Color.black.opacity(0.1))
}
