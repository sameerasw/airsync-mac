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
        ZStack(alignment: .bottom) {
            ZStack {
                switch AppState.shared.selectedTab {
                case .notifications:
                    NotificationView()
                        .transition(.blurReplace)
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

                case .apps:
                    AppsView()
                        .transition(.blurReplace)

                case .transfers:
                    TransfersView()
                        .transition(.blurReplace)
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

                case .calls:
                    CallsView()
                        .transition(.blurReplace)
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) {
                                Button("Refresh", systemImage: "arrow.clockwise") {
                                    _ = LiveNotificationManager.shared.getCallLogs(forceRefresh: true)
                                }
                                .help("Refresh call logs")
                            }
                        }

                case .messages:
                    MessagesView()
                        .transition(.blurReplace)
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) {
                                Button("Refresh", systemImage: "arrow.clockwise") {
                                    _ = LiveNotificationManager.shared.getSmsThreads(forceRefresh: true)
                                }
                                .help("Refresh messages")
                            }
                        }

                case .health:
                    HealthView()
                        .transition(.blurReplace)
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) {
                                Button("Refresh", systemImage: "arrow.clockwise") {
                                    WebSocketServer.shared.requestHealthSummary()
                                }
                                .help("Refresh health data")
                            }
                        }

                case .settings:
                    SettingsView()
                        .transition(.blurReplace)
                        .toolbar {
                            ToolbarItemGroup {
                                Button("Help", systemImage: "questionmark.circle") {
                                    showHelpSheet = true
                                }
                                .help("Feedback and How to?")
                            }
                        }

                case .qr:
                    ScannerView()
                        .transition(.blurReplace)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: AppState.shared.selectedTab)
            .frame(minWidth: 550)

            DockTabBar()
                .zIndex(1)
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
