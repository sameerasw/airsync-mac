//
//  ScreenView.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2025-09-20.
//

import SwiftUI
import AppKit

struct ScreenView: View {
    @ObservedObject var appState = AppState.shared
    @State private var showingPlusPopover = false

    var body: some View {
        VStack {
            ConnectionStatusPill()
                .padding(.top, 4)
            
            ConnectionStateView()
                .padding(.top, 4)

            Spacer()

                TimeView()
            Spacer()

            if appState.adbConnected {
                RecentAppsGridView()
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.9)),
                        removal: .opacity.combined(with: .scale(scale: 1.1))
                    ))
            }
            


            if appState.device != nil {
                HStack(spacing: 10){
                    GlassButtonView(
                        label: "Send",
                        systemImage: "square.and.arrow.up",
                        iconOnly: true,
                        fixedIconSize: 16,
                        action: {
                            let panel = NSOpenPanel()
                            panel.allowsMultipleSelection = true
                            panel.canChooseDirectories = false
                            panel.canChooseFiles = true
                            
                            if panel.runModal() == .OK {
                                QuickShareManager.shared.transferURLs = panel.urls
                                QuickShareManager.shared.startDiscovery()
                                appState.showingQuickShareTransfer = true
                            }
                        }
                    )
                    .transition(.identity)
                    .keyboardShortcut(
                        "f",
                        modifiers: .command
                     )

                    if appState.device?.ipAddress != "BLE" {
                        GlassButtonView(
                            label: "Browse",
                            systemImage: "folder",
                            iconOnly: true,
                            fixedIconSize: 16,
                            action: {
                                if appState.isPlus && appState.licenseCheck {
                                    appState.openFileBrowser()
                                } else {
                                    showingPlusPopover = true
                                }
                            }
                        )
                        .transition(.identity)
                        .keyboardShortcut(
                            "b",
                            modifiers: .command
                        )
                        .popover(isPresented: $showingPlusPopover, arrowEdge: .bottom) {
                            PlusFeaturePopover(message: "Browse files with AirSync+")
                        }
                    }

                    GlassButtonView(
                        label: "Mute",
                        systemImage: appState.silenceAllNotifications ? "bell.slash.fill" : "bell.badge",
                        iconOnly: true,
                        fixedIconSize: 16,
                        action: {
                            appState.silenceAllNotifications.toggle()
                        }
                    )
                    .transition(.identity)

                    GlassButtonView(
                        label: "Clipboard",
                        systemImage: "clipboard",
                        iconOnly: true,
                        fixedIconSize: 16,
                        action: {
                            sendClipboard()
                        }
                    )
                    .transition(.identity)

                }
            }
            if (appState.status != nil){
                DeviceStatusView()
                    .transition(.scale.combined(with: .opacity))
                    .animation(.interpolatingSpring(stiffness: 200, damping: 30), value: appState.isMusicCardHidden)
            }

        }
        .padding(8)
        .animation(
            .easeInOut(duration: 0.35),
            value: AppState.shared.adbConnected
        )
        .animation(
            .easeInOut(duration: 0.28),
            value: appState.isMusicCardHidden
        )
    }

    private func sendClipboard() {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], let firstUrl = urls.first {
            if appState.device?.ipAddress != "BLE" {
                DispatchQueue.global(qos: .userInitiated).async {
                    WebSocketServer.shared.sendFile(url: firstUrl, isClipboard: true)
                }
            } else {
                print("[ScreenView] Cannot send files over BLE")
            }
        } else if let image = NSImage(pasteboard: pasteboard) {
            if appState.device?.ipAddress != "BLE" {
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
                        print("[ScreenView] Failed to save clipboard image: \(error)")
                    }
                }
            } else {
                print("[ScreenView] Cannot send images over BLE")
            }
        } else if let text = pasteboard.string(forType: .string) {
            appState.sendClipboardToAndroid(text: text)
        }
    }
}

#Preview {
    ScreenView()
}
