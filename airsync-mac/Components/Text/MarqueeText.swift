//
//  MarqueeText.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2026-05-28.
//

import SwiftUI
import AppKit

/// Seamlessly looping marquee text backed by Core Animation (zero CPU per frame).
/// Falls back to a static view when the text fits within `containerWidth`.
struct MarqueeText: NSViewRepresentable {
    let text: String
    var fontSize: CGFloat = 12
    var fontWeight: NSFont.Weight = .regular
    var containerWidth: CGFloat
    /// Scroll speed in points per second.
    var speed: Double = 40
    /// Gap between the end of one copy and the start of the next.
    var gap: CGFloat = 44

    func makeNSView(context: Context) -> MarqueeNSView {
        MarqueeNSView()
    }

    func updateNSView(_ nsView: MarqueeNSView, context: Context) {
        nsView.update(
            text: text,
            fontSize: fontSize,
            fontWeight: fontWeight,
            containerWidth: containerWidth,
            speed: speed,
            gap: gap
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MarqueeNSView, context: Context) -> CGSize? {
        CGSize(width: containerWidth, height: nsView.contentHeight)
    }
}

// MARK: - NSView

final class MarqueeNSView: NSView {
    private(set) var contentHeight: CGFloat = 16

    private let clipLayer    = CALayer()
    private let contentLayer = CALayer()
    private let textLayer1   = CATextLayer()
    private let textLayer2   = CATextLayer()

    // Track last values to avoid unnecessary redraws
    private var lastText            = ""
    private var lastFontSize: CGFloat    = -1
    private var lastFontWeight: NSFont.Weight = .regular
    private var lastContainerWidth: CGFloat  = -1
    private var lastSpeed: Double    = -1
    private var lastGap: CGFloat     = -1

    override init(frame: NSRect) {
        super.init(frame: frame)
        buildLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildLayers()
    }

    private func buildLayers() {
        wantsLayer = true
        layer?.masksToBounds = true

        clipLayer.masksToBounds = true
        layer?.addSublayer(clipLayer)

        contentLayer.masksToBounds = false
        clipLayer.addSublayer(contentLayer)

        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        for tl in [textLayer1, textLayer2] {
            tl.contentsScale  = scale
            tl.truncationMode = .none
            tl.isWrapped      = false
            tl.alignmentMode  = .left
            contentLayer.addSublayer(tl)
        }
    }

    func update(text: String, fontSize: CGFloat, fontWeight: NSFont.Weight,
                containerWidth: CGFloat, speed: Double, gap: CGFloat) {
        let changed = text != lastText
            || fontSize != lastFontSize
            || fontWeight != lastFontWeight
            || containerWidth != lastContainerWidth
            || speed != lastSpeed
            || gap != lastGap
        guard changed else { return }

        lastText           = text
        lastFontSize       = fontSize
        lastFontWeight     = fontWeight
        lastContainerWidth = containerWidth
        lastSpeed          = speed
        lastGap            = gap

        refresh()
    }

    // Called on system dark/light mode switch
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTextColor()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: lastContainerWidth, height: contentHeight)
    }

    // MARK: - Layout & Animation

    private func refresh() {
        let nsFont = NSFont.systemFont(ofSize: lastFontSize, weight: lastFontWeight)
        let attrs: [NSAttributedString.Key: Any] = [.font: nsFont]
        let measured  = (lastText as NSString).size(withAttributes: attrs)
        let tw        = ceil(measured.width)
        let th        = ceil(measured.height)
        contentHeight = th

        let loopWidth   = tw + lastGap
        let needsScroll = tw > lastContainerWidth

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let newFrame = NSRect(x: 0, y: 0, width: lastContainerWidth, height: th)
        if frame != newFrame {
            frame = newFrame
            invalidateIntrinsicContentSize()
        }

        clipLayer.frame = CGRect(x: 0, y: 0, width: lastContainerWidth, height: th)

        for tl in [textLayer1, textLayer2] {
            tl.string   = lastText
            tl.font     = nsFont
            tl.fontSize = lastFontSize
        }

        if needsScroll {
            contentLayer.frame = CGRect(x: 0, y: 0, width: loopWidth * 2, height: th)
            textLayer1.frame   = CGRect(x: 0,         y: 0, width: tw, height: th)
            textLayer2.frame   = CGRect(x: loopWidth,  y: 0, width: tw, height: th)
            textLayer2.isHidden = false
        } else {
            contentLayer.frame  = CGRect(x: 0, y: 0, width: tw, height: th)
            textLayer1.frame    = CGRect(x: 0, y: 0, width: tw, height: th)
            textLayer2.isHidden = true
        }

        CATransaction.commit()

        applyTextColor()

        // Restart scroll animation
        contentLayer.removeAnimation(forKey: "marquee")
        guard needsScroll else { return }

        // Reset model position so beginTime fill works correctly
        contentLayer.setValue(0, forKeyPath: "transform.translation.x")

        let anim            = CABasicAnimation(keyPath: "transform.translation.x")
        anim.fromValue      = 0
        anim.toValue        = -loopWidth
        anim.duration       = CFTimeInterval(loopWidth) / lastSpeed
        anim.repeatCount    = .infinity
        anim.isRemovedOnCompletion = false
        anim.fillMode       = .backwards
        anim.beginTime      = CACurrentMediaTime() + 1.0  // 1s initial pause
        contentLayer.add(anim, forKey: "marquee")
    }

    private func applyTextColor() {
        var resolved: CGColor = NSColor.labelColor.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = NSColor.labelColor.cgColor
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        textLayer1.foregroundColor = resolved
        textLayer2.foregroundColor = resolved
        CATransaction.commit()
    }
}
