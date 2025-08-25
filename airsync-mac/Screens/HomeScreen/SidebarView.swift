//
//  SidebarView.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-07-28.
//

import SwiftUI


struct SidebarView: View {

    @ObservedObject var appState = AppState.shared
    @State private var isExpandedAllSeas: Bool = false

    var body: some View {
        VStack{

            if let deviceVersion = appState.device?.version,
               isVersion(deviceVersion, lessThan: appState.minAndroidVersion) {
                Label("Your Android app is outdated", systemImage: "iphone.badge.exclamationmark")
                    .padding(4)
            }


            PhoneView()
                .transition(.scale)


            .animation(.easeInOut(duration: 0.5), value: appState.status != nil)
            .frame(minWidth: 230, minHeight: 380)
            .safeAreaInset(edge: .bottom) {
                HStack{
                    GlassButtonView(
                        label: NSLocalizedString("Disconnect", comment: ""),
                        systemImage: "xmark",
                        action: {
                            appState.disconnectDevice()
                            ADBConnector.disconnectADB()
                            appState.adbConnected = false
                        }
                    )
                    .transition(.identity)
                }
                .padding()
            }
        }
    }
}

#Preview {
    SidebarView()
}
