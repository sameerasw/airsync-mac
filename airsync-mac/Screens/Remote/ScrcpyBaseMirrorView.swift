//
//  ScrcpyBaseMirrorView.swift
//  AirSync
//
//  Created by Sameera Wijerathna on 2026-06-04.
//

import SwiftUI
import AppKit
import MetalKit

struct ScrcpyBaseMirrorView: View {
    let desktopMode: Bool
    let windowId: String
    let defaultTitle: String
    let defaultIconName: String
    let defaultRatio: CGFloat
    let isDesktopResizeEnabled: Bool

    @Environment(\.dismissWindow) var dismissWindow
    @EnvironmentObject var appState: AppState
    @StateObject private var streamClient = ScrcpyStreamClient.shared
    @State private var isMirroring = false
    @State private var errorMessage: String?
    @State private var isHovering = false
    @State private var currentWindow: NSWindow?
    @State private var isWindowActive = false
    @State private var navbarController = NavbarWindowController()
    @State private var sideController = SideControlWindowController()
    @AppStorage("showMirrorControls") private var showMirrorControls = true

    private var safeRatio: CGFloat {
        if streamClient.videoWidth > 0 && streamClient.videoHeight > 0 {
            return CGFloat(streamClient.videoWidth) / CGFloat(streamClient.videoHeight)
        }
        return defaultRatio
    }

    private var contentCornerRadius: CGFloat {
        isHovering ? 24 : 0
    }

    private var isStreaming: Bool {
        isMirroring && streamClient.videoWidth > 0
    }

