//
//  SyncSettingsView.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2026-05-20.
//

import SwiftUI
import UserNotifications

struct SyncSettingsView: View {
    @ObservedObject var appState = AppState.shared
    @State private var showingPlusPopover = false
    @State private var showRemoteSheet = false

    @State private var showPairingSheet = false
    @AppStorage("showInControlCenter") private var showInControlCenter = false
    @State private var showControlCenterInfo = false

    // State for notification permissions
    @State private var notificationsGranted = false
    @State private var notificationsChecked = false

    var body: some View {
        ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // 1. Connection & ADB
                        HStack {
                            headerSection(title: "Connection & ADB", icon: "bolt.horizontal.circle")
                            Spacer()
                            GlassButtonView(
                                label: L("settings.newDevice"),
                                systemImage: "qrcode",
                                action: {
                                    showPairingSheet = true
                                }
                            )
                            .padding(.trailing, 8)
                        }
                        VStack(spacing: 12) {
                            ZStack {
                                HStack {
                                    Label("Auto connect ADB", systemImage: "bolt.horizontal.circle")
                                    Spacer()

                                    if appState.adbConnected {
                                        GlassButtonView(
                                            label: "Disconnect ADB",
                                            systemImage: "stop.circle",
                                            action: {
                                                ADBConnector.disconnectADB()
                                                appState.adbConnected = false
                                            }
                                        )
                                    } else {
                                        GlassButtonView(
                                            label: appState.adbConnecting ? "Connecting..." : "Connect ADB",
                                            systemImage: appState.adbConnecting ? "hourglass" : "play.circle",
                                            action: {
                                                if !appState.adbConnecting {
                                                    appState.adbConnectionResult = "" // Clear console
                                                    appState.manualAdbConnectionPending = true
                                                    appState.userInitiatedAdbConnect = true
                                                    WebSocketServer.shared.sendRefreshAdbPortsRequest()
                                                    appState.adbConnectionResult = "Refreshing latest ADB ports from device..."
                                                }
                                            }
                                        )
                                        .disabled(
                                            appState.device == nil || appState.adbConnecting || !AppState.shared.isPlus
                                        )
                                    }

                                    ZStack {
                                        Toggle(
                                            "",
                                            isOn: $appState.adbEnabled
                                        )
                                        .labelsHidden()
                                        .toggleStyle(.switch)
                                        .disabled(!AppState.shared.isPlus && AppState.shared.licenseCheck)
                                    }
                                    .frame(width: 55)
                                }

                                if !AppState.shared.isPlus && AppState.shared.licenseCheck {
                                    HStack {
                                        Spacer()
                                        Rectangle()
                                            .fill(Color.clear)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                showingPlusPopover = true
                                            }
                                            .frame(width: 500)
                                    }
                                }
                            }
                            .popover(isPresented: $showingPlusPopover, arrowEdge: .bottom) {
                                PlusFeaturePopover(message: "Wireless and Wired ADB features are available in AirSync+")
                                    .onTapGesture {
                                        showingPlusPopover = false
                                    }
                            }

                            HStack {
                                Label(L("settings.alwaysKillAdbBeforeConnect"), systemImage: "arrow.clockwise.circle")
                                Spacer()
                                Toggle("", isOn: $appState.alwaysKillAdbBeforeConnect)
                                    .toggleStyle(.switch)
                            }

                            HStack {
                                Label("Fallback to mDNS services", systemImage: "antenna.radiowaves.left.and.right")
                                Spacer()
                                Toggle("", isOn: $appState.fallbackToMdns)
                                    .toggleStyle(.switch)
                            }

                            if let result = appState.adbConnectionResult {
                                VStack(alignment: .leading, spacing: 6) {
                                    ExpandableLicenseSection(title: "ADB Console", content: "[" + (UserDefaults.standard.lastADBCommand ?? "[]") + "] " + result, copyable: true)
                                }
                            }

                            HStack {
                                ZStack {
                                    HStack {
                                        Label(L("settings.wiredAdb"), systemImage: "cable.connector")
                                        Spacer()
                                        Toggle("", isOn: $appState.wiredAdbEnabled)
                                            .toggleStyle(.switch)
                                            .disabled(!AppState.shared.isPlus && AppState.shared.licenseCheck)
                                    }
                                    
                                    if !AppState.shared.isPlus && AppState.shared.licenseCheck {
                                        HStack {
                                            Spacer()
                                            Rectangle()
                                                .fill(Color.clear)
                                                .contentShape(Rectangle())
                                                .onTapGesture {
                                                    showingPlusPopover = true
                                                }
                                                .frame(width: 500)
                                        }
                                    }
                                }
                            }

                            HStack {
                                Label("Suppress failed messages", systemImage: "bell.slash")
                                Spacer()
                                Toggle("", isOn: $appState.suppressAdbFailureAlerts)
                                    .toggleStyle(.switch)
                            }
                        }
                        .padding()
                        .glassBoxIfAvailable(radius: 18)

