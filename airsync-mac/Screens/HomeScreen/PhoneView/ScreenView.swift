//
//  ScreenView.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2025-09-20.
//

import SwiftUI

struct ScreenView: View {
    @ObservedObject var appState = AppState.shared
    var body: some View {
        VStack{
            ConnectionStateView()
                .padding(.top, 12)

            Spacer()

            TimeView()
                .transition(.opacity.combined(with: .scale))

            Spacer()

            if appState.device != nil {

                HStack(spacing: 10){
                    GlassButtonView(
                        label: "Send",
                        systemImage: "square.and.arrow.up",
                        iconOnly: appState.adbConnected,
                        action: {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = true
                            panel.canChooseDirectories = false
                            panel.allowsMultipleSelection = false
                            panel.begin { response in
                                if response == .OK, let url = panel.url {
                                    DispatchQueue.global(qos: .userInitiated).async {
                                        WebSocketServer.shared.sendFile(url: url)
                                    }
                                }
                            }
                        }
                    )
                    .transition(.identity)
                    .keyboardShortcut(
                        "f",
                        modifiers: .command
                    )


                    if appState.adbConnected{
                        GlassButtonView(
                            label: "Mirror",
                            systemImage: "apps.iphone",
                            action: {
                                ADBConnector
                                    .startScrcpy(
                                        ip: appState.device?.ipAddress ?? "",
                                        port: appState.adbPort,
                                        deviceName: appState.device?.name ?? "My Phone"
                                    )
                            }
                        )
                        .transition(.identity)
                        .keyboardShortcut(
                            "p",
                            modifiers: .command
                        )
                        .contextMenu {
                            Button("Desktop Mode") {
                                ADBConnector.startScrcpy(
                                    ip: appState.device?.ipAddress ?? "",
                                    port: appState.adbPort,
                                    deviceName: appState.device?.name ?? "My Phone",
                                    desktop: true
                                )
                            }
                        }
                        .keyboardShortcut(
                            "p",
                            modifiers: [.command, .shift]
                        )
                    }
                }
            }
            if (appState.status != nil){
                DeviceStatusView()
                    .transition(.scale.combined(with: .opacity))
                    .animation(.interpolatingSpring(stiffness: 200, damping: 30), value: appState.isMusicCardHidden)
            }

        }
        .padding(8)
        .animation(
            .easeInOut(duration: 0.35),
            value: AppState.shared.adbConnected
        )
        .animation(
            .easeInOut(duration: 0.28),
            value: appState.isMusicCardHidden
        )
    }
}

#Preview {
    ScreenView()
}
