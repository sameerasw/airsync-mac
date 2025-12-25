import SwiftUI
import AppKit

struct RemoteControlCanvas: View {
    // The logical Android screen size used for coordinate mapping
    var androidSize: CGSize

    // Optional overlay image (e.g., last screenshot) to provide visual feedback
    var overlayImage: NSImage?

    // Gesture configuration
    var minimumSwipeDistance: CGFloat = 10

    @State private var viewSize: CGSize = .zero
    @State private var dragStart: CGPoint? = nil

    var body: some View {
        ZStack {
            if let overlayImage {
                Image(nsImage: overlayImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(dragGesture)
                    .highPriorityGesture(tapGesture)
            } else {
                Color.gray.opacity(0.2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .gesture(dragGesture)
                    .highPriorityGesture(tapGesture)
            }
        }
        .background(SizeReader(size: $viewSize))
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 10) {
                Button("Back") {
                    WebSocketServer.shared.sendNavAction("back")
                }
                Button("Home") {
                    WebSocketServer.shared.sendNavAction("home")
                }
                Button("Recents") {
                    WebSocketServer.shared.sendNavAction("recents")
                }
                Button("Screenshot") {
                    WebSocketServer.shared.requestScreenshot()
                }
            }
            .padding(6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding(10)
        }
    }

    private var tapGesture: some Gesture {
        TapGesture()
            .onEnded { location in
                // TapGesture doesn't provide location, fallback to center or ignore
                // Instead, do nothing here, taps handled in dragGesture with minimumDistance 0
            }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = value.startLocation
                }
            }
            .onEnded { value in
                guard let start = dragStart else {
                    return
                }
                let end = value.location
                let distance = hypot(end.x - start.x, end.y - start.y)
                if distance >= minimumSwipeDistance {
                    sendSwipe(from: start, to: end)
                } else {
                    sendTap(at: end)
                }
                dragStart = nil
            }
    }

    private func mapToAndroid(_ point: CGPoint) -> (x: Int, y: Int) {
        let scaleX = androidSize.width / max(viewSize.width, 1)
        let scaleY = androidSize.height / max(viewSize.height, 1)
        let androidX = max(0, min(Int(round(point.x * scaleX)), Int(androidSize.width)))
        let androidY = max(0, min(Int(round((viewSize.height - point.y) * scaleY)), Int(androidSize.height)))
        return (androidX, androidY)
    }

    private func sendTap(at point: CGPoint) {
        let mapped = mapToAndroid(point)
        WebSocketServer.shared.sendInputTap(x: mapped.x, y: mapped.y)
    }

    private func sendSwipe(from start: CGPoint, to end: CGPoint, durationMs: Int = 200) {
        let s = mapToAndroid(start)
        let e = mapToAndroid(end)
        WebSocketServer.shared.sendInputSwipe(x1: s.x, y1: s.y, x2: e.x, y2: e.y, durationMs: durationMs)
    }

    private struct SizeReader: View {
        @Binding var size: CGSize
        var body: some View {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { size = proxy.size }
                    .onChange(of: proxy.size) { _, newValue in size = newValue }
            }
        }
    }
}

#Preview {
    RemoteControlCanvas(androidSize: CGSize(width: 1080, height: 2400))
        .frame(width: 300, height: 600)
}