                        // 2. Clipboard Sync
                        headerSection(title: "Clipboard Sync", icon: "clipboard")
                        VStack {
                            SettingsToggleView(name: "Sync clipboard", icon: "clipboard", isOn: $appState.isClipboardSyncEnabled)

                            HStack {
                                Label("Auto-open shared links", systemImage: "link")
                                Spacer()
                                Toggle("", isOn: $appState.autoOpenLinks)
                                    .toggleStyle(.switch)
                                    .disabled(!appState.isClipboardSyncEnabled)
                            }
                            .opacity(appState.isClipboardSyncEnabled ? 1.0 : 0.5)
                        }
                        .padding()
                        .glassBoxIfAvailable(radius: 18)

                        // 3. Media Player
                        headerSection(title: "Media Player", icon: "play.circle")
                        VStack {
                            SettingsToggleView(name: "Send now playing status", icon: "play.circle", isOn: $appState.sendNowPlayingStatus)

                            HStack {
                                Label("Show in control center", systemImage: "slider.horizontal.below.rectangle")
                                Button(action: { showControlCenterInfo = true }) {
                                    Image(systemName: "info.circle")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .alert("Show in control center", isPresented: $showControlCenterInfo) {
                                    Button("OK", role: .cancel) {}
                                } message: {
                                    Text("This feature plays a silent audio track in background in order to show up in macOS media. This may prevent your multi-device bluetooth audio devices to not switch correctly.")
                                }
                                Spacer()
                                Toggle("", isOn: $showInControlCenter)
                                    .toggleStyle(.switch)
                                    .onChange(of: showInControlCenter) { _, enabled in
                                        if enabled {
                                            NowPlayingPublisher.shared.enableSilentAudio()
                                        } else {
                                            NowPlayingPublisher.shared.disableSilentAudio()
                                        }
                                    }
                            }
                        }
                        .padding()
                        .glassBoxIfAvailable(radius: 18)

                        // 5. Remote Controls
                        headerSection(title: "Remote Controls", icon: "accessibility")
                        VStack {
                            HStack {
                                Label("Remote control permission", systemImage: "accessibility")
                                Spacer()
                                GlassButtonView(label: "Configure", systemImage: "gearshape") {
                                    showRemoteSheet = true
                                }
                            }
                        }
                        .padding()
                        .glassBoxIfAvailable(radius: 18)
                        .sheet(isPresented: $showRemoteSheet) {
                            RemotePermissionView()
                        }
                        .sheet(isPresented: $showPairingSheet) {
                            ADBPairingSheetView()
                        }
                    }
                    .padding()
                }
    }

    @ViewBuilder
    private func headerSection(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Notification Permission Helpers
    func checkNotificationPermissions() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                notificationsGranted = (settings.authorizationStatus == .authorized)
                notificationsChecked = true
            }
        }
    }

    func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }
}
