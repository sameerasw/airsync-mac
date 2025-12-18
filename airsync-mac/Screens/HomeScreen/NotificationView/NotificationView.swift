//
//  NotificationView.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2025-08-07.
//

import SwiftUI

struct NotificationView: View {
    @ObservedObject var appState = AppState.shared
    @AppStorage("notificationStacks") private var notificationStacks = true
    @State private var expandedPackages: Set<String> = []

    @ViewBuilder
    var body: some View {
        if !appState.notifications.isEmpty {
            ZStack {
                // stacked view on top when notificationStacks == true
                stackedList
                    .opacity(notificationStacks ? 1 : 0)
                    .allowsHitTesting(notificationStacks)     // only interact when visible
                    .accessibilityHidden(!notificationStacks)
                    .animation(.easeInOut(duration: 0.5), value: notificationStacks)

                // flat view on top when notificationStacks == false
                flatList
                    .opacity(notificationStacks ? 0 : 1)
                    .allowsHitTesting(!notificationStacks)
                    .accessibilityHidden(notificationStacks)
                    .animation(.easeInOut(duration: 0.5), value: notificationStacks)
            }
        } else {
            NotificationEmptyView()
        }
    }


    // MARK: - Flat List
    private var flatList: some View {
        List(appState.notifications.prefix(20), id: \.id) { notif in
            notificationRow(for: notif)
                .onTapGesture {
                    if appState.device != nil && appState.adbConnected &&
                        notif.package != "" &&
                        notif.package != "com.sameerasw.airsync" &&
                        appState.mirroringPlus {
                        ADBConnector.startScrcpy(
                            ip: appState.device?.ipAddress ?? "",
                            port: appState.adbPort,
                            deviceName: appState.device?.name ?? "My Phone",
                            package: notif.package
                        )
                    }
                }
        }
        .scrollContentBackground(.hidden)
        .background(.clear)
        .transition(.blurReplace)
        .listStyle(.sidebar)
    }

    // MARK: - Stacked List
    private var stackedList: some View {
        List {
            ForEach(groupedNotifications.keys.sorted(), id: \.self) { package in
                let packageNotifs = groupedNotifications[package] ?? []
                let isExpanded = expandedPackages.contains(package)

                Section {
                    let visibleNotifs: [Notification] = {
                        if isExpanded {
                            return packageNotifs
                        } else {
                            return packageNotifs.first.map { [$0] } ?? []
                        }
                    }()

                    ForEach(visibleNotifs) { notif in
                        notificationRow(for: notif)
                            .onTapGesture {
                                if appState.device != nil && appState.adbConnected &&
                                    notif.package != "" &&
                                    notif.package != "com.sameerasw.airsync" &&
                                    appState.mirroringPlus {
                                    ADBConnector.startScrcpy(
                                        ip: appState.device?.ipAddress ?? "",
                                        port: appState.adbPort,
                                        deviceName: appState.device?.name ?? "My Phone",
                                        package: notif.package
                                    )
                                }
                            }
                    }

                    if packageNotifs.count > 1 {
                        Button {
                            withAnimation(.spring) {
                                if isExpanded {
                                    expandedPackages.remove(package)
                                } else {
                                    expandedPackages.insert(package)
                                }
                            }
                        } label: {
                            Label(
                                isExpanded ? "Show Less" : "Show \(packageNotifs.count - 1) More",
                                systemImage: isExpanded ? "chevron.up" : "chevron.down"
                            )
                            .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                } header: {
                    Text(appState.androidApps[package]?.name ?? "AirSync")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(.clear)
        .transition(.blurReplace)
        .listStyle(.sidebar)
    }

    // MARK: - Helpers
    private var groupedNotifications: [String: [Notification]] {
        Dictionary(grouping: appState.notifications.prefix(20)) { notif in
            notif.package
        }
    }

    @ViewBuilder
    private func notificationRow(for notif: Notification) -> some View {
        NotificationCardView(
            notification: notif,
            deleteNotification: { appState.removeNotification(notif) },
            hideNotification: { appState.hideNotification(notif) }
        )
        .applyGlassViewIfAvailable()
    }
}

#Preview {
    NotificationView()
}
