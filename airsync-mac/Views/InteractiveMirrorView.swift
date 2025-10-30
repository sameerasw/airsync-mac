//
//  InteractiveMirrorView.swift
//  airsync-mac
//
//  Interactive mirror view with remote control capabilities
//

import SwiftUI
import AppKit

#if canImport(SwiftUI)
struct InteractiveMirrorView: View {
    @ObservedObject private var appState = AppState.shared
    @State private var screenSize: CGSize = .zero
    @State private var showControls: Bool = true
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image = appState.latestMirrorFrame {
                    InteractiveImageView(
                        image: image,
                        screenSize: $screenSize,
                        onTap: handleTap,
                        onDrag: handleDrag,
                        onScroll: handleScroll
                    )
                    .background(Color.black)
                    .onChange(of: appState.latestMirrorFrame) { _, _ in
                        // Record frame for performance monitoring
                        PerformanceMonitor.shared.recordFrame()
                    }
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Waiting for mirror frames…")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
                
                // Performance overlay (top-right)
                MirrorPerformanceOverlay()
                
                // Navigation controls overlay (bottom)
                if showControls {
                    VStack {
                        Spacer()
                        HStack(spacing: 20) {
                            Button(action: { WebSocketServer.shared.sendNavAction("back") }) {
                                Image(systemName: "chevron.left")
                                    .font(.title2)
                            }
                            .help("Back (Delete)")
                            
                            Button(action: { WebSocketServer.shared.sendNavAction("home") }) {
                                Image(systemName: "house")
                                    .font(.title2)
                            }
                            .help("Home (Escape)")
                            
                            Button(action: { WebSocketServer.shared.sendNavAction("recents") }) {
                                Image(systemName: "square.stack")
                                    .font(.title2)
                            }
                            .help("Recent Apps")
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .padding(.bottom, 20)
                    }
                }
            }
            .frame(minWidth: 320, minHeight: 600)
            .onAppear {
                screenSize = geometry.size
                PerformanceMonitor.shared.reset()
            }
            .onChange(of: geometry.size) { _, newSize in
                screenSize = newSize
            }
        }
        .onHover { hovering in
            showControls = hovering
        }
        // Keyboard shortcuts
        .onAppear {
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                self.handleKeyPress(event)
            }
        }
    }
    
    private func handleKeyPress(_ event: NSEvent) -> NSEvent? {
        switch event.keyCode {
        case 51: // Delete/Backspace
            WebSocketServer.shared.sendNavAction("back")
        case 53: // Escape
            WebSocketServer.shared.sendNavAction("home")
        default:
            break
        }
        return event
    }
    
    private func handleTap(at point: CGPoint, in imageSize: CGSize) {
        // Convert Mac coordinates to Android pixel coordinates
        // Get actual Android screen size from latest frame if available
        let androidWidth: CGFloat
        let androidHeight: CGFloat
        
        if let image = appState.latestMirrorFrame {
            // Use actual image dimensions for accurate mapping
            androidWidth = image.size.width
            androidHeight = image.size.height
        } else {
            // Fallback to common Android resolution
            androidWidth = 1080
            androidHeight = 2400
        }
        
        let scaleX = androidWidth / imageSize.width
        let scaleY = androidHeight / imageSize.height
        
        let androidX = Int(point.x * scaleX)
        let androidY = Int(point.y * scaleY)
        
        WebSocketServer.shared.sendInputTap(x: androidX, y: androidY)
    }
    
    private func handleDrag(from start: CGPoint, to end: CGPoint, in imageSize: CGSize) {
        // Get actual Android screen size from latest frame if available
        let androidWidth: CGFloat
        let androidHeight: CGFloat
        
        if let image = appState.latestMirrorFrame {
            androidWidth = image.size.width
            androidHeight = image.size.height
        } else {
            androidWidth = 1080
            androidHeight = 2400
        }
        
        let scaleX = androidWidth / imageSize.width
        let scaleY = androidHeight / imageSize.height
        
        let x1 = Int(start.x * scaleX)
        let y1 = Int(start.y * scaleY)
        let x2 = Int(end.x * scaleX)
        let y2 = Int(end.y * scaleY)
        
        // Calculate duration based on distance for more natural feel
        let distance = hypot(end.x - start.x, end.y - start.y)
        let duration = max(100, min(300, Int(distance * 0.5))) // 100-300ms based on distance
        
        WebSocketServer.shared.sendInputSwipe(x1: x1, y1: y1, x2: x2, y2: y2, durationMs: duration)
    }
    
    private func handleScroll(delta: CGFloat, at point: CGPoint, in imageSize: CGSize) {
        // Scroll is typically implemented as a swipe gesture
        let androidWidth: CGFloat
        let androidHeight: CGFloat
        
        if let image = appState.latestMirrorFrame {
            androidWidth = image.size.width
            androidHeight = image.size.height
        } else {
            androidWidth = 1080
            androidHeight = 2400
        }
        
        let scaleX = androidWidth / imageSize.width
        let scaleY = androidHeight / imageSize.height
        
        let x = Int(point.x * scaleX)
        let y = Int(point.y * scaleY)
        
        // Convert scroll delta to swipe distance (negative delta = scroll up = swipe down)
        // Increased sensitivity for smoother scrolling
        let swipeDistance = Int(-delta * 5)
        let y2 = max(0, min(Int(androidHeight), y + swipeDistance))
        
        WebSocketServer.shared.sendInputSwipe(x1: x, y1: y, x2: x, y2: y2, durationMs: 50)
    }
}

