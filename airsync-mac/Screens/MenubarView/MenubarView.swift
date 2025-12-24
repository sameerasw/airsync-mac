//
//  MenubarView.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2025-08-08.
//

import SwiftUI

struct MenubarView: View {
    @Environment(\.openWindow) var openWindow
    @StateObject private var appState = AppState.shared
    @AppStorage("hasPairedDeviceOnce") private var hasPairedDeviceOnce: Bool = false
    private var appDelegate: AppDelegate? { AppDelegate.shared }

    private func focus(window: NSWindow) {
    if window.isMiniaturized { window.deminiaturize(nil) }
    window.collectionBehavior.insert(.moveToActiveSpace)
    NSApp.unhide(nil)
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
    }

    private func openAndFocusMainWindow() {

        DispatchQueue.main.async {
            if let window = self.appDelegate?.mainWindow {
                // Reuse the existing window
                window.makeKeyAndOrderFront(nil)
            } else {
                // Trigger creation
                self.openWindow(id: "main")
            }

            // Bring app + window to the front once
            NSApp.activate(ignoringOtherApps: true)
        }
    }



    private func getDeviceName() -> String {
        appState.device?.name ?? "Ready"
    }

    private let minWidthTabs: CGFloat = 280
    private let toolButtonSize: CGFloat = 38

    var body: some View {
        VStack {
            VStack(spacing: 12){
                // Header
                Text("AirSync - \(getDeviceName())")
                    .font(.headline)

                HStack(spacing: 10){
                    GlassButtonView(
                        label: "Open App",
                        systemImage: "arrow.up.forward.app",
                        iconOnly: true,
                        circleSize: toolButtonSize
                    ) {
                        openAndFocusMainWindow()
                    }

                    if (appState.device != nil){
                        GlassButtonView(
                            label: "Send",
                            systemImage: "square.and.arrow.up",
                            iconOnly: true,
                            circleSize: toolButtonSize,
                            action: {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = true
                                panel.canChooseDirectories = false
                                panel.allowsMultipleSelection = false
                                panel.begin { response in
                                    if response == .OK, let url = panel.url {
                                        DispatchQueue.global(qos: .userInitiated).async {
                                            WebSocketServer.shared.sendFile(url: url)
                                        }
                                    }
                                }
                            }
                        )
                        .transition(.identity)
                        .keyboardShortcut(
                            "f",
                            modifiers: .command
                        )
                    }


                    if appState.adbConnected{
                        GlassButtonView(
                            label: "Mirror",
                            systemImage: "apps.iphone",
                            iconOnly: true,
                            circleSize: toolButtonSize,
                            action: {
                                ADBConnector
                                    .startScrcpy(
                                        ip: appState.device?.ipAddress ?? "",
                                        port: appState.adbPort,
                                        deviceName: appState.device?.name ?? "My Phone"
                                    )
                            }
                        )
                        .transition(.identity)
                        .keyboardShortcut(
                            "p",
                            modifiers: .command
                        )
                        .contextMenu {
                            Button("Desktop Mode") {
                                ADBConnector.startScrcpy(
                                    ip: appState.device?.ipAddress ?? "",
                                    port: appState.adbPort,
                                    deviceName: appState.device?.name ?? "My Phone",
                                    desktop: true
                                )
                            }
                        }
                        .keyboardShortcut(
                            "p",
                            modifiers: [.command, .shift]
                        )
                    }

                    GlassButtonView(
                        label: "Quit",
                        systemImage: "power",
                        iconOnly: true,
                        circleSize: toolButtonSize
                    ) {
                        NSApplication.shared.terminate(nil)
                    }
                }
                .padding(8)

                if (appState.status != nil){
                    DeviceStatusView(showMediaToggle: false)
                        .transition(.opacity.combined(with: .scale))
                }

                if let music = appState.status?.music,
                let title = appState.status?.music.title.trimmingCharacters(in: .whitespacesAndNewlines),
                !title.isEmpty {

                    MediaPlayerView(music: music)
                        .transition(.opacity.combined(with: .scale))
                }


                if !appState.notifications.isEmpty {
                    GlassButtonView(
                        label: "Clear All",
                        systemImage: "wind",
                        action: {
                            appState.clearNotifications()
                        }
                    )
                    .help("Clear all notifications")
                }
            }
            .padding(10)

            if appState.device != nil {
                MenuBarNotificationsListView()
                    .frame(maxWidth: .infinity)
            }

        }
        .frame(minWidth: minWidthTabs)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    MenubarView()
}
