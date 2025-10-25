//
//  SidebarView.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-07-28.
//

import SwiftUI
import Cocoa


struct SidebarView: View {

    @ObservedObject var appState = AppState.shared
    @State private var isExpandedAllSeas: Bool = false
    @State private var showDisconnectAlert = false

    var body: some View {
        VStack{

            HStack(alignment: .center) {
                let name = appState.device?.name ?? "AirSync"
                let truncated = name.count > 20
                ? String(name.prefix(20)) + "..."
                : name

                Text(truncated)
                    .font(.title3)
            }
            .padding(8)



            if let deviceVersion = appState.device?.version,
               isVersion(deviceVersion, lessThan: appState.minAndroidVersion) {
                Label("Your Android app is outdated", systemImage: "iphone.badge.exclamationmark")
                    .padding(4)
            }


            PhoneView()
                .transition(.scale)
                .opacity(appState.device != nil ? 1 : 0.5)


            .animation(.easeInOut(duration: 0.5), value: appState.status != nil)
            .frame(minWidth: 280, minHeight: 400)
            .safeAreaInset(edge: .bottom) {
                HStack{
                    if appState.device != nil {
                        // Start Mirroring button next to Disconnect
                        GlassButtonView(
                            label: "Start Mirroring",
                            systemImage: "rectangle.on.rectangle",
                            primary: true,
                            action: {
                                guard let device = appState.device else { return }

                                // If ADB is enabled AND connected AND tools are present -> use scrcpy
                                let adbEnabled = appState.adbEnabled && appState.adbConnected
                                let hasADB = ADBConnector.findExecutable(named: "adb", fallbackPaths: ADBConnector.possibleADBPaths) != nil
                                let hasScrcpy = ADBConnector.findExecutable(named: "scrcpy", fallbackPaths: ADBConnector.possibleScrcpyPaths) != nil

                                if adbEnabled && hasADB && hasScrcpy {
                                    ADBConnector.startScrcpy(
                                        ip: device.ipAddress,
                                        port: appState.adbPort,
                                        deviceName: device.name
                                    )
                                } else {
                                    // Default: open built-in TCP Remote Viewer (no ADB dependency)
                                    let viewer = RemoteViewerWindowController(host: device.ipAddress, port: UInt16(device.port))
                                    viewer.showWindow(nil)
                                    viewer.window?.makeKeyAndOrderFront(nil)
                                }
                            }
                        )
                        .transition(.identity)

                        GlassButtonView(
                            label: "Disconnect",
                            systemImage: "xmark",
                            action: {
                                showDisconnectAlert = true
                            }
                        )
                        .transition(.identity)
                    } else {
                        Label("Connect your device", systemImage: "arrow.2.circlepath.circle")
                    }
                }
                .padding(16)
            }
        }
        .alert(isPresented: $showDisconnectAlert) {
            Alert(
                title: Text("Disconnect Device"),
                message: Text("Do you want to disconnect \"\(appState.device?.name ?? "device")\"?"),
                primaryButton: .destructive(Text("Disconnect")) {
                    appState.disconnectDevice()
                    ADBConnector.disconnectADB()
                    appState.adbConnected = false
                },
                secondaryButton: .cancel()
            )
        }
    }
}

#Preview {
    SidebarView()
}

