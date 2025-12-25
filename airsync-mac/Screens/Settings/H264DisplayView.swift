import SwiftUI
import AVFoundation

#if os(macOS)
import AppKit
import QuartzCore

struct H264DisplayView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVSampleBufferDisplayLayer()
        view.wantsLayer = true
        view.layer = CALayer()
        view.layer?.addSublayer(layer)
        layer.frame = view.bounds
        let mask: CAAutoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer.autoresizingMask = mask
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let layer = nsView.layer?.sublayers?.first as? AVSampleBufferDisplayLayer {
            layer.frame = nsView.bounds
        }
    }
}
#endif

