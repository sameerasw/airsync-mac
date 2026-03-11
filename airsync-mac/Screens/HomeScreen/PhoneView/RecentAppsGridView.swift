//
//  RecentAppsGridView.swift
//  AirSync
//
//  Created by Sameera Wijerathna on 2026-03-11.
//

import SwiftUI

struct RecentAppsGridView: View {
    @ObservedObject var appState = AppState.shared
    
    var body: some View {
        HStack(spacing: 2) {

            Spacer()
            
            ForEach(0..<min(5, appState.recentApps.count), id: \.self) { index in
                RecentAppIconView(app: appState.recentApps[index])
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

private struct RecentAppIconView: View {
    let app: AndroidApp
    @ObservedObject var appState = AppState.shared
    @State private var isHovered = false
    
    var body: some View {
        Button {
            appState.trackAppUse(app) // Move to front
            ADBConnector.startScrcpy(
                ip: appState.device?.ipAddress ?? "",
                port: appState.adbPort,
                deviceName: appState.device?.name ?? "My Phone",
                package: app.packageName
            )
        } label: {
            ZStack {
                if let iconPath = app.iconUrl, let image = Image(filePath: iconPath) {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 36, height: 36)
                        .cornerRadius(10)
                } else {
                    Image(systemName: "app.badge")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .frame(width: 36, height: 36)
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovered)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}


#Preview {
    RecentAppsGridView()
        .background(Color.blue.opacity(0.3))
}