// SwiftUI-based interactive image view
struct InteractiveImageView: View {
    let image: NSImage
    @Binding var screenSize: CGSize
    let onTap: (CGPoint, CGSize) -> Void
    let onDrag: (CGPoint, CGPoint, CGSize) -> Void
    let onScroll: (CGFloat, CGPoint, CGSize) -> Void
    
    @State private var dragStart: CGPoint?
    @GestureState private var dragLocation: CGPoint?
    
    var body: some View {
        GeometryReader { geometry in
            Image(nsImage: image)
                .resizable()
                .scaledToFit() // This is what makes it work correctly!
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if dragStart == nil {
                                dragStart = value.startLocation
                            }
                        }
                        .onEnded { value in
                            let start = dragStart ?? value.startLocation
                            let end = value.location
                            let distance = hypot(end.x - start.x, end.y - start.y)
                            
                            // Calculate image rect
                            let imageSize = image.size
                            let viewSize = geometry.size
                            let imageRect = calculateImageRect(imageSize: imageSize, viewSize: viewSize)
                            
                            if distance < 5 {
                                // It's a tap
                                let relativePoint = CGPoint(
                                    x: end.x - imageRect.origin.x,
                                    y: end.y - imageRect.origin.y
                                )
                                onTap(relativePoint, imageRect.size)
                            } else {
                                // It's a swipe
                                let relativeStart = CGPoint(
                                    x: start.x - imageRect.origin.x,
                                    y: start.y - imageRect.origin.y
                                )
                                let relativeEnd = CGPoint(
                                    x: end.x - imageRect.origin.x,
                                    y: end.y - imageRect.origin.y
                                )
                                onDrag(relativeStart, relativeEnd, imageRect.size)
                            }
                            
                            dragStart = nil
                        }
                )
                .onAppear {
                    // Enable scroll events
                    NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                        let location = NSEvent.mouseLocation
                        // Convert to view coordinates
                        if let window = NSApp.keyWindow {
                            let windowPoint = window.convertPoint(fromScreen: location)
                            let imageSize = image.size
                            let viewSize = geometry.size
                            let imageRect = calculateImageRect(imageSize: imageSize, viewSize: viewSize)
                            
                            let relativePoint = CGPoint(
                                x: windowPoint.x - imageRect.origin.x,
                                y: windowPoint.y - imageRect.origin.y
                            )
                            onScroll(event.scrollingDeltaY, relativePoint, imageRect.size)
                        }
                        return event
                    }
                }
        }
    }
    
    private func calculateImageRect(imageSize: CGSize, viewSize: CGSize) -> CGRect {
        let imageAspect = imageSize.width / imageSize.height
        let viewAspect = viewSize.width / viewSize.height
        
        var rect = CGRect.zero
        
        if imageAspect > viewAspect {
            // Image is wider - fit to width
            let height = viewSize.width / imageAspect
            rect = CGRect(
                x: 0,
                y: (viewSize.height - height) / 2,
                width: viewSize.width,
                height: height
            )
        } else {
            // Image is taller - fit to height
            let width = viewSize.height * imageAspect
            rect = CGRect(
                x: (viewSize.width - width) / 2,
                y: 0,
                width: width,
                height: viewSize.height
            )
        }
        
        return rect
    }
}
#endif
