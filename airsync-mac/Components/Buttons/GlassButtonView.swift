import SwiftUI

struct GlassButtonView: View {
    var label: String
    var systemImage: String? = nil
    var image: String? = nil
    var iconOnly: Bool = false
    var size: ControlSize = .large
    var primary: Bool = false
    var circleSize: CGFloat? = nil
    var fixedIconSize: CGFloat? = nil
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) { labelContent }
            .controlSize(size)
            .modifier(LabelStyleModifier(iconOnly: iconOnly && useSystemLabelStyle))
            .applyGlassButtonStyle(primary: primary)
            .contentTransition(.symbolEffect)
            .ifLet(circleSize) { view, dim in
                view.frame(width: dim, height: dim)
                    .contentShape(Circle())
                    .clipShape(Circle())
            }
    }

    @ViewBuilder
    private var labelContent: some View {
        if customIconSizingActive, iconOnly, let (imgView, altText) = iconImageView() {
            imgView.accessibilityLabel(Text(altText))
        } else {
            let translatedLabel = NSLocalizedString(label, comment: "")
            if let systemImage { Label(translatedLabel, systemImage: systemImage) }
            else if let image { Label(translatedLabel, image: image) }
            else { Text(translatedLabel) }
        }
    }
    // Use native system Label sizing when custom sizing is not active
    private var useSystemLabelStyle: Bool { !customIconSizingActive }

    // Activate custom icon sizing only if explicit circle or fixed icon size provided
    private var customIconSizingActive: Bool { circleSize != nil || fixedIconSize != nil }

    private func iconImageView() -> (AnyView, String)? {
        let resolvedSize: CGFloat = fixedIconSize
            ?? (circleSize.map { max(16, $0 * 0.5) })
            ?? 18 // default when custom sizing explicitly active without sizes

        if let system = systemImage {
            let v = Image(systemName: system)
                .resizable()
                .scaledToFit()
                .frame(width: resolvedSize, height: resolvedSize)
                .font(.system(size: resolvedSize, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .padding(.zero)
            return (AnyView(v), label)
        }
        if let imgName = image {
            let v = Image(imgName)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .frame(width: resolvedSize, height: resolvedSize)
                .padding(.zero)
            return (AnyView(v), label)
        }
        return nil
    }
}

private extension View {
    @ViewBuilder
    func ifLet<T, Content: View>(_ value: T?, transform: (Self, T) -> Content) -> some View {
        if let value = value {
            transform(self, value)
        } else {
            self
        }
    }
}

// MARK: - Label Style Modifier

struct LabelStyleModifier: ViewModifier {
    var iconOnly: Bool

    func body(content: Content) -> some View {
        if iconOnly {
            content.labelStyle(IconOnlyLabelStyle())
        } else {
            content.labelStyle(TitleAndIconLabelStyle())
        }
    }
}

// MARK: - Button Style Extension

extension View {
    @ViewBuilder
    func applyGlassButtonStyle(primary: Bool) -> some View {
        if primary {
            self.glassPrimaryButtonIfAvailable()
        } else {
            self.glassButtonIfAvailable()
        }
    }
}


extension View {
    @ViewBuilder
    func glassButtonIfAvailable() -> some View {
        if !UIStyle.pretendOlderOS, #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    func glassPrimaryButtonIfAvailable() -> some View {
        if !UIStyle.pretendOlderOS, #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }
}


// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        GlassButtonView(label: "Normal", systemImage: "xmark")
        GlassButtonView(label: "Primary", systemImage: "checkmark", primary: true)
    }
    .padding()
}
