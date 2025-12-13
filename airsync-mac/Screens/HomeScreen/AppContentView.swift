//
//  AppContentView.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-07-28.
//

import SwiftUI

struct AppContentView: View {
    @ObservedObject var appState = AppState.shared
    @State private var showAboutSheet = false
    @State private var showHelpSheet = false
    @AppStorage("notificationStacks") private var notificationStacks = true
    @State private var showDisconnectAlert = false

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            // QR Scanner Tab (only when device is NOT connected)
            if appState.device == nil {
                ScannerView()
                    .tabItem {
                        Image(systemName: "qrcode")
                        //                    Label("Scan", systemImage: "qrcode")
                    }
                    .tag(TabIdentifier.qr)
                    .toolbar {
                        ToolbarItemGroup {
                            Button("Help", systemImage: "questionmark.circle") {
                                showHelpSheet = true
                            }
                            .help("Feedback and How to?")

                            Button("Refresh", systemImage: "repeat") {
                                WebSocketServer.shared.stop()
                                WebSocketServer.shared.start()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    appState.shouldRefreshQR = true
                                }
                            }
                            .help("Refresh server")
                        }
                    }
            }

            // Notifications Tab (only when device connected)
            if appState.device != nil {
                NotificationView()
                    .tabItem {
                        Image(systemName: "bell.badge")
                        //                        Label("Notifications", systemImage: "bell.badge")
                    }
                    .tag(TabIdentifier.notifications)
                    .toolbar {
                        if appState.notifications.count > 0 || appState.callEvents.count > 0 {
                            ToolbarItem(placement: .primaryAction) {
                                Button {
                                    notificationStacks.toggle()
                                } label: {
                                    Label("Toggle Notification Stacks", systemImage: notificationStacks ? "mail" : "mail.stack")
                                }
                                .help(notificationStacks ? "Switch to stacked view" : "Switch to expanded view")
                            }
                            ToolbarItem(placement: .primaryAction) {
                                Button {
                                    appState.clearNotifications()
                                } label: {
                                    Label("Clear", systemImage: "wind")
                                }
                                .help("Clear all notifications")
                                .keyboardShortcut(.delete, modifiers: .command)
                                .badge(appState.notifications.count + appState.callEvents.count)
                            }
                        }
                    }

                // Apps Tab
                AppsView()
                    .tabItem {
                        Image(systemName: "app")
                        //                        Label("Apps", systemImage: "app")
                    }
                    .tag(TabIdentifier.apps)

                // Transfers Tab
                TransfersView()
                    .tabItem {
                        Image(systemName: "tray.and.arrow.up")
                        //                        Label("Transfers", systemImage: "tray.and.arrow.up")
                    }
                    .tag(TabIdentifier.transfers)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                AppState.shared.removeCompletedTransfers()
                            } label: {
                                Label("Clear completed", systemImage: "trash")
                            }
                            .help("Remove all completed transfers from the list")
                            .keyboardShortcut(.delete, modifiers: .command)
                        }
                    }
            }

            // Settings Tab
            SettingsView()
                .tabItem {
                    //                    Label("Settings", systemImage: "gear")
                    Image(systemName: "gear")
                }
                .tag(TabIdentifier.settings)
                .toolbar {
                    ToolbarItemGroup {
                        Button("Help", systemImage: "questionmark.circle") {
                            showHelpSheet = true
                        }
                        .help("Feedback and How to?")

                        Button {
                            showAboutSheet = true
                        } label: {
                            Label("About", systemImage: "info")
                        }
                        .help("View app information and version details")
                    }

                    if appState.device != nil {
                        ToolbarItemGroup {
                            Button {
                                showDisconnectAlert = true
                            } label: {
                                Label("Disconnect", systemImage: "iphone.slash")
                            }
                            .help("Disconnect Device")
                        }
                    }
                }
        }
        .tabViewStyle(.automatic)
        .frame(minWidth: 550)
        .onAppear {
            // Ensure the correct tab is selected when the view appears
            if appState.device == nil {
                AppState.shared.selectedTab = .qr
            } else {
                AppState.shared.selectedTab = .notifications
            }
        }
        .sheet(isPresented: $showAboutSheet) {
            AboutView(onClose: { showAboutSheet = false })
        }
        .sheet(isPresented: $showHelpSheet) {
            HelpWebSheet(isPresented: $showHelpSheet)
        }
        .alert(isPresented: $showDisconnectAlert) {
            Alert(
                title: Text("Disconnect Device"),
                message: Text("Are you sure you want to disconnect from \(appState.device?.name ?? "this device")?"),
                primaryButton: .destructive(Text("Disconnect")) {
                    appState.disconnectDevice()
                },
                secondaryButton: .cancel()
            )
        }
    }
}

#Preview {
    AppContentView()
}
