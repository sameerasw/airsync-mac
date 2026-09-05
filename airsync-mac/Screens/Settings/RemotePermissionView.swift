//
//  RemotePermissionView.swift
//  airsync-mac
//
//  Created by AirSync on 2026-01-10.
//

import SwiftUI
import Combine

struct RemotePermissionView: View {
    @Environment(\.dismiss) var dismiss
    @State private var isTrusted: Bool = false
    @State private var timer: AnyCancellable?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "keyboard.badge.eye")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
                .padding(.bottom, 10)
            
            Text("Remote control permission")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("To allow AirSync to simulate keystrokes (arrows, media keys) and control volume, you need to grant Accessibility permissions in System Settings.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)

            GlassButtonView(
                label:  !isTrusted ? "Open System Settings" : "You're all set!",
                systemImage: "accessibility",
                primary: true,
            ){
                if isTrusted {
                    dismiss()
                } else {
                    MacRemoteManager.shared.requestAccessibilityPermission()
                }
            }
        }
        .padding(30)
        .frame(width: 450)
        .onAppear {
            checkPermission()
            timer = Timer.publish(every: 2, on: .main, in: .default)
                .autoconnect()
                .sink { _ in checkPermission() }
        }
        .onDisappear {
            timer?.cancel()
            timer = nil
        }
    }
    
    private func checkPermission() {
        isTrusted = MacRemoteManager.shared.isAccessibilityTrusted()
    }
}

#Preview {
    RemotePermissionView()
}
