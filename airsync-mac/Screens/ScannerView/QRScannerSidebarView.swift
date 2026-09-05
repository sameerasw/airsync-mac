//
//  QRScannerSidebarView.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2026-05-19.
//

import SwiftUI
import QRCode
import LocalAuthentication

struct QRScannerSidebarView: View {
    @ObservedObject var appState = AppState.shared
    @ObservedObject var qrManager = QRConnectionManager.shared
    
    private func statusInfo(for status: WebSocketStatus) -> (text: String, icon: String, color: Color) {
        switch status {
        case .stopped:
            return ("Stopped", "xmark.circle", .gray)
        case .starting:
            return ("Starting...", "clock", .orange)
        case .started:
            return ("Ready", "checkmark.circle", .green)
        case .failed(let error):
            return ("Failed: \(error)", "exclamationmark.triangle", .red)
        }
    }
    
    @State private var showingSettingsPopover = false
    
    var body: some View {
        let info = statusInfo(for: appState.webSocketStatus)
        
        VStack(spacing: 16) {

                Text("Scan to connect")
                    .font(.title3)
                    .fontWeight(.bold)
                    .whatsNewPopover(item: .scanQR, arrowEdge: .trailing)
            .padding(.horizontal, 16)
            .padding(.top, 16)

            Spacer()

            
            if !qrManager.hasValidIP {
                VStack {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 30))
                        .foregroundColor(.gray)
                        .padding()
                    
                    Text("No local IP found")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .padding()
                .glassBoxIfAvailable(radius: 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if !qrManager.isUnlocked {
                    // Locked UI: 1:1 card with glass background
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.accentColor)
                        Text("Click to Reveal")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .frame(width: 240, height: 240)
                    .glassBoxIfAvailable(radius: 24)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        qrManager.authenticateUser()
                    }
                } else {
                    // Unlocked
                    if let qrImage = qrManager.qrImage {
                        VStack(spacing: 12) {
                            Image(decorative: qrImage, scale: 1.0)
                                .resizable()
                                .interpolation(.none)
                                .frame(width: 180, height: 180)
                                .accessibilityLabel("QR Code")
                                .shadow(radius: 20)
                                .padding()
                                .background(.black.opacity(0.6), in: .rect(cornerRadius: 30))
                            
                            if let key = WebSocketServer.shared.getSymmetricKeyBase64(), !key.isEmpty {
                                VStack(spacing: 8) {
                                    HStack {
                                        GlassButtonView(
                                            label: "Copy Key",
                                            systemImage: "key",
                                            action: {
                                                qrManager.copyToClipboard(key)
                                            }
                                        )
                                        
                                        GlassButtonView(
                                            label: "Re-generate key",
                                            systemImage: "repeat.badge.xmark",
                                            iconOnly: true,
                                            action: {
                                                qrManager.showConfirmReset = true
                                            }
                                        )
                                    }
                                    .confirmationDialog(
                                        "Are you sure you want to reset the key? You will have to re-auth all the devices.",
                                        isPresented: $qrManager.showConfirmReset
                                    ) {
                                        Button("Reset key", role: .destructive) {
                                            WebSocketServer.shared.resetSymmetricKey()
                                            qrManager.generateQRAsync()
                                        }
                                        Button("Cancel", role: .cancel) { }
                                    }
                                    
                                    if let status = qrManager.copyStatus {
                                        Text(status)
                                            .font(.caption)
                                            .foregroundColor(.green)
                                            .transition(.opacity)
                                    }
                                }
                            }
                        }
                        .frame(width: 240)
                    } else {
                        ProgressView("Generating QR…")
                            .frame(width: 240, height: 240)
                    }
                }
            }

            Spacer()

            HStack {
                GlassButtonView(
                    label: info.text,
                    systemImage: info.icon,
                    action: {}
                )
                .foregroundStyle(info.color)
                .focusable(false)


                GlassButtonView(
                    label: "",
                    systemImage: "gearshape",
                    iconOnly: true,
                    action: {showingSettingsPopover.toggle()}
                )
                .popover(isPresented: $showingSettingsPopover, arrowEdge: .top) {
                    ConnectionPillPopover()
                }
                .focusable(false)
            }
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 8)
        .onAppear {
            qrManager.generateQRAsync()
            WhatsNewTourManager.shared.evaluateActiveItem()
        }
        .onDisappear {
            qrManager.cleanUpTimer()
        }
    }
}
