import Cocoa

class RemoteDisplayView: NSView {
    private var client: RemoteViewerConnection?
    private var currentImage: NSImage?
    private var lastImageRect: NSRect = .zero

    // Coordinate mapping
    private var remoteWidth: CGFloat = 1080
    private var remoteHeight: CGFloat = 1920

    // Touch tracking for swipe gestures
    private var touchStartPoint: NSPoint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupTracking()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTracking()
    }

    private func setupTracking() {
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    func setClient(_ client: RemoteViewerConnection) {
        self.client = client
        client.onFrameReceived = { [weak self] image in
            self?.currentImage = image
            self?.remoteWidth = image.size.width
            self?.remoteHeight = image.size.height
            self?.needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let image = currentImage else {
            NSColor.black.setFill()
            dirtyRect.fill()
            return
        }

        // Fill background
        NSColor.black.setFill()
        dirtyRect.fill()

        // Draw image with aspect-fit inside bounds and remember the drawn rect for coordinate mapping
        let imageSize = image.size
        let viewSize = bounds.size
        let imageAspect = imageSize.width / imageSize.height
        let viewAspect = viewSize.width / viewSize.height

        var drawRect = bounds
        if imageAspect > viewAspect {
            // Image is wider than view: fit by width
            let width = viewSize.width
            let height = width / imageAspect
            let y = (viewSize.height - height) / 2.0
            drawRect = NSRect(x: 0, y: y, width: width, height: height)
        } else {
            // Image is taller than view: fit by height
            let height = viewSize.height
            let width = height * imageAspect
            let x = (viewSize.width - width) / 2.0
            drawRect = NSRect(x: x, y: 0, width: width, height: height)
        }

        lastImageRect = drawRect
        image.draw(in: drawRect)
    }

    // MARK: - Coordinate Conversion
    private func convertToRemoteCoordinates(_ point: NSPoint) -> (x: Int, y: Int) {
        // Map from view-space point to remote image coordinates using the last drawn image rect (aspect-fit)
        let rect = lastImageRect
        // If point is outside the drawn image rect, clamp to the rect so gestures near the bars still work reasonably
        let clampedX = min(max(point.x, rect.minX), rect.maxX)
        let clampedY = min(max(point.y, rect.minY), rect.maxY)

        let localX = clampedX - rect.minX
        let localY = clampedY - rect.minY

        guard rect.width > 0, rect.height > 0 else {
            return (0, 0)
        }

        let scaleX = remoteWidth / rect.width
        let scaleY = remoteHeight / rect.height

        // Flip Y coordinate: macOS view origin is bottom-left; remote (Android) origin is top-left
        let flippedLocalY = rect.height - localY

        let remoteX = Int((localX * scaleX).rounded())
        let remoteY = Int((flippedLocalY * scaleY).rounded())
        return (remoteX, remoteY)
    }

    // MARK: - Mouse Events (converted to touch events)
    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        window?.makeFirstResponder(self)
        touchStartPoint = location
    }

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)

        if let startPoint = touchStartPoint {
            let distance = hypot(location.x - startPoint.x, location.y - startPoint.y)

            if distance < 10 {
                // It's a tap
                let coords = convertToRemoteCoordinates(location)
                client?.sendTap(x: coords.x, y: coords.y)
            } else {
                // It's a swipe
                let startCoords = convertToRemoteCoordinates(startPoint)
                let endCoords = convertToRemoteCoordinates(location)
                client?.sendSwipe(
                    startX: startCoords.x,
                    startY: startCoords.y,
                    endX: endCoords.x,
                    endY: endCoords.y
                )
            }
        }

        touchStartPoint = nil
    }

    override func mouseDragged(with event: NSEvent) {
        // Optional: add visual feedback for swipe
    }

    // MARK: - Keyboard Events
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if let characters = event.characters, !characters.isEmpty {
            client?.sendText(characters)
        } else {
            // Convert macOS keycode to Android keycode
            let androidKeyCode = mapKeyCode(event.keyCode)
            if androidKeyCode > 0 {
                client?.sendKeyPress(keyCode: androidKeyCode)
            }
        }
    }

    private func mapKeyCode(_ macOSKeyCode: UInt16) -> Int {
        // Basic key mapping (extend as needed)
        switch macOSKeyCode {
        case 36: return 66  // Return -> Enter
        case 51: return 67  // Delete -> Del
        case 48: return 61  // Tab -> Tab
        case 53: return 4   // Escape -> Back
        case 49: return 62  // Space -> Space
        default: return 0
        }
    }
}

