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
    
    var body: some View {
        HStack(spacing: dockSpacing) {
            ForEach(TabIdentifier.availableTabs) { tab in
                DockItem(
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
        }
        .padding(.horizontal, dockPadding)
        .padding(.vertical, dockPadding)
        .frame(height: dockItemSize + (dockPadding * 2))
        .glassBoxIfAvailable(radius: 25)
        .padding(.horizontal, 20)
        .padding(.bottom, bottomMargin)
    }
}

/// Individual dock item representing a tab
private struct DockItem: View {
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

/// Visual effect view for macOS-style background
private struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

#Preview {
    DockTabBar()
        .background(Color(.controlBackgroundColor))
}
