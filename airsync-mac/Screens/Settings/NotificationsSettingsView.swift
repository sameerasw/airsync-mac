//
//  NotificationsSettingsView.swift
//  AirSync
//
//  Created by Antigravity on 2026-06-04.
//

import SwiftUI
import UserNotifications

struct NotificationsSettingsView: View {
    @ObservedObject var appState = AppState.shared



    // State for notification permissions
    @State private var notificationsGranted = false
    @State private var notificationsChecked = false
    @State private var selectedSettingsApp: AndroidApp? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 1. Notifications Sync
                headerSection(title: L("settings.notifications.sync"), icon: "bell.badge")
                VStack {
                    SettingsToggleView(name: L("settings.notifications.dismiss"), icon: "bell.badge", isOn: $appState.dismissNotif)

                    HStack {
                        Label("Open app on notification click", systemImage: "arrow.up.forward.app")
                        Text("BETA")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.18))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                        Spacer()
                        Toggle("", isOn: $appState.openAppOnNotificationClick)
                            .toggleStyle(.switch)
                    }

                    HStack {
                        Label(L("settings.notifications.system"), systemImage: "bell.badge")
                        Spacer()

                        if notificationsGranted {
                            Picker("", selection: $appState.notificationSound) {
                                Text(L("settings.notifications.sound.default")).tag("default")
                                ForEach(SystemSounds.availableSounds, id: \.self) { sound in
                                    Text(sound).tag(sound)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            .frame(minWidth: 100)

                            Button(action: {
                                SystemSounds.playSound(appState.notificationSound)
                            }) {
                                Image(systemName: "play.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Test notification sound")
                        } else {
                            GlassButtonView(
                                label: L("settings.notifications.grant"),
                                systemImage: "bell.badge",
                                primary: true,
                                action: {
                                    openNotificationSettings()
                                }
                            )
                        }
                    }
                }
                .padding()
                .glassBoxIfAvailable(radius: 18)
                .onAppear {
                    checkNotificationPermissions()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    checkNotificationPermissions()
                }

                // 2. Call Alerts
                headerSection(title: L("settings.notifications.calls"), icon: "phone")
                VStack {
                    HStack {
                        Label(L("settings.notifications.callAlert"), systemImage: "phone")
                        Spacer()

                        Picker("", selection: $appState.callNotificationMode) {
                            ForEach(CallNotificationMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(minWidth: 120)
                    }

                    SettingsToggleView(name: L("settings.notifications.ring"), icon: "speaker.wave.3", isOn: $appState.ringForCalls)
                }
                .padding()
                .glassBoxIfAvailable(radius: 18)

                // 3. Apps
                headerSection(title: L("settings.notifications.app.title"), icon: "app.badge")
                VStack(spacing: 12) {
                    if appState.device == nil {
                        Text(L("settings.notifications.apps.connect"))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        let sortedApps = appState.androidApps.values.sorted(by: { $0.name.lowercased() < $1.name.lowercased() })
                        if sortedApps.isEmpty {
                            Text(L("settings.notifications.apps.none"))
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(sortedApps, id: \.packageName) { app in
                                HStack {
                                    if let iconPath = app.iconUrl,
                                       let image = Image(filePath: iconPath) {
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 24, height: 24)
                                            .cornerRadius(4)
                                    } else {
                                        Image(systemName: "app.badge")
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 24, height: 24)
                                            .foregroundColor(.gray)
                                    }
                                    
                                    Text(app.name)
                                        .font(.body)
                                    
                                    Spacer()
                                    
                                    Button(action: {
                                        selectedSettingsApp = app
                                    }) {
                                        Image(systemName: "gearshape")
                                            .font(.system(size: 14))
                                            .foregroundColor(app.listening ? .primary : .secondary.opacity(0.5))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!app.listening)
                                    .padding(.trailing, 8)
                                    
                                    Toggle("", isOn: Binding(
                                        get: { app.listening },
                                        set: { newValue in
                                            WebSocketServer.shared.toggleNotification(for: app.packageName, to: newValue)
                                        }
                                    ))
                                    .toggleStyle(.switch)
                                    .labelsHidden()
                                }
                                
                                if app.packageName != sortedApps.last?.packageName {
                                    Divider()
                                }
                            }
                        }
                    }
                }
                .padding()
                .glassBoxIfAvailable(radius: 18)
            }
            .padding()
        }
        .sheet(item: $selectedSettingsApp) { app in
            AppNotificationSettingsView(app: app)
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
