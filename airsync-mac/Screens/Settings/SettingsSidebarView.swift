//
//  SettingsSidebarView.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2026-05-20.
//

import SwiftUI

struct SettingsSidebarView: View {
    @ObservedObject var appState = AppState.shared
    @State private var hoveredTab: SettingsTab? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text("Settings")
                .font(.system(size: 20, weight: .bold))
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .whatsNewPopover(item: .settings, arrowEdge: .trailing)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(SettingsTab.allCases) { tab in
                        categoryRow(for: tab)
                    }
                }
                .padding(.horizontal, 8)
            }

            Spacer()

            HStack {
                Spacer()
                Text("AirSync v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.0")")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .glassBoxIfAvailable(radius: 32)
                Spacer()
            }
            .padding(.bottom, 12)
        }
        .frame(minWidth: 260)
        .onAppear {
            WhatsNewTourManager.shared.evaluateActiveItem()
        }
    }

    @ViewBuilder
    private func categoryRow(for tab: SettingsTab) -> some View {
        let isSelected = appState.selectedSettingsTab == tab
        let isHovered = hoveredTab == tab

        Button {
            appState.selectedSettingsTab = tab
        } label: {
            HStack(spacing: 12) {
                // Circular icon badge
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.accentColor)
                        .frame(width: 26, height: 26)

                    Image(systemName: tab.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(tab.displayName)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .foregroundColor(isSelected ? .primary : .primary.opacity(0.85))

                    if tab == .myMac {
                        Text(DeviceTypeUtil.deviceFullDescription())
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Special trailing indicator icons/pills
                if tab == .mirroring && !appState.isPlus {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                } else if tab == .airsyncPlus {
                    if appState.isPlus {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.accentColor)
                    } else {
                        Text("Get")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .glassBoxIfAvailable(radius: 32)
                            .tint(Color.accentColor)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.35) : (isHovered ? Color.secondary.opacity(0.08) : Color.clear))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            hoveredTab = hovering ? tab : nil
        }
    }
}
