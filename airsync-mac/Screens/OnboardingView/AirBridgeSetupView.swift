//
//  AirBridgeSetupView.swift
//  AirSync
//
//  Created by AI Assistant.
//

import SwiftUI

struct AirBridgeSetupView: View {
    let onNext: () -> Void
    let onSkip: () -> Void

    @ObservedObject var appState = AppState.shared
    @ObservedObject var airBridge = AirBridgeClient.shared

    @State private var relayURL: String = ""
    @State private var pairingId: String = ""
    @State private var secret: String = ""
    @State private var showSecret: Bool = false

    @State private var isTesting: Bool = false
    @State private var testError: String? = nil
    @State private var showErrorAlert: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            ScrollView {
                VStack(spacing: 20) {
                    Text("AirBridge Relay")
                        .font(.title)
                        .multilineTextAlignment(.center)
                        .padding()

                    Text("AirBridge allows you to connect your Mac and Android device over the internet when they are not on the same Wi-Fi network. If you have an AirBridge relay server, you can configure it now.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 500)

                    VStack(alignment: .leading, spacing: 16) {
                        Toggle("Enable AirBridge", isOn: $appState.airBridgeEnabled)
                            .toggleStyle(.switch)
                            .padding(.bottom, 8)
                            .onChange(of: appState.airBridgeEnabled) { enabled in
                                if enabled {
                                    // Generate credentials in memory only — no Keychain access
                                    if pairingId.isEmpty {
                                        pairingId = AirBridgeClient.generateShortId()
                                    }
                                    if secret.isEmpty {
                                        secret = AirBridgeClient.generateRandomSecret()
                                    }
                                }
                            }

                        if appState.airBridgeEnabled {
                            VStack(alignment: .leading, spacing: 12) {
                                // Relay Server URL
                                HStack {
                                    Label("Server URL", systemImage: "server.rack")
                                        .frame(width: 100, alignment: .leading)
                                    TextField("wss://airbridge", text: $relayURL)
                                        .textFieldStyle(.roundedBorder)
                                }

                                // Pairing ID
                                HStack {
                                    Label("Pairing ID", systemImage: "link")
                                        .frame(width: 100, alignment: .leading)
                                    TextField("Generated automatically", text: $pairingId)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(.body, design: .monospaced))
                                    
                                    Button {
                                        // Generate in memory only — no Keychain writes during onboarding
                                        pairingId = AirBridgeClient.generateShortId()
                                        secret = AirBridgeClient.generateRandomSecret()
                                    } label: {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Regenerate Credentials")
                                }

                                // Secret
                                HStack {
                                    Label("Secret", systemImage: "key")
                                        .frame(width: 100, alignment: .leading)
                                    
                                    Group {
                                        if showSecret {
                                            TextField("Secret", text: $secret)
                                                .font(.system(.body, design: .monospaced))
                                        } else {
                                            SecureField("Secret", text: $secret)
                                        }
                                    }
                                    .textFieldStyle(.roundedBorder)

                                    Button {
                                        showSecret.toggle()
                                    } label: {
                                        Image(systemName: showSecret ? "eye.slash" : "eye")
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                            .padding()
                            .background(Color.secondary.opacity(0.08))
                            .cornerRadius(10)
                            .frame(maxWidth: 500)
                        }
                    }
                    .frame(maxWidth: 500)
                    .padding(.top, 10)
                }
                .padding(.bottom, 10)
            }

            HStack(spacing: 16) {
                if !appState.airBridgeEnabled {
                    GlassButtonView(
                        label: "Skip",
                        size: .large,
                        action: onSkip
                    )
                    .transition(.identity)
                } else {
                    GlassButtonView(
                        label: isTesting ? "Testing…" : "Continue",
                        systemImage: isTesting ? "hourglass" : "arrow.right.circle",
                        size: .large,
                        primary: true,
                        action: runConnectivityTest
                    )
                    .disabled(isTesting || relayURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .transition(.identity)
                }
            }
            .padding(.bottom, 10)
        }
        .onAppear {
            if appState.airBridgeEnabled {
                loadCredentials()
            }
        }
        .alert("Connection Failed", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(testError ?? "Could not reach the relay server.")
        }
    }

    private func runConnectivityTest() {
        guard !relayURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isTesting = true
        AirBridgeClient.shared.testConnectivity(
            url: relayURL,
            pairingId: pairingId,
            secret: secret
        ) { result in
            isTesting = false
            switch result {
            case .success:
                saveCredentials()
                AirBridgeClient.shared.connect()
                onNext()
            case .failure(let error):
                testError = error.localizedDescription
                showErrorAlert = true
            }
        }
    }

    private func loadCredentials() {
        relayURL = airBridge.relayServerURL
        pairingId = airBridge.pairingId
        secret = airBridge.secret
    }

    private func saveCredentials() {
        airBridge.saveAllCredentials(url: relayURL, pairingId: pairingId, secret: secret)
    }
}

#Preview {
    AirBridgeSetupView(onNext: {}, onSkip: {})
}
