//
//  TimeView.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-07-28.
//

import SwiftUI
internal import Combine
import CoreText

// MARK: - CoreText -> Path helper (macOS-safe)
private struct TextHelper {
    private init() { }

    static func path(for string: NSAttributedString) -> Path {
        let line = CTLineCreateWithAttributedString(string)
        let runs = CTLineGetGlyphRuns(line) as NSArray

        let outputPath = CGMutablePath()

        for i in 0..<CFArrayGetCount(runs) {
            let run = unsafeBitCast(CFArrayGetValueAtIndex(runs, i), to: CTRun.self)
            let attributes = CTRunGetAttributes(run) as NSDictionary

            let key = kCTFontAttributeName as NSAttributedString.Key
            guard let anyCTFont = attributes[key] else {
                print("[time-view] (liquid-glass) Missing font attribute in run attributes: \(attributes)")
                continue
            }
            let ctFont = anyCTFont as! CTFont

            let glyphCount = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: glyphCount)
            var positions = [CGPoint](repeating: .zero, count: glyphCount)

            CTRunGetGlyphs(run, CFRangeMake(0, 0), &glyphs)
            CTRunGetPositions(run, CFRangeMake(0, 0), &positions)

            for j in 0..<glyphCount {
                if let glyphPath = CTFontCreatePathForGlyph(ctFont, glyphs[j], nil) {
                    let position = positions[j]
                    let transform = CGAffineTransform(translationX: position.x, y: position.y)
                    outputPath.addPath(glyphPath, transform: transform)
                }
            }
        }

        let swiftUIPath = Path(outputPath)
        let bounds = swiftUIPath.boundingRect
        // Flip vertically within the bounds
        let flipped = swiftUIPath
            .applying(CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -bounds.height))
        return flipped
    }
}

// MARK: - Rounded font helper
private func roundedFont(ofSize size: CGFloat, weight: NSFont.Weight) -> NSFont {
    // Try common SF Rounded faces; fall back to system if not available
    let candidates = [
        "SF Pro Rounded Black",
        "SF Pro Display Rounded Black",
        "SF Pro Text Rounded Black"
    ]
    for name in candidates {
        if let f = NSFont(name: name, size: size) {
            // Return the rounded face directly; weight adjustments are limited for named fonts
            return f
        }
    }
    // Fallback to system font with requested weight
    return NSFont.systemFont(ofSize: size, weight: weight)
}

// MARK: - LiquidGlassText (flat, rounded)
private struct LiquidGlassText: View {
    private let string: NSAttributedString

    init(_ string: NSAttributedString) {
        self.string = string
    }

    init(_ text: String, font: NSFont) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .kern: -12
        ]
        self.string = NSAttributedString(string: text, attributes: attrs)
    }

    var body: some View {
        let path = TextHelper.path(for: string)
        let bounds = path.boundingRect

        Color.clear
            .frame(width: bounds.width, height: bounds.height, alignment: .center)
            .overlay(
                Group {
                    if !UIStyle.pretendOlderOS, #available(macOS 26.0, *) {
                        Color.clear
                            .glassEffect(in: path)   // keep glass effect, but no transition/animation here
                    } else {
                        Color.clear
                    }
                }
            )
            .accessibilityHidden(true)
    }
}


struct TimeView: View {
    @State private var currentDate = Date()
    @Namespace private var ns   // namespace for matchedGeometryEffect

    // Timer that updates every second
    private let timer = Timer
        .publish(every: 1, on: .main, in: .common)
        .autoconnect()

    var body: some View {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: currentDate)

        let is24Hour = isSystemUsing24Hour()
        let hourValue = components.hour ?? 0
        let displayHour = is24Hour ? hourValue : (hourValue % 12 == 0 ? 12 : hourValue % 12)
        let hour = String(format: "%02d", displayHour)
        let minute = String(format: "%02d", components.minute ?? 0)

        // Desired size and weight
        let fontSize: CGFloat = 85
        // Use a rounded NSFont for the liquid glass path
        let roundedNSFont = roundedFont(ofSize: fontSize, weight: .black)

        ZStack {
            if #available(macOS 26.0, *) {
                GlassEffectContainer {
                    ClockLayout(
                        hour: hour,
                        minute: minute,
                        roundedNSFont: roundedNSFont,
                        ns: ns,
                        stacked: AppState.shared.isMusicCardHidden
                    )
                }
            } else {
                ClockLayout(
                    hour: hour,
                    minute: minute,
                    roundedNSFont: roundedNSFont,
                    ns: ns,
                    stacked: AppState.shared.isMusicCardHidden
                )
            }
        }

        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center) // keep centered
        .onReceive(timer) { newValue in currentDate = newValue }
        // spring animation drives the motion; tweak stiffness/damping for more/less jiggle
        .animation(.interpolatingSpring(stiffness: 300, damping: 15), value: AppState.shared.isMusicCardHidden)
        .foregroundColor(.white)
    }

    @ViewBuilder
    private func ClockLayout(
        hour: String,
        minute: String,
        roundedNSFont: NSFont,
        ns: Namespace.ID,
        stacked: Bool
    ) -> some View {
        let hourView = LiquidGlassText(hour, font: roundedNSFont)
            .matchedGeometryEffect(id: "hour", in: ns)
            .conditionalGlassEffectID("hour", in: ns)

        let minuteView = LiquidGlassText(minute, font: roundedNSFont)
            .matchedGeometryEffect(id: "minute", in: ns)
            .conditionalGlassEffectID("minute", in: ns)

        if stacked {
            VStack(alignment: .center, spacing: 0) {
                hourView
                minuteView
            }
            .id("stack")
        } else {
            HStack(alignment: .center, spacing: 0) {
                hourView
                minuteView
            }
            .id("row")
        }
    }



    private func isSystemUsing24Hour() -> Bool {
        let formatString = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: Locale.current) ?? ""
        return !formatString.contains("a")
    }
}

extension View {
    @ViewBuilder
    func conditionalGlassEffectID(_ id: String, in ns: Namespace.ID) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffectID(id, in: ns)
        } else {
            self
        }
    }
}



#Preview {
    TimeView()
}
