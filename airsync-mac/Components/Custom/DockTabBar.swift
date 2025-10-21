//
//  DockTabBar.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-10-22.
//

import SwiftUI

/// A macOS floating dock-style tab switcher that appears at the bottom of the window
struct DockTabBar: View {
    @ObservedObject var appState = AppState.shared

    private let dockItemSize: CGFloat = 48
    private let dockPadding: CGFloat = 12
    private let dockSpacing: CGFloat = 8
    private let bottomMargin: CGFloat = 8

    var showPinnedSection: Bool {
        appState.adbConnected && appState.isPlus && appState.device != nil
    }

    var body: some View {
        HStack(spacing: dockSpacing) {
            DockTabsSection()
            DockSeparatorSection(showPinnedSection: showPinnedSection)
            DockPinnedAppsSection(showPinnedSection: showPinnedSection)
        }
        .padding(.horizontal, dockPadding)
        .padding(.vertical, dockPadding)
        .frame(height: dockItemSize + (dockPadding * 2))
        .glassBoxIfAvailable(radius: 25)
        .padding(.horizontal, 20)
        .padding(.bottom, bottomMargin)
        .animation(.easeInOut(duration: 0.3), value: appState.pinnedApps.count)
    }
}

/// Individual dock item representing a system tab
private struct DockTabItem: View {
    let tab: TabIdentifier
    let isSelected: Bool
    let action: () -> Void

    private let dockItemSize: CGFloat = 48
    private let selectedScale: CGFloat = 1.15
    private let hoverScale: CGFloat = 1.05

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: tab.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .frame(width: dockItemSize, height: dockItemSize)
                .background(
                    Group {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 15)
                                .fill(Color.accentColor.opacity(0.15))
                        } else if isHovering {
                            RoundedRectangle(cornerRadius: 15)
                                .fill(Color.gray.opacity(0.1))
                        }
                    }
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(LocalizedStringKey(tab.rawValue))
        .scaleEffect(isSelected ? selectedScale : (isHovering ? hoverScale : 1.0))
        .onHover { hovering in
            isHovering = hovering
        }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
    }
}

/// Individual dock item representing a pinned app
private struct DockPinnedAppItem: View {
    let pinnedApp: PinnedApp
    @ObservedObject var appState = AppState.shared

    private let dockItemSize: CGFloat = 48
    private let hoverScale: CGFloat = 1.05

    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: launchApp, label: {
                PinnedAppIconView(pinnedApp: pinnedApp)
            })
            .frame(width: dockItemSize, height: dockItemSize)
            .background(
                Group {
                    if isHovering {
                        RoundedRectangle(cornerRadius: 15)
                            .fill(Color.gray.opacity(0.1))
                    }
                }
            )
            .buttonStyle(.plain)
            .help(pinnedApp.appName)
            .scaleEffect(isHovering ? hoverScale : 1.0)
            .onHover { hovering in
                isHovering = hovering
            }
            .animation(.easeInOut(duration: 0.15), value: isHovering)
            .contextMenu {
                Button(role: .destructive) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        appState.removePinnedApp(pinnedApp.packageName)
                    }
                } label: {
                    Label("Unpin", systemImage: "pin.slash")
                }
            }
        }
        .transition(.asymmetric(
            insertion: .scale(scale: 0.5).combined(with: .opacity),
            removal: .scale(scale: 0.5).combined(with: .opacity)
        ))
    }

    private func launchApp() {
        if let device = appState.device, appState.adbConnected {
            ADBConnector.startScrcpy(
                ip: device.ipAddress,
                port: appState.adbPort,
                deviceName: device.name,
                package: pinnedApp.packageName
            )
        }
    }
}

// MARK: - Pinned App Icon View
private struct PinnedAppIconView: View {
    let pinnedApp: PinnedApp

    var body: some View {
        if let iconPath = pinnedApp.iconUrl,
           let image = Image(filePath: iconPath) {
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
                .cornerRadius(8)
        } else {
            Image(systemName: "app.badge")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
                .foregroundColor(.gray)
        }
    }
}

// MARK: - Dock Tabs Section
private struct DockTabsSection: View {
    @ObservedObject var appState = AppState.shared
    private let dockSpacing: CGFloat = 8

    var body: some View {
        ForEach(TabIdentifier.availableTabs) { tab in
            DockTabItem(
                tab: tab,
                isSelected: appState.selectedTab == tab,
                action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appState.selectedTab = tab
                    }
                }
            )
        }
    }
}

// MARK: - Dock Separator Section
private struct DockSeparatorSection: View {
    @ObservedObject var appState = AppState.shared
    let showPinnedSection: Bool

    var body: some View {
        if showPinnedSection && !appState.pinnedApps.isEmpty {
            Divider()
                .frame(height: 32)
                .transition(.opacity)
        }
    }
}

// MARK: - Dock Pinned Apps Section
private struct DockPinnedAppsSection: View {
    @ObservedObject var appState = AppState.shared
    let showPinnedSection: Bool

    var body: some View {
        if showPinnedSection {
            ForEach(appState.pinnedApps) { pinnedApp in
                DockPinnedAppItem(pinnedApp: pinnedApp)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.5).combined(with: .opacity),
                        removal: .scale(scale: 0.5).combined(with: .opacity)
                    ))
            }
        }
    }
}
