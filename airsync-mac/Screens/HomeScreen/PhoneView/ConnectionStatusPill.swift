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
                if appState.device != nil {
                    HStack(spacing: 6) {
                        Image(systemName: appState.connectionTransportIcon)
                            .contentTransition(.symbolEffect(.replace))

                        Text(appState.connectionTransportLabel)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(transportTint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(transportTint.opacity(0.14), in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(transportTint.opacity(0.22), lineWidth: 1)
                    )
                    .help(appState.connectionTransportHelp)
                } else {
                    Image(systemName: appState.connectionTransportIcon)
                        .contentTransition(.symbolEffect(.replace))
                        .help(appState.connectionTransportHelp)
                }
                
                if appState.isPlus {
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

                    if QuickShareManager.shared.isEnabled && QuickShareManager.shared.isRunning {
                        Image(systemName: "laptopcomputer.and.arrow.down")
                            .contentTransition(.symbolEffect(.replace))
                            .help("Quick Share Ready")
                            .transition(.asymmetric(
                                insertion: .scale.combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
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
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: QuickShareManager.shared.isRunning)
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

    private var transportTint: Color {
        switch appState.connectionTransportLabel {
        case "LAN":
            return .green
        case "Internet":
            return .orange
        default:
            return .secondary
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
    @ObservedObject var quickShareManager = QuickShareManager.shared
    @State private var currentIPAddress: String = "N/A"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connection")
                .font(.headline)
            
            if let device = appState.device {
                VStack(alignment: .leading, spacing: 8) {
                    ConnectionInfoText(
                        label: "Device",
                        icon: "iphone.gen3",
                        text: device.name
                    )
                    
                    ConnectionInfoText(
                        label: "IP Address",
                        icon: "wifi",
                        text: currentIPAddress,
                        activeIp: appState.activeMacIp
                    )

                    ConnectionInfoText(
                        label: "Transport",
                        icon: appState.connectionTransportIcon,
                        text: appState.connectionTransportLabel
                    )
                    
                    if appState.isPlus && appState.adbConnected {
                        ConnectionInfoText(
                            label: "ADB Connection",
                            icon: appState.adbConnectionMode == .wired ? "cable.connector" : "airplay.audio",
                            text: appState.adbConnectionMode == .wired ? "Wired (USB)" : "Wireless"
                        )
                    }

                    HStack {
                        Label("QuickShare", systemImage: "laptopcomputer.and.arrow.down")
                        Spacer()
                        Toggle("", isOn: $quickShareManager.isEnabled)
                            .toggleStyle(.switch)
                    }
                }
                .padding(.bottom, 4)
                
                HStack(spacing: 8) {
                    if appState.isPlus {
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
                    }
                    
                    GlassButtonView(
                        label: "Disconnect Device",
                        systemImage: "iphone.slash",
                        iconOnly: false,
                        primary: true,
                        action: {
                            appState.disconnectDevice()
                            if appState.isPlus {
                                ADBConnector.disconnectADB()
                            }
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
        .onAppear {
            currentIPAddress = WebSocketServer.shared.getLocalIPAddress(adapterName: appState.selectedNetworkAdapterName) ?? "N/A"
        }
    }
}


#Preview {
    ConnectionStatusPill()
        .padding()
        .background(Color.black.opacity(0.1))
}
