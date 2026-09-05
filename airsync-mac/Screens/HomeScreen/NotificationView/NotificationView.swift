//
//  NotificationView.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2025-08-07.
//

import SwiftUI
import FoundationModels

struct NotificationView: View {
    @ObservedObject var appState = AppState.shared
    @AppStorage("notificationStacks") private var notificationStacks = true
    @ObservedObject private var summaryViewModel = NotificationSummaryViewModel.shared
    @State private var expandedPackages: Set<String> = []
    @State private var isSilentExpanded: Bool = false

    @ViewBuilder
    var body: some View {
        if !appState.notifications.isEmpty {
            VStack(spacing: 0) {
                if !appState.disableAllAIFeatures && summaryViewModel.showSummary {
                    NotificationSummaryView(viewModel: summaryViewModel)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                }

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
            }
            .whatsNewPopover(item: .firstNotification, arrowEdge: .top)
            .toolbar {
                let hasValidNotifications = appState.includeSilentInAIOption ? !appState.notifications.isEmpty : appState.notifications.contains(where: { $0.priority != "silent" })
                if !appState.disableAllAIFeatures && appState.showAIToolbarButton && hasValidNotifications {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            summaryViewModel.generateSummary(notifications: appState.notifications, androidApps: appState.androidApps, isFromToolbar: true)
                        } label: {
                            Label("Summarize", systemImage: "sparkles")
                        }
                        .disabled(summaryViewModel.isGeneratingSummary)
                        .help("Summarize notifications with AI")
                    }
                }
            }
            .onAppear {
                WhatsNewTourManager.shared.evaluateActiveItem()
            }
            .onChange(of: appState.disableAllAIFeatures) { _, disabled in
                if disabled {
                    summaryViewModel.showSummary = false
                }
            }
            .onChange(of: appState.notifications.count) { _, _ in
                WhatsNewTourManager.shared.evaluateActiveItem()
            }
            .onChange(of: appState.selectedTab) { _, _ in
                WhatsNewTourManager.shared.evaluateActiveItem()
            }
            .sheet(item: Binding(
                get: { appState.configuringLaunchPreferenceFor.map { NotifConfigureTarget(id: $0) } },
                set: { appState.configuringLaunchPreferenceFor = $0?.id }
            )) { target in
                if let app = appState.androidApps[target.id] {
                    AppNotificationSettingsView(app: app)
                }
            }
        } else {
            NotificationEmptyView()
        }
    }


    // MARK: - Flat List
    private var flatList: some View {
        List {
            let alertingNotifs = appState.notifications.prefix(20).filter { $0.priority != "silent" }
            let silentNotifs = appState.notifications.prefix(20).filter { $0.priority == "silent" }

            // Alerting Notifications
            ForEach(alertingNotifs) { notif in
                notificationRowWithTap(for: notif)
            }

            // Silent Notifications (Mimics App Stack)
            if !silentNotifs.isEmpty {
                Section {
                    let visibleSilentNotifs: [Notification] = {
                        if isSilentExpanded {
                            return Array(silentNotifs)
                        } else {
                            return silentNotifs.first.map { [$0] } ?? []
                        }
                    }()
                    
                    ForEach(visibleSilentNotifs) { notif in
                        notificationRowWithTap(for: notif)
                    }
                    
                    if silentNotifs.count > 1 {
                        Button {
                            withAnimation(.spring) {
                                isSilentExpanded.toggle()
                            }
                        } label: {
                            Label(
                                isSilentExpanded ? "Show Less" : "Show \(silentNotifs.count - 1) More",
                                systemImage: isSilentExpanded ? "chevron.up" : "chevron.down"
                            )
                            .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                } header: {
                    HStack {
                        Image(systemName: "bell.slash.fill")
                            .font(.caption)
                        Text("Silent Notifications")
                    }
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                    .padding(4)
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
                        notificationRowWithTap(for: notif)
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

    @ViewBuilder
    private func notificationRowWithTap(for notif: Notification) -> some View {
        notificationRow(for: notif)
            .onTapGesture {
                appState.handleNotificationTap(notif)
            }
    }
}

private struct NotifConfigureTarget: Identifiable {
    let id: String
}

#Preview {
    NotificationView()
}
