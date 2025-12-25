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

    private let dockPadding: CGFloat = 12
    private let dockSpacing: CGFloat = 8
    private let bottomMargin: CGFloat = 8

    var dockItemSize: CGFloat {
        appState.dockSize
    }

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
        .animation(.easeInOut(duration: 0.3), value: showPinnedSection)
        .animation(.easeInOut(duration: 0.2), value: appState.dockSize)
    }
}

/// Individual dock item representing a system tab
private struct DockTabItem: View {
    let tab: TabIdentifier
    let isSelected: Bool
    let action: () -> Void
    let dockItemSize: CGFloat

    private let selectedScale: CGFloat = 1.15
    private let hoverScale: CGFloat = 1.05

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: tab.icon)
                .font(.system(size: dockItemSize * 0.4, weight: .semibold))
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .frame(width: dockItemSize, height: dockItemSize)
                .background(
                    Group {
                        if isSelected {
                            RoundedRectangle(cornerRadius: dockItemSize * 0.3)
                                .fill(Color.accentColor.opacity(0.15))
                        } else if isHovering {
                            RoundedRectangle(cornerRadius: dockItemSize * 0.3)
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
    let dockItemSize: CGFloat
    @ObservedObject var appState = AppState.shared

    private let hoverScale: CGFloat = 1.05

    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: launchApp, label: {
                PinnedAppIconView(pinnedApp: pinnedApp, dockItemSize: dockItemSize)
            })
            .frame(width: dockItemSize, height: dockItemSize)
            .background(
                Group {
                    if isHovering {
                        RoundedRectangle(cornerRadius: dockItemSize * 0.3)
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
        // Guard against multiple mirror requests
        guard !appState.isMirrorRequestPending && !appState.isMirroring else {
            print("[dock] Mirror request already pending or active, ignoring")
            return
        }
        
        guard let device = appState.device else { return }
        
        // If ADB is enabled AND connected AND tools are present -> use scrcpy
        let adbEnabled = appState.adbEnabled && appState.adbConnected
        let hasADB = ADBConnector.findExecutable(named: "adb", fallbackPaths: ADBConnector.possibleADBPaths) != nil
        let hasScrcpy = ADBConnector.findExecutable(named: "scrcpy", fallbackPaths: ADBConnector.possibleScrcpyPaths) != nil
        
        if adbEnabled && hasADB && hasScrcpy {
            // Use scrcpy when ADB is connected
            ADBConnector.startScrcpy(
                ip: device.ipAddress,
                port: appState.adbPort,
                deviceName: device.name,
                package: pinnedApp.packageName
            )
        } else {
            // Use WebSocket mirroring for app-specific mirroring with auto-approve
            WebSocketServer.shared.sendMirrorRequest(
                action: "start",
                mode: "app",
                package: pinnedApp.packageName,
                options: [
                    "transport": "websocket",
                    "fps": appState.mirrorFPS,
                    "quality": appState.mirrorQuality,
                    "maxWidth": appState.mirrorMaxWidth,
                    "autoApprove": true
                ]
            )
            print("[dock] Requested WebSocket app mirroring for: \(pinnedApp.packageName)")
        }
    }
}

// MARK: - Pinned App Icon View
private struct PinnedAppIconView: View {
    let pinnedApp: PinnedApp
    let dockItemSize: CGFloat

    var body: some View {
        let iconSize = dockItemSize * 0.85
        
        if let iconPath = pinnedApp.iconUrl,
           let image = Image(filePath: iconPath) {
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: iconSize, height: iconSize)
                .cornerRadius(dockItemSize * 0.2)
        } else {
            Image(systemName: "app.badge")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: iconSize, height: iconSize)
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
                },
                dockItemSize: appState.dockSize
            )
            .transition(.asymmetric(
                insertion: .scale(scale: 0.5).combined(with: .opacity),
                removal: .scale(scale: 0.5).combined(with: .opacity)
            ))
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
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.5).combined(with: .opacity),
                    removal: .scale(scale: 0.5).combined(with: .opacity)
                ))
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
                DockPinnedAppItem(pinnedApp: pinnedApp, dockItemSize: appState.dockSize)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.5).combined(with: .opacity),
                        removal: .scale(scale: 0.5).combined(with: .opacity)
                    ))
            }
        }
    }
}
