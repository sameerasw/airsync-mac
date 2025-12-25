import SwiftUI
import AppKit
import QuartzCore

struct SnowfallView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true

        let emitterLayer = CAEmitterLayer()

        emitterLayer.emitterPosition = CGPoint(x: 110, y: 470)
        emitterLayer.emitterSize = CGSize(width: 400, height: 1) // Wider than the view
        emitterLayer.emitterShape = .line

        let cell = CAEmitterCell()
        cell.contents = createSnowflakeImage()
        cell.birthRate = 4
        cell.lifetime = 20.0

        cell.velocity = 5
        cell.velocityRange = 15
        cell.yAcceleration = -5

        cell.emissionLongitude = -.pi / 2
        cell.emissionRange = 20

        cell.scale = 0.05
        cell.scaleRange = 0.03
        cell.alphaRange = 0.5
        cell.alphaSpeed = -0.04

        emitterLayer.emitterCells = [cell]

        emitterLayer.frame = CGRect(x: 0, y: 0, width: 220, height: 460)
        view.layer?.addSublayer(emitterLayer)

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private func createSnowflakeImage() -> CGImage? {
        let size = CGSize(width: 20, height: 20)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.white.set()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        SnowfallView()
            .frame(width: 220, height: 460)
//            .border(Color.gray, width: 1)
            .clipped()
    }
}