    @ViewBuilder
    private var metalView: some View {
        MetalVideoView(streamClient: streamClient)
            .aspectRatio(safeRatio, contentMode: .fit)
            .cornerRadius(contentCornerRadius)
            .padding(.top, isHovering ? 8 : 0)
            .padding(.horizontal, isHovering ? 8 : 0)
            .padding(.bottom, isHovering ? 20 : 0)
            .opacity(isStreaming ? 1 : 0)
            .blur(radius: isStreaming ? 0 : 20)
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isStreaming)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isHovering)
            .overlay {
                if !isStreaming {
                    connectingView(message: "Loading")
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
    }

    @ViewBuilder
    private var connectionStatusView: some View {
        connectingView(message: errorMessage ?? "Connecting")
            .cornerRadius(contentCornerRadius)
            .transition(.opacity)
    }

    @ViewBuilder
    private var mainMirrorContent: some View {
        ZStack(alignment: .top) {
            if isMirroring {
                metalView
            } else {
                connectionStatusView
            }
        }
    }

    @ViewBuilder
    private var controlsHintView: some View {
        if isHovering {
            Text("⌘B to toggle controls")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(.primary.opacity(0.4))
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            wallpaperView
                .opacity(isStreaming ? 0 : 0.4)
                .animation(.easeInOut(duration: 0.8), value: isStreaming)
                .ignoresSafeArea()

            Button(action: {
                showMirrorControls.toggle()
            }) {
                Text("")
            }
            .buttonStyle(.plain)
            .keyboardShortcut("b", modifiers: [.command])
            .frame(width: 0, height: 0)
            .opacity(0)

            VStack(spacing: 0) {
                if isHovering {
                    headerView
                        .frame(height: 36)
                        .clipped()
                        .transition(.opacity)
                        .onHover { hovering in
                            if !hovering {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    isHovering = false
                                    updateWindowUI(isHovering: false)
                                }
                            }
                        }
                }

                mainMirrorContent
                    .animation(.easeInOut(duration: 1.25), value: isMirroring)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .top) {
                        if !isHovering {
                            Color.clear
                                .frame(height: 6)
                                .contentShape(Rectangle())
                                .onHover { hovering in
                                    if hovering {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            isHovering = true
                                            updateWindowUI(isHovering: true)
                                        }
                                    }
                                }
                        }
                    }

                controlsHintView
            }
            .background(WindowAccessor(callback: { window in
                self.setupWindow(window)
            }))
            .ignoresSafeArea()
            .onAppear {
                let isActive = desktopMode ? AppState.shared.isNativeDesktopMirroring : AppState.shared.isNativeMirroring
                if !isActive {
                    dismissWindow(id: windowId)
                    return
                }
                startMirroring()
            }
        }
        .background(.ultraThinMaterial.opacity(isMirroring ? 0.01 : 1.0))
        .onChange(of: isHovering) { _, newValue in
            updateWindowUI(isHovering: newValue)
        }
        .onChange(of: isMirroring) { _, newValue in
            if !newValue { isHovering = false }
            updateNavbarVisibility()
        }
        .onChange(of: isWindowActive) { _, _ in
            updateNavbarVisibility()
        }
        .onChange(of: showMirrorControls) { _, _ in
            updateNavbarVisibility()
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
        .frame(minWidth: isDesktopResizeEnabled ? 400 : 200, minHeight: isDesktopResizeEnabled ? 250 : 300)
        .ignoresSafeArea()
        .onDisappear {
            navbarController.hide()
            sideController.hide()
            stopMirroring()
        }
    }

    private var wallpaperView: some View {
        Group {
            if let wallpaperBase64 = appState.currentDeviceWallpaperBase64,
               let data = Data(base64Encoded: wallpaperBase64),
               let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 15)
            } else {
                Color.clear
            }
        }
    }

    private var headerView: some View {
        ZStack {
            if #available(macOS 15.0, *) {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(WindowDragGesture())
            }

            HStack {
                Spacer()

                Text(isMirroring ? streamClient.deviceName : defaultTitle)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.primary.opacity(0.7))

                Spacer()
            }
        }
        .frame(height: 36)
        .background(Color.clear)
    }

    private func connectingView(message: String) -> some View {
        VStack(spacing: 24) {
            VStack {
                Image(systemName: defaultIconName)
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

    private func setupWindow(_ window: NSWindow) {
        self.currentWindow = window
        window.backgroundColor = NSColor.clear
        window.isOpaque = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = NSWindow.TitleVisibility.hidden
        window.isMovableByWindowBackground = false
        window.isRestorable = false
        window.level = .floating

        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isMovable = false

        window.title = isMirroring ? streamClient.deviceName : defaultTitle

        if !isDesktopResizeEnabled && isMirroring && streamClient.videoWidth > 0 {
            window.contentAspectRatio = NSSize(width: CGFloat(streamClient.videoWidth), height: CGFloat(streamClient.videoHeight))
        }

        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            if desktopMode {
                AppState.shared.isNativeDesktopMirroring = false
            } else {
                AppState.shared.isNativeMirroring = false
            }
            self.stopMirroring()
        }

        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { _ in
            navbarController.updatePosition(parent: window)
            sideController.updatePosition(parent: window)
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { _ in
            navbarController.updatePosition(parent: window)
            sideController.updatePosition(parent: window)
            
            if isDesktopResizeEnabled, let contentView = window.contentView {
                let backingSize = contentView.convertToBacking(contentView.bounds).size
                let width = UInt16(backingSize.width)
                let height = UInt16(backingSize.height)
                ScrcpyControlClient.shared.sendResizeDisplay(width: width, height: height)
            }
        }

        self.isWindowActive = window.isKeyWindow
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { _ in
            self.isWindowActive = true
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { _ in
            self.isWindowActive = false
        }
    }

    private func updateWindowUI(isHovering: Bool) {
        guard let window = currentWindow else { return }
        window.isMovable = isHovering

        window.standardWindowButton(.closeButton)?.isHidden = !isHovering
        window.standardWindowButton(.miniaturizeButton)?.isHidden = !isHovering
        window.standardWindowButton(.zoomButton)?.isHidden = true
    }

    private func updateWindowConstraints(width: UInt32, height: UInt32) {
        guard !isDesktopResizeEnabled else { return }
        guard width > 0 && height > 0 else { return }
        currentWindow?.contentAspectRatio = NSSize(width: CGFloat(width), height: CGFloat(height))
    }

    private func startMirroring() {
        errorMessage = nil
        ScrcpyServerManager.shared.startMirroringSession(appState: AppState.shared, streamClient: streamClient, desktopMode: desktopMode) { success, errorMsg in
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

    private func updateNavbarVisibility() {
        guard let window = currentWindow else { return }
        if isWindowActive && isMirroring && showMirrorControls {
            navbarController.show(parent: window, isMirroring: isMirroring)
            sideController.show(parent: window, isMirroring: isMirroring)
        } else {
            navbarController.hide()
            sideController.hide()
        }
    }
}
