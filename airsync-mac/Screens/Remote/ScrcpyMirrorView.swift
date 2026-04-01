//
//  ScrcpyMirrorView.swift
//  AirSync
//
//  Created by Sameera Wijerathna on 2026-04-01.
//

import SwiftUI
import AppKit
import MetalKit

struct ScrcpyMirrorView: View {
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
                // Ensure we don't render Metal in a zero-size view
                if streamClient.videoWidth > 0 {
                    MetalVideoView(streamClient: streamClient)
                        .aspectRatio(safeRatio, contentMode: .fit)
                        .background(WindowAccessor(callback: { window in
                            window.backgroundColor = .clear
                            window.isOpaque = false
                            window.titlebarAppearsTransparent = true
                            window.titleVisibility = .hidden
                            window.isMovableByWindowBackground = false
                            window.level = .floating
                            
                            // Set initial aspect ratio
                            window.contentAspectRatio = NSSize(width: CGFloat(streamClient.videoWidth), height: CGFloat(streamClient.videoHeight))
                        }))
                        .onChange(of: streamClient.videoWidth) { _, _ in updateWindowRatio() }
                        .onChange(of: streamClient.videoHeight) { _, _ in updateWindowRatio() }
                } else {
                    ProgressView("Initializing Stream...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "iphone.radiowaves.left.and.right")
                        .font(.system(size: 64))
                        .foregroundColor(.accentColor)
                    
                    Text("Ready to Mirror")
                        .font(.title)
                        .bold()
                    
                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                    
                    Button(action: startMirroring) {
                        Text("Start Mirroring")
                            .font(.headline)
                            .padding()
                            .frame(minWidth: 200)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                }
            }
        }
        .frame(minWidth: 250, minHeight: 450)
        .onDisappear {
            stopMirroring()
        }
    }
    
    private func updateWindowRatio() {
        guard streamClient.videoWidth > 0 && streamClient.videoHeight > 0 else { return }
        
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "nativeMirror" || $0.contentView?.subviews.contains(where: { $0 is MTKView }) ?? false }) {
            window.contentAspectRatio = NSSize(width: CGFloat(streamClient.videoWidth), height: CGFloat(streamClient.videoHeight))
            
            // Re-evaluate size to ensure it fits the ratio if it was collapsed
            let currentFrame = window.frame
            let targetHeight = currentFrame.width / safeRatio
            window.setContentSize(NSSize(width: currentFrame.width, height: targetHeight))
        }
    }
    
    private func startMirroring() {
        errorMessage = nil
        
        ADBConnector.getWiredDeviceSerial { serial in
            guard let serial = serial else {
                DispatchQueue.main.async {
                    self.errorMessage = "No wired ADB device detected. Please connect your device via USB."
                }
                return
            }
            
            ScrcpyServerManager.shared.startServer(serial: serial) { success in
                guard success else {
                    DispatchQueue.main.async {
                        self.errorMessage = "Failed to start scrcpy server on device."
                    }
                    return
                }
                
                DispatchQueue.main.async {
                    self.streamClient.onPacketReceived = { data, isConfig, isKeyframe, pts in
                        ScrcpyVideoDecoder.shared.decodePacket(data: data, isConfig: isConfig, pts: pts)
                    }
                    self.streamClient.connect()
                    ScrcpyControlClient.shared.connect()
                    self.isMirroring = true
                }
            }
        }
    }
    
    private func stopMirroring() {
        streamClient.disconnect()
        ScrcpyControlClient.shared.disconnect()
        ScrcpyServerManager.shared.stopServer()
        isMirroring = false
    }
}
