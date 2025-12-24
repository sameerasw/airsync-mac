//
//  ConnectionStateView.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2025-12-20.
//

import SwiftUI

struct ConnectionStateView: View {
    @ObservedObject var appState = AppState.shared
    @State private var showResult = false
    @State private var isSuccess = false
    
    var body: some View {
        ZStack {
            if appState.adbConnecting && !showResult {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Connecting ADB...")
                }
                .padding(8)
                .applyGlassViewIfAvailable()
            } else if showResult {
                HStack(spacing: 8) {
                    Image(systemName: isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(isSuccess ? .green : .red)
                    Text(isSuccess ? "ADB ready" : "ADB failed")
                }
                .padding(8)
                .applyGlassViewIfAvailable()
            }
        }
        .frame(height: 40)
        .transition(.scale(scale: 0.8).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.3), value: showResult)
        .onChange(of: appState.adbConnected) { _, newValue in
            if newValue && appState.adbConnecting {
                isSuccess = true
                showResult = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showResult = false
                }
            }
        }
        .onChange(of: appState.adbConnecting) { _, newValue in
            // Only show failure if adbConnecting becomes false and connection failed
            if !newValue && !appState.adbConnected && !showResult {
                isSuccess = false
                showResult = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showResult = false
                }
            }
        }
    }
}
