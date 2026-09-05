//
//  SidebarMirrorView.swift
//  AirSync
//
//  Created by Sameera Wijerathna on 2026-06-04.
//

import SwiftUI
import MetalKit

struct SidebarMirrorView: View {
    @ObservedObject var appState = AppState.shared
    @StateObject private var streamClient = ScrcpyStreamClient.shared
    @State private var isMirroring = false
    @State private var errorMessage: String?

    private var safeRatio: CGFloat {
        if streamClient.videoWidth > 0 && streamClient.videoHeight > 0 {
            return CGFloat(streamClient.videoWidth) / CGFloat(streamClient.videoHeight)
        }
        return 9.0 / 19.5
    }

    var body: some View {
        ZStack {
            if isMirroring {
                MetalVideoView(streamClient: streamClient)
                    .overlay {
                        if streamClient.videoWidth == 0 {
                            ProgressView()
                        }
                    }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    } else {
                        Text("Connecting...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            startMirroring()
        }
        .onDisappear {
            stopMirroring()
        }
    }

    private func startMirroring() {
        errorMessage = nil
        ScrcpyServerManager.shared.startMirroringSession(appState: AppState.shared, streamClient: streamClient) { success, errorMsg in
            if success {
                self.isMirroring = true
            } else {
                self.errorMessage = errorMsg
            }
        }
    }
    
    private func stopMirroring() {
        ScrcpyServerManager.shared.stopMirroringSession(streamClient: streamClient)
        isMirroring = false
    }
}
