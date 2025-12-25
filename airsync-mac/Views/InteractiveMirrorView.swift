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
    @State private var dimAndroidScreen: Bool = false
    @State private var keyboardMonitor: Any? = nil
    @State private var localKeyboardMonitor: Any? = nil
    
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
                        
                        VStack(spacing: 12) {
                            // Navigation buttons
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
                setupKeyboardMonitor()
            }
            .onDisappear {
                removeKeyboardMonitor()
            }
            .onChange(of: geometry.size) { _, newSize in
                screenSize = newSize
            }
        }
        .onHover { hovering in
            showControls = hovering
        }
        // SwiftUI native key handling for arrow keys (SwiftUI intercepts these for focus navigation)
        .onKeyPress(.leftArrow) {
            WebSocketServer.shared.sendKeyEvent(keyCode: 21, text: "") // KEYCODE_DPAD_LEFT
            print("[mirror] ⌨️ SwiftUI LEFT ARROW")
            return .handled
        }
        .onKeyPress(.rightArrow) {
            WebSocketServer.shared.sendKeyEvent(keyCode: 22, text: "") // KEYCODE_DPAD_RIGHT
            print("[mirror] ⌨️ SwiftUI RIGHT ARROW")
            return .handled
        }
        .onKeyPress(.upArrow) {
            WebSocketServer.shared.sendKeyEvent(keyCode: 19, text: "") // KEYCODE_DPAD_UP
            print("[mirror] ⌨️ SwiftUI UP ARROW")
            return .handled
        }
        .onKeyPress(.downArrow) {
            WebSocketServer.shared.sendKeyEvent(keyCode: 20, text: "") // KEYCODE_DPAD_DOWN
            print("[mirror] ⌨️ SwiftUI DOWN ARROW")
            return .handled
        }
        // Keyboard shortcuts and text input
        .focusable()
        .onAppear {
            // Make window accept keyboard events
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.keyWindow?.makeFirstResponder(NSApp.keyWindow?.contentView)
                NSApp.keyWindow?.makeKey()
            }
        }
    }
    
    private func setupKeyboardMonitor() {
        // Remove existing monitor if any
        removeKeyboardMonitor()
        
        // Use GLOBAL event monitor to catch all keyboard events including arrow keys
        // Local monitors don't receive arrow keys as they're consumed by system navigation
        keyboardMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { event in
            // Only handle if mirror window is focused
            guard NSApp.keyWindow?.identifier?.rawValue == "mirror-window" || 
                  NSApp.keyWindow?.title.contains("Mirror") == true else {
                return
            }
            
            // Only handle if mirror view is active
            guard self.appState.latestMirrorFrame != nil else { 
                print("[mirror] ⌨️ Key ignored - no mirror frame active")
                return  
            }
            
            print("[mirror] ⌨️ Global KeyDown: keyCode=\(event.keyCode), chars='\(event.characters ?? "nil")'")
            _ = self.handleKeyPress(event)
        }
        
        // Also add local monitor for keys when window is active
        localKeyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            guard self.appState.latestMirrorFrame != nil else { return event }
            
            print("[mirror] ⌨️ Local KeyDown: keyCode=\(event.keyCode)")
            return self.handleKeyPress(event)
        }
        
        print("[mirror] ⌨️ Keyboard monitors installed (global + local)")
    }
    
    private func removeKeyboardMonitor() {
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
            keyboardMonitor = nil
        }
        if let monitor = localKeyboardMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyboardMonitor = nil
        }
        print("[mirror] ⌨️ Keyboard monitors removed")
    }
    
    private func handleKeyPress(_ event: NSEvent) -> NSEvent? {
        // Check for modifier keys (Cmd, Ctrl, Alt)
        let hasCommand = event.modifierFlags.contains(.command)
        let hasControl = event.modifierFlags.contains(.control)
        let hasOption = event.modifierFlags.contains(.option)
        
        // Handle common keyboard shortcuts - send to Android
        if hasCommand {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c": // Cmd+C -> Copy (KEYCODE_C with META_CTRL)
                print("[mirror] ⌨️ Sending Cmd+C (Copy) to Android")
                WebSocketServer.shared.sendKeyEventWithMeta(keyCode: 31, metaState: 0x1000) // KEYCODE_C + META_CTRL_ON
                return nil
            case "v": // Cmd+V -> Paste
                print("[mirror] ⌨️ Sending Cmd+V (Paste) to Android")
                WebSocketServer.shared.sendKeyEventWithMeta(keyCode: 50, metaState: 0x1000) // KEYCODE_V + META_CTRL_ON
                return nil
            case "x": // Cmd+X -> Cut
                print("[mirror] ⌨️ Sending Cmd+X (Cut) to Android")
                WebSocketServer.shared.sendKeyEventWithMeta(keyCode: 52, metaState: 0x1000) // KEYCODE_X + META_CTRL_ON
                return nil
            case "a": // Cmd+A -> Select All
                print("[mirror] ⌨️ Sending Cmd+A (Select All) to Android")
                WebSocketServer.shared.sendKeyEventWithMeta(keyCode: 29, metaState: 0x1000) // KEYCODE_A + META_CTRL_ON
                return nil
            case "z": // Cmd+Z -> Undo
                print("[mirror] ⌨️ Sending Cmd+Z (Undo) to Android")
                WebSocketServer.shared.sendKeyEventWithMeta(keyCode: 54, metaState: 0x1000) // KEYCODE_Z + META_CTRL_ON
                return nil
            default:
                // Let other Cmd shortcuts pass through to macOS
                return event
            }
        }
        
        // Pass through Ctrl/Option shortcuts to macOS (window management, etc.)
        if hasControl || hasOption {
            return event
        }
        
        print("[mirror] ⌨️ Key pressed: keyCode=\(event.keyCode), chars='\(event.characters ?? "")'")
        
        // Handle special keys - always consume (return nil) to prevent system beep
        switch event.keyCode {
        case 51: // Delete/Backspace
            WebSocketServer.shared.sendKeyEvent(keyCode: 67, text: "") // KEYCODE_DEL
            print("[mirror] ⌨️ Sent BACKSPACE")
            return nil
        case 53: // Escape - send BACK
            WebSocketServer.shared.sendNavAction("back")
            print("[mirror] ⌨️ Sent BACK (Escape)")
            return nil
        case 36: // Return/Enter
            WebSocketServer.shared.sendKeyEvent(keyCode: 66, text: "\n") // KEYCODE_ENTER
            print("[mirror] ⌨️ Sent ENTER")
            return nil
        case 48: // Tab
            WebSocketServer.shared.sendKeyEvent(keyCode: 61, text: "\t") // KEYCODE_TAB
            print("[mirror] ⌨️ Sent TAB")
            return nil
        case 49: // Space
            WebSocketServer.shared.sendKeyEvent(keyCode: 62, text: " ") // KEYCODE_SPACE
            print("[mirror] ⌨️ Sent SPACE")
            return nil
        case 123: // Left arrow
            WebSocketServer.shared.sendKeyEvent(keyCode: 21, text: "") // KEYCODE_DPAD_LEFT
            print("[mirror] ⌨️ Sent LEFT ARROW")
            return nil
        case 124: // Right arrow
            WebSocketServer.shared.sendKeyEvent(keyCode: 22, text: "") // KEYCODE_DPAD_RIGHT
            print("[mirror] ⌨️ Sent RIGHT ARROW")
            return nil
        case 125: // Down arrow
            WebSocketServer.shared.sendKeyEvent(keyCode: 20, text: "") // KEYCODE_DPAD_DOWN
            print("[mirror] ⌨️ Sent DOWN ARROW")
            return nil
        case 126: // Up arrow
            WebSocketServer.shared.sendKeyEvent(keyCode: 19, text: "") // KEYCODE_DPAD_UP
            print("[mirror] ⌨️ Sent UP ARROW")
            return nil
        case 117: // Forward Delete
            WebSocketServer.shared.sendKeyEvent(keyCode: 112, text: "") // KEYCODE_FORWARD_DEL
            print("[mirror] ⌨️ Sent FORWARD DELETE")
            return nil
        case 115: // Home
            WebSocketServer.shared.sendKeyEvent(keyCode: 122, text: "") // KEYCODE_MOVE_HOME
            print("[mirror] ⌨️ Sent HOME")
            return nil
        case 119: // End
            WebSocketServer.shared.sendKeyEvent(keyCode: 123, text: "") // KEYCODE_MOVE_END
            print("[mirror] ⌨️ Sent END")
            return nil
        case 116: // Page Up
            WebSocketServer.shared.sendKeyEvent(keyCode: 92, text: "") // KEYCODE_PAGE_UP
            print("[mirror] ⌨️ Sent PAGE UP")
            return nil
        case 121: // Page Down
            WebSocketServer.shared.sendKeyEvent(keyCode: 93, text: "") // KEYCODE_PAGE_DOWN
            print("[mirror] ⌨️ Sent PAGE DOWN")
            return nil
        default:
            // Filter out function keys (F1-F12 are keyCodes 122-135)
            if event.keyCode >= 122 && event.keyCode <= 135 {
                print("[mirror] ⌨️ Ignoring function key: F\(event.keyCode - 121)")
                return event // Let system handle function keys
            }
            
            // Handle regular text input - only printable ASCII characters
            if let characters = event.characters, !characters.isEmpty {
                // Filter out non-printable characters and control characters
                let printableChars = characters.filter { char in
                    let scalar = char.unicodeScalars.first?.value ?? 0
                    // Only allow printable ASCII (32-126) and some extended chars
                    return (scalar >= 32 && scalar <= 126) || scalar >= 160
                }
                
                if !printableChars.isEmpty {
                    print("[mirror] ⌨️ Sending text: '\(printableChars)'")
                    WebSocketServer.shared.sendTextInput(text: printableChars)
                    return nil
                } else {
                    print("[mirror] ⌨️ Ignoring non-printable: '\(characters)'")
                }
            }
        }
        return event
    }
    
    private func handleTap(at point: CGPoint, in imageSize: CGSize) {
        // Guard against zero image size to prevent division by zero
        guard imageSize.width > 0, imageSize.height > 0 else {
            print("[mirror] ⚠️ Ignoring tap - image size is zero")
            return
        }
        
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
        
        // Guard against infinite or NaN scale values
        guard scaleX.isFinite, scaleY.isFinite else {
            print("[mirror] ⚠️ Ignoring tap - invalid scale values")
            return
        }
        
        let androidX = Int(point.x * scaleX)
        let androidY = Int(point.y * scaleY)
        
        WebSocketServer.shared.sendInputTap(x: androidX, y: androidY)
    }
    
    private func handleDrag(from start: CGPoint, to end: CGPoint, in imageSize: CGSize) {
        // Guard against zero image size to prevent division by zero
        guard imageSize.width > 0, imageSize.height > 0 else {
            print("[mirror] ⚠️ Ignoring drag - image size is zero")
            return
        }
        
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
        
        // Guard against infinite or NaN scale values
        guard scaleX.isFinite, scaleY.isFinite else {
            print("[mirror] ⚠️ Ignoring drag - invalid scale values")
            return
        }
        
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
        // Guard against zero image size to prevent division by zero
        guard imageSize.width > 0, imageSize.height > 0 else {
            print("[mirror] ⚠️ Ignoring scroll - image size is zero")
            return
        }
        
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
        
        // Guard against infinite or NaN scale values
        guard scaleX.isFinite, scaleY.isFinite else {
            print("[mirror] ⚠️ Ignoring scroll - invalid scale values")
            return
        }
        
        let x = Int(point.x * scaleX)
        let y = Int(point.y * scaleY)
        
        // Convert scroll delta to swipe distance (negative delta = scroll up = swipe down)
        // Increased sensitivity for smoother scrolling
        let swipeDistance = Int(-delta * 5)
        let y2 = max(0, min(Int(androidHeight), y + swipeDistance))
        
        WebSocketServer.shared.sendInputSwipe(x1: x, y1: y, x2: x, y2: y2, durationMs: 50)
    }
}

