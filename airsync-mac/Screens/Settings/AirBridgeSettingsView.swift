//
//  AirBridgeSettingsView.swift
//  airsync-mac
//
//  Created by AI Assistant.
//

import SwiftUI

struct AirBridgeSettingsView: View {
    @ObservedObject var appState = AppState.shared
    @ObservedObject var airBridge = AirBridgeClient.shared

    @State private var relayURL: String = ""
    @State private var pairingId: String = ""
    @State private var secret: String = ""
    @State private var showSecret: Bool = false

    var body: some View {
        VStack(spacing: 12) {
            // Toggle
            HStack {
                Label("Enable AirBridge", systemImage: "antenna.radiowaves.left.and.right.circle.fill")
                Spacer()
                Toggle("", isOn: $appState.airBridgeEnabled)
                    .toggleStyle(.switch)
            }

            if appState.airBridgeEnabled {
                Divider()

                // Connection status
                HStack {
                    statusDot
                    Text(airBridge.connectionState.displayName)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()

                    if case .failed = airBridge.connectionState {
                        Button("Retry") {
                            AirBridgeClient.shared.connect()
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11))
                    }
                }

                Divider()

                // Relay Server URL
                HStack {
                    Label("Relay Server", systemImage: "server.rack")
                    Spacer()
                    TextField("wss://airbridge", text: $relayURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 220)
                        .onSubmit { saveRelayURL() }
                }

                // Pairing ID (128-bit hex, show truncated with copy option)
                HStack {
                    Label("Pairing ID", systemImage: "link")
                    Spacer()
                    Text(pairingId.prefix(12) + "...")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .help(pairingId)

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(pairingId, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy Pairing ID")

                    Button {
                        regeneratePairingCredentials()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Regenerate Pairing ID and Secret")
                }

                // Secret (passphrase)
                HStack {
                    Label("Secret", systemImage: "key")
                    Spacer()

                    if showSecret {
                        Text(secret)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } else {
                        Text("••••-••••-••••-••••")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        showSecret.toggle()
                    } label: {
                        Image(systemName: showSecret ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(secret, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy Secret")

                }

                Divider()

                // Save & Reconnect
                HStack {
                    Spacer()
                    Button {
                        saveAndReconnect()
                    } label: {
                        Label("Save & Reconnect", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .onAppear {
            if appState.airBridgeEnabled {
                loadCredentials()
            }
        }
        .onChange(of: appState.airBridgeEnabled) { enabled in
            if enabled {
                // Ensure default URL if missing
                if airBridge.relayServerURL.isEmpty {
                    airBridge.relayServerURL = "wss://airbridge.tornado.ovh/ws"
                }
                
                // Ensure credentials exist (generates and saves if missing)
                airBridge.ensureCredentialsExist()
                
                // Sync view state with the (possibly newly generated) credentials
                loadCredentials()
                
                // Auto-connect immediately so the QR code is live
                airBridge.connect()
            } else {
                airBridge.disconnect()
            }
        }
    }

    // MARK: - Helpers

    private func loadCredentials() {
        relayURL = airBridge.relayServerURL
        pairingId = airBridge.pairingId
        secret = airBridge.secret
    }

    @ViewBuilder
    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
    }

    private var statusColor: Color {
        switch airBridge.connectionState {
        case .disconnected:         return .gray
        case .connecting:           return .orange
        case .registering:          return .orange
        case .waitingForPeer:       return .yellow
        case .relayActive:          return .green
        case .failed:               return .red
        }
    }

    private func saveRelayURL() {
        // Batch-save all credentials (single Keychain write)
        airBridge.saveAllCredentials(url: relayURL, pairingId: pairingId, secret: secret)
    }

    private func saveAndReconnect() {
        airBridge.saveAllCredentials(url: relayURL, pairingId: pairingId, secret: secret)
        airBridge.disconnect()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            airBridge.connect()
        }
    }

    private func regeneratePairingCredentials() {
        airBridge.regeneratePairingCredentials()
        pairingId = airBridge.pairingId
        secret = airBridge.secret
    }
}
