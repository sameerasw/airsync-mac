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
                            label: "Sync Clipboard",
                            systemImage: "doc.on.clipboard",
                            iconOnly: true,
                            circleSize: toolButtonSize,
                            action: {
                                let pasteboard = NSPasteboard.general
                                if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], let firstUrl = urls.first {
                                    DispatchQueue.global(qos: .userInitiated).async {
                                        WebSocketServer.shared.sendFile(url: firstUrl, isClipboard: true)
                                    }
                                } else if let image = NSImage(pasteboard: pasteboard) {
                                    // Handle copied image data
                                    let tempDir = FileManager.default.temporaryDirectory
                                    let tempUrl = tempDir.appendingPathComponent("clipboard_image_\(Int(Date().timeIntervalSince1970)).png")
                                    if let tiffData = image.tiffRepresentation,
                                       let bitmap = NSBitmapImageRep(data: tiffData),
                                       let pngData = bitmap.representation(using: .png, properties: [:]) {
                                        do {
                                            try pngData.write(to: tempUrl)
                                            DispatchQueue.global(qos: .userInitiated).async {
                                                WebSocketServer.shared.sendFile(url: tempUrl, isClipboard: true)
                                            }
                                        } catch {
                                            print("[MenubarView] Failed to save clipboard image: \(error)")
                                        }
                                    }
                                }
                            }
                        )
                        .transition(.identity)
                        .keyboardShortcut(
                            "v",
                            modifiers: [.command, .shift]
                        )
                        
                        GlassButtonView(
                            label: "Send",
                            systemImage: "paperplane.fill",
                            iconOnly: true,
                            circleSize: toolButtonSize,
                            action: {
                                let panel = NSOpenPanel()
                                panel.allowsMultipleSelection = true
                                panel.canChooseFiles = true
                                panel.canChooseDirectories = false
                                
                                if panel.runModal() == .OK {
                                    let targetName = appState.device?.name
                                    QuickShareManager.shared.startDiscovery(autoTargetName: targetName)
                                    QuickShareManager.shared.transferURLs = panel.urls
                                    appState.showingQuickShareTransfer = true
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
                            Button("Android Mirror") {
                                appState.isNativeMirroring = true
                            }
                            
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
                        label: appState.silenceAllNotifications ? "Disable DND" : "Enable DND",
                        systemImage: appState.silenceAllNotifications ? "bell.slash.fill" : "bell.badge",
                        iconOnly: true,
                        circleSize: toolButtonSize
                    ) {
                        appState.silenceAllNotifications.toggle()
                    }
                    .help(appState.silenceAllNotifications ? "Do Not Disturb is ON" : "Turn on Do Not Disturb")

                    GlassButtonView(
                        label: "Quit",
                        systemImage: "power",
                        iconOnly: true,
                        circleSize: toolButtonSize
                    ) {
                        NSApplication.shared.terminate(nil)
                    }

                    #if DEBUG
                    GlassButtonView(
                        label: "Crash",
                        systemImage: "bolt.trianglebadge.exclamationmark",
                        iconOnly: true,
                        circleSize: toolButtonSize
                    ) {
                        fatalError("Sentry Test Crash")
                    }
                    #endif
                }
                .padding(8)

                if appState.adbConnected && !appState.recentApps.isEmpty {
                    RecentAppsGridView()
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

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
        .dropTarget(appState: appState, autoTargetName: appState.device?.name)
        .onAppear {
            appState.isMenubarWindowOpen = true
        }
        .onDisappear {
            appState.isMenubarWindowOpen = false
        }
    }
}

#Preview {
    MenubarView()
}