// SwiftUI-based interactive image view with proper scroll monitor lifecycle
struct InteractiveImageView: View {
    let image: NSImage
    @Binding var screenSize: CGSize
    let onTap: (CGPoint, CGSize) -> Void
    let onDrag: (CGPoint, CGPoint, CGSize) -> Void
    let onScroll: (CGFloat, CGPoint, CGSize) -> Void
    
    @State private var dragStart: CGPoint?
    @State private var scrollMonitor: Any?
    @State private var currentGeometry: CGSize = .zero
    
    var body: some View {
        GeometryReader { geometry in
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
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
                            
                            let imageRect = calculateImageRect(imageSize: image.size, viewSize: geometry.size)
                            
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
                .onChange(of: geometry.size) { _, newSize in
                    currentGeometry = newSize
                }
                .onAppear {
                    currentGeometry = geometry.size
                    setupScrollMonitor()
                }
                .onDisappear {
                    removeScrollMonitor()
                }
        }
    }
    
    private func setupScrollMonitor() {
        // Remove existing monitor first
        removeScrollMonitor()
        
        // Capture values needed for scroll handling
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [self] event in
            // Use stored geometry to avoid capturing stale values
            guard currentGeometry.width > 0, currentGeometry.height > 0 else { return event }
            
            let location = NSEvent.mouseLocation
            if let window = NSApp.keyWindow {
                let windowPoint = window.convertPoint(fromScreen: location)
                let imageRect = calculateImageRect(imageSize: image.size, viewSize: currentGeometry)
                
                // Only handle scroll if within image bounds
                if imageRect.contains(windowPoint) {
                    let relativePoint = CGPoint(
                        x: windowPoint.x - imageRect.origin.x,
                        y: windowPoint.y - imageRect.origin.y
                    )
                    onScroll(event.scrollingDeltaY, relativePoint, imageRect.size)
                }
            }
            return event
        }
    }
    
    private func removeScrollMonitor() {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
    }
    
    private func calculateImageRect(imageSize: CGSize, viewSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              viewSize.width > 0, viewSize.height > 0 else {
            return .zero
        }
        
        let imageAspect = imageSize.width / imageSize.height
        let viewAspect = viewSize.width / viewSize.height
        
        if imageAspect > viewAspect {
            // Image is wider - fit to width
            let height = viewSize.width / imageAspect
            return CGRect(
                x: 0,
                y: (viewSize.height - height) / 2,
                width: viewSize.width,
                height: height
            )
        } else {
            // Image is taller - fit to height
            let width = viewSize.height * imageAspect
            return CGRect(
                x: (viewSize.width - width) / 2,
                y: 0,
                width: width,
                height: viewSize.height
            )
        }
    }
}
#endif
