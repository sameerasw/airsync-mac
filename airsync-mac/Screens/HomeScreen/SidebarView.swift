//
//  SidebarView.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-07-28.
//

import SwiftUI

struct SidebarView: View {
    @ObservedObject var appState = AppState.shared
    @ObservedObject var discoveryManager = DiscoveryManager.shared
    @State private var isExpandedAllSeas: Bool = false
    @State private var showingPlusDesktopPopover = false

    var body: some View {
        VStack {
            HStack(alignment: .center, spacing: 8) {
                let name = appState.device?.name ?? "AirSync"
                let truncated = name.count > 16
                ? String(name.prefix(16)) + "..."
                : name

                Text(truncated)
                    .font(.title3)

                if let wifiDevice = discoveryManager.availableWifiDeviceForCurrentBLE {
                    GlassButtonView(
                        label: "WiFi",
                        systemImage: "wifi",
                        action: {
                            QuickConnectManager.shared.connect(to: wifiDevice)
                        }
                    )
                }
            }

            if let deviceVersion = appState.device?.version,
               appState.device?.ipAddress != "BLE",
               isVersion(deviceVersion, lessThan: appState.minAndroidVersion) {
                Label("Your Android app is outdated", systemImage: "iphone.badge.exclamationmark")
                    .padding(4)
            }

            PhoneView()
                .transition(.scale)
                .opacity(appState.device != nil ? 1 : 0.5)

            Spacer()

        }
        .animation(.easeInOut(duration: 0.5), value: appState.status != nil)
        .frame(minWidth: 250, minHeight: 400)
        .safeAreaInset(edge: .bottom) {

            if appState.adbConnected {
                HStack(spacing: 12) {
                    Menu {
                        // 1. Default mirror action
                        if appState.useNativeMirroringByDefault {
                            Button("Android Mirror") {
                                appState.isNativeMirroring = true
                            }
                            .keyboardShortcut("p", modifiers: [.command])
                        } else {
                            Button("scrcpy Mirror") {
                                ADBConnector.startScrcpy(
                                    ip: appState.device?.ipAddress ?? "",
                                    port: appState.adbPort,
                                    deviceName: appState.device?.name ?? "My Phone"
                                )
                            }
                            .keyboardShortcut("p", modifiers: [.command])
                        }
                        
                        // 2. Alternative mirror action
                        if appState.useNativeMirroringByDefault {
                            Button("scrcpy Mirror") {
                                ADBConnector.startScrcpy(
                                    ip: appState.device?.ipAddress ?? "",
                                    port: appState.adbPort,
                                    deviceName: appState.device?.name ?? "My Phone"
                                )
                            }
                            .keyboardShortcut("p", modifiers: [.command, .shift])
                        } else {
                            Button("Android Mirror") {
                                appState.isNativeMirroring = true
                            }
                            .keyboardShortcut("p", modifiers: [.command, .shift])
                        }

                        Button(appState.isSidebarMirroring ? "Stop Mirroring Here" : "Mirror Here") {
                            appState.isSidebarMirroring.toggle()
                        }
                        .keyboardShortcut("s", modifiers: [.command, .shift])
                    } label: {
                        if appState.isSidebarMirroring {
                            Label("Close", systemImage: "xmark.circle")
                        } else {
                            Label("Mirror", systemImage: "apps.iphone")
                        }
                    } primaryAction: {
                        if appState.isSidebarMirroring {
                            appState.isSidebarMirroring = false
                        } else {
                            if appState.useNativeMirroringByDefault {
                                appState.isNativeMirroring = true
                            } else {
                                ADBConnector.startScrcpy(
                                    ip: appState.device?.ipAddress ?? "",
                                    port: appState.adbPort,
                                    deviceName: appState.device?.name ?? "My Phone"
                                )
                            }
                        }
                    }
                    .menuStyle(.button)
                    .controlSize(.large)
                    .glassButtonIfAvailable()
                    .transition(.identity)
                    .keyboardShortcut("p", modifiers: [.command])

                    Menu {
                        if appState.useNativeDesktopMirroringByDefault {
                            Button("Native Desktop") {
                                if appState.isPlus && appState.licenseCheck {
                                    appState.isNativeDesktopMirroring = true
                                } else {
                                    showingPlusDesktopPopover = true
                                }
                            }
                            .keyboardShortcut("d", modifiers: [.command])
                            
                            Button("scrcpy Desktop") {
                                if appState.isPlus && appState.licenseCheck {
                                    ADBConnector.startScrcpy(
                                        ip: appState.device?.ipAddress ?? "",
                                        port: appState.adbPort,
                                        deviceName: appState.device?.name ?? "My Phone",
                                        desktop: true
                                    )
                                } else {
                                    showingPlusDesktopPopover = true
                                }
                            }
                            .keyboardShortcut("d", modifiers: [.command, .shift])
                        } else {
                            Button("scrcpy Desktop") {
                                if appState.isPlus && appState.licenseCheck {
                                    ADBConnector.startScrcpy(
                                        ip: appState.device?.ipAddress ?? "",
                                        port: appState.adbPort,
                                        deviceName: appState.device?.name ?? "My Phone",
                                        desktop: true
                                    )
                                } else {
                                    showingPlusDesktopPopover = true
                                }
                            }
                            .keyboardShortcut("d", modifiers: [.command])
                            
                            Button("Native Desktop") {
                                if appState.isPlus && appState.licenseCheck {
                                    appState.isNativeDesktopMirroring = true
                                } else {
                                    showingPlusDesktopPopover = true
                                }
                            }
                            .keyboardShortcut("d", modifiers: [.command, .shift])
                        }
                    } label: {
                        Label("Desktop", systemImage: "desktopcomputer")
                    } primaryAction: {
                        if appState.isPlus && appState.licenseCheck {
                            if appState.useNativeDesktopMirroringByDefault {
                                appState.isNativeDesktopMirroring = true
                            } else {
                                ADBConnector.startScrcpy(
                                    ip: appState.device?.ipAddress ?? "",
                                    port: appState.adbPort,
                                    deviceName: appState.device?.name ?? "My Phone",
                                    desktop: true
                                )
                            }
                        } else {
                            showingPlusDesktopPopover = true
                        }
                    }
                    .menuStyle(.button)
                    .controlSize(.large)
                    .glassButtonIfAvailable()
                    .transition(.identity)
                    .keyboardShortcut("d", modifiers: [.command])
                    .popover(isPresented: $showingPlusDesktopPopover, arrowEdge: .top) {
                        PlusFeaturePopover(message: "Desktop Mode is an AirSync+ feature")
                    }
                    .whatsNewPopover(item: .desktopMode, arrowEdge: .top)

                }
                .padding(.top, 8)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .onAppear {
            WhatsNewTourManager.shared.evaluateActiveItem()
        }
        .onChange(of: appState.adbConnected) { _, _ in
            WhatsNewTourManager.shared.evaluateActiveItem()
        }
        .onChange(of: appState.selectedTab) { _, _ in
            WhatsNewTourManager.shared.evaluateActiveItem()
        }
    }
}

#Preview {
    SidebarView()
}
