import SwiftUI
import AVFoundation

#if os(macOS)
import AppKit

struct H264DisplayView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = H264Decoder.shared.displayLayer
        view.wantsLayer = true
        view.layer = CALayer()
        view.layer?.addSublayer(layer)
        layer.frame = view.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let layer = nsView.layer?.sublayers?.first as? AVSampleBufferDisplayLayer {
            layer.frame = nsView.bounds
        }
    }
}
#endif
