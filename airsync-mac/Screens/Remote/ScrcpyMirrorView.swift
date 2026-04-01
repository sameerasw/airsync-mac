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
    @State private var isHovering = false
    @State private var currentWindow: NSWindow?
    
    private var safeRatio: CGFloat {
        if streamClient.videoWidth > 0 && streamClient.videoHeight > 0 {
            return CGFloat(streamClient.videoWidth) / CGFloat(streamClient.videoHeight)
        }
        return 9.0 / 19.5
    }
    
    private var contentCornerRadius: CGFloat {
        isHovering ? 24 : 0
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                // Expanding Header
                headerView
                    .frame(height: isHovering ? 36 : 0)
                    .opacity(isHovering ? 1 : 0)
                    .clipped()
                
                ZStack(alignment: .top) {
                    if isMirroring {
                        if streamClient.videoWidth > 0 {
                            MetalVideoView(streamClient: streamClient)
                                .aspectRatio(safeRatio, contentMode: .fit)
                                .cornerRadius(contentCornerRadius)
                                .padding(isHovering ? 8 : 0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isHovering)
                        } else {
                            connectingView(message: "Loading")
                        }
                    } else {
                        connectingView(message: errorMessage ?? "Connecting")
                            .cornerRadius(contentCornerRadius)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(WindowAccessor(callback: { window in
                self.currentWindow = window
                window.backgroundColor = NSColor.clear
                window.isOpaque = false
                window.titlebarAppearsTransparent = true
                window.titleVisibility = NSWindow.TitleVisibility.hidden
                window.isMovableByWindowBackground = false
                window.level = .floating
                
                // Hide native traffic lights
                window.standardWindowButton(.closeButton)?.isHidden = true
                window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                window.standardWindowButton(.zoomButton)?.isHidden = true
                
                window.title = isMirroring ? streamClient.deviceName : "AirSync Mirror"
                
                if isMirroring && streamClient.videoWidth > 0 {
                    window.contentAspectRatio = NSSize(width: CGFloat(streamClient.videoWidth), height: CGFloat(streamClient.videoHeight))
                }

                // Handle manual window closure
                NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
                    AppState.shared.isNativeMirroring = false
                    self.stopMirroring()
                }
            }))
            .ignoresSafeArea()
            .onAppear {
                startMirroring()
            }
            
            // Selective Hover Trigger Area (Top Edge)
            Color.clear
                .frame(height: isHovering ? 36 : 6)
                .contentShape(Rectangle())
                .onHover { hovering in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isHovering = hovering
                        updateWindowMovableState(isHovering: hovering)
                    }
                }
                .ignoresSafeArea()
        }
        .background(.ultraThinMaterial.opacity(isMirroring ? 0.01 : 1.0))
        .onChange(of: isHovering) { _, newValue in
            updateWindowMovableState(isHovering: newValue)
        }
        .onChange(of: isMirroring) { _, newValue in
            if !newValue { isHovering = false }
        }
        .onChange(of: streamClient.videoWidth) { _, newValue in
            updateWindowConstraints(width: newValue, height: streamClient.videoHeight)
        }
        .onChange(of: streamClient.videoHeight) { _, newValue in
            updateWindowConstraints(width: streamClient.videoWidth, height: newValue)
        }
        .onChange(of: streamClient.deviceName) { _, newValue in
            currentWindow?.title = newValue
        }
        .frame(minWidth: 200, minHeight: 300)
        .onDisappear {
            stopMirroring()
        }
    }
    
    private var headerView: some View {
        ZStack {
            // Drag Area (Lower Layer)
            if #available(macOS 15.0, *) {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(WindowDragGesture()) 
            }
            
            // Content (Upper Layer for Hit-Testing)
            HStack {
                HStack(spacing: 8) {
                    Button(action: { currentWindow?.close() }) {
                        Circle()
                            .fill(Color.red.opacity(0.8))
                            .frame(width: 12, height: 12)
                            .overlay(Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundColor(.black.opacity(0.5)))
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { currentWindow?.miniaturize(nil) }) {
                        Circle()
                            .fill(Color.yellow.opacity(0.8))
                            .frame(width: 12, height: 12)
                            .overlay(Rectangle().fill(Color.black.opacity(0.5)).frame(width: 8, height: 1))
                    }
                    .buttonStyle(.plain)
                    
                    Circle()
                        .fill(Color.green.opacity(0.8))
                        .frame(width: 12, height: 12)
                }
                .padding(.leading, 12)
                
                Spacer()
                
                Text(isMirroring ? streamClient.deviceName : "AirSync")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.primary.opacity(0.7))
                
                Spacer()
                
                Color.clear.frame(width: 52, height: 1)
            }
        }
        .frame(height: 36)
        .background(Color.clear)
    }
    
    private func connectingView(message: String) -> some View {
        VStack(spacing: 24) {
            VStack {
                Image(systemName: "iphone")
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor)
                
                ProgressView()
            }
            
            Text(message)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(.primary.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            if errorMessage != nil {
                Button(action: startMirroring) {
                    Text("Retry Connection")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func updateWindowMovableState(isHovering: Bool) {
        currentWindow?.isMovable = isHovering
    }
    
    private func updateWindowConstraints(width: UInt32, height: UInt32) {
        guard width > 0 && height > 0 else { return }
        currentWindow?.contentAspectRatio = NSSize(width: CGFloat(width), height: CGFloat(height))
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
