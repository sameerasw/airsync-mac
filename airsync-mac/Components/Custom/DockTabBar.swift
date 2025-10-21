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
    private let dockCornerRadius: CGFloat = 18
    private let bottomMargin: CGFloat = 8
    
    @State private var isDropTarget = false
    
    var body: some View {
        HStack(spacing: dockSpacing) {
            // System tabs
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
                .keyboardShortcut(
                    tab.shortcut,
                    modifiers: .command
                )
            }
            
            // Separator if there are pinned apps
            if !appState.pinnedApps.isEmpty && appState.adbConnected && appState.isPlus && appState.device != nil {
                Divider()
                    .frame(height: 32)
            }
            
            // Pinned apps - only show if Plus member, ADB connected, and device connected
            if appState.adbConnected && appState.isPlus && appState.device != nil {
                ForEach(appState.pinnedApps) { pinnedApp in
                    DockPinnedAppItem(pinnedApp: pinnedApp)
                }
            }
            
            // Drop zone for pinning new apps
            if appState.adbConnected && appState.isPlus && appState.device != nil && appState.pinnedApps.count < 3 {
                DropZoneItem(pinnedAppsCount: appState.pinnedApps.count)
            }
        }
        .padding(.horizontal, dockPadding)
        .padding(.vertical, dockPadding)
        .frame(height: dockItemSize + (dockPadding * 2))
        .glassBoxIfAvailable(radius: 25)
        .padding(.horizontal, 20)
        .padding(.bottom, bottomMargin)
    }
}

/// Drop zone to add new pinned apps
private struct DropZoneItem: View {
    @ObservedObject var appState = AppState.shared
    let pinnedAppsCount: Int
    
    private let dockItemSize: CGFloat = 48
    
    @State private var isDropTarget = false
    
    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: dockItemSize, height: dockItemSize)
                .background(
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(style: StrokeStyle(lineWidth: 2, dash: [4]))
                        .foregroundColor(isDropTarget ? .accentColor : .secondary.opacity(0.3))
                )
                .contentShape(Rectangle())
        }
        .help("Drag apps here to pin them (max 3)")
        .onDrop(of: ["com.sameerasw.airsync.app"], isTargeted: $isDropTarget) { providers in
            handleDrop(providers: providers)
            return true
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadDataRepresentation(forTypeIdentifier: "com.sameerasw.airsync.app") { data, _ in
                if let data = data {
                    DispatchQueue.main.async {
                        do {
                            let app = try JSONDecoder().decode(AndroidApp.self, from: data)
                            _ = appState.addPinnedApp(app)
                        } catch {
                            print("[dock] Error decoding app: \(error)")
                        }
                    }
                }
            }
        }
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
            VStack(spacing: 4) {
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
        }
        .buttonStyle(.plain)
        .help(L(tab.rawValue))
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
            Button(action: launchApp) {
                VStack(spacing: 0) {
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
                .frame(width: dockItemSize, height: dockItemSize)
                .background(
                    Group {
                        if isHovering {
                            RoundedRectangle(cornerRadius: 15)
                                .fill(Color.gray.opacity(0.1))
                        }
                    }
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(pinnedApp.appName)
            .scaleEffect(isHovering ? hoverScale : 1.0)
            .onHover { hovering in
                isHovering = hovering
            }
            .animation(.easeInOut(duration: 0.15), value: isHovering)
            .contextMenu {
                Button(role: .destructive) {
                    appState.removePinnedApp(pinnedApp.packageName)
                } label: {
                    Label("Unpin", systemImage: "pin.slash")
                }
            }
            
            // Remove button overlay
            Button(action: {
                appState.removePinnedApp(pinnedApp.packageName)
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                    .background(Color.white.clipShape(Circle()))
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -6)
            .opacity(isHovering ? 1 : 0)
        }
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
