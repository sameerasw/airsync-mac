//
//  ADBPairingSheetView.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2026-05-27.
//

import SwiftUI
import QRCode
internal import SwiftImageReadWrite

struct ADBPairingSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var pairingManager = ADBPairingManager.shared
    
    @State private var qrImage: CGImage?
    @State private var isHowToPairExpanded = false
    @State private var isTroubleshootingExpanded = false
    
    var body: some View {
        ZStack {
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
            
            VStack {
                ScrollView {
                    VStack(spacing: 20) {
                        Spacer()
                        
                        Text("Pair New ADB Device")
                            .font(.title2)
                            .bold()
                        
                        if let qrImage = qrImage {
                            VStack(spacing: 12) {
                                Image(decorative: qrImage, scale: 1.0)
                                    .resizable()
                                    .interpolation(.none)
                                    .frame(width: 200, height: 200)
                                    .accessibilityLabel("ADB pairing QR Code")
                                    .shadow(radius: 10)
                                    .padding()
                                    .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 30))
                                
                                Text(pairingManager.status)
                                    .font(.body)
                                    .foregroundStyle(isErrorStatus ? Color.red : .secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 16)
                            }
                        } else {
                            ProgressView("Generating QR Code…")
                                .frame(width: 200, height: 200)
                        }
                        
                        HStack(spacing: 24) {
                            // "How to pair?" Button
                            Button(action: {
                                isHowToPairExpanded.toggle()
                                if isHowToPairExpanded {
                                    isTroubleshootingExpanded = false
                                }
                            }) {
                                HStack {
                                    Text(L("settings.pairing.howToPair"))
                                    Image(systemName: isHowToPairExpanded ? "chevron.up" : "chevron.down")
                                }
                            }
                            .buttonStyle(.link)
                            
                            // "Troubleshooting" Button
                            Button(action: {
                                isTroubleshootingExpanded.toggle()
                                if isTroubleshootingExpanded {
                                    isHowToPairExpanded = false
                                }
                            }) {
                                HStack {
                                    Text(L("settings.pairing.troubleshooting"))
                                    Image(systemName: isTroubleshootingExpanded ? "chevron.up" : "chevron.down")
                                }
                            }
                            .buttonStyle(.link)
                        }
                        
                        if isHowToPairExpanded {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(L("settings.pairing.instructions"))
                                    .font(.body)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: false)
                                
                                HStack(spacing: 16) {
                                    Spacer()
                                    Image("adb-pair")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxWidth: 240, maxHeight: 180)
                                        .cornerRadius(12)
                                        .shadow(radius: 4)
                                    
                                    Image("adb-pair-prompt")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxWidth: 240, maxHeight: 180)
                                        .cornerRadius(12)
                                        .shadow(radius: 4)
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                            }
                            .padding()
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        if isTroubleshootingExpanded {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(L("settings.pairing.troubleshooting.text"))
                                    .font(.body)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: false)
                            }
                            .padding()
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        Spacer()
                    }
                    .padding()
                }
                
                Divider()
                
                HStack {
                    Spacer()
                    
                    GlassButtonView(
                        label: "Close",
                        systemImage: "xmark.circle",
                        action: {
                            pairingManager.stopPairing()
                            dismiss()
                        }
                    )
                    .keyboardShortcut(.cancelAction)
                }
                .padding([.horizontal, .bottom])
            }
        }
        .frame(width: 600, height: 500)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(radius: 20)
        .onAppear {
            pairingManager.startPairing()
            generateQRAsync()
        }
        .onChange(of: pairingManager.pairingString) { _, _ in
            generateQRAsync()
        }
        .onChange(of: pairingManager.status) { _, newStatus in
            if newStatus == "Device successfully connected!" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    pairingManager.stopPairing()
                    dismiss()
                }
            }
        }
    }
    
    private var isErrorStatus: Bool {
        let status = pairingManager.status.lowercased()
        return status.contains("failed") || status.contains("error")
    }
    
    private func generateQRAsync() {
        guard !pairingManager.pairingString.isEmpty else { return }
        Task {
            if let cgImage = await QRCodeGenerator.generateQRCode(for: pairingManager.pairingString) {
                DispatchQueue.main.async {
                    self.qrImage = cgImage
                }
            }
        }
    }
}
