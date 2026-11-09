import SwiftUI

/// Dawn glow drawn behind root-page content. Scrolls with content; never animated.
/// CSS equivalent: `radial-gradient(900px 600px at 12% -8%)` — 900×600 are ellipse radii.
enum InkGlowChrome {
    /// Ellipse radii (pt). Bounding box is 2× these.
    static let radius = CGSize(width: 900, height: 600)
    static var size: CGSize {
        CGSize(width: radius.width * 2, height: radius.height * 2)
    }

    /// Center as fractions of the container (x of width, y of height).
    static let centerXFraction: CGFloat = 0.12
    static let centerYFraction: CGFloat = -0.08

    static let stopPurple: CGFloat = 0
    static let stopAmber: CGFloat = 0.38
    static let stopClear: CGFloat = 0.70

    static let purpleHex: UInt32 = 0x8E_3F_80
    static let amberHex: UInt32 = 0xC9_8B_2F

    static let purple = Color(
        red: Double((purpleHex >> 16) & 0xFF) / 255,
        green: Double((purpleHex >> 8) & 0xFF) / 255,
        blue: Double(purpleHex & 0xFF) / 255)
    static let amber = Color(
        red: Double((amberHex >> 16) & 0xFF) / 255,
        green: Double((amberHex >> 8) & 0xFF) / 255,
        blue: Double(amberHex & 0xFF) / 255)

    static func shouldDraw(
        contrast: ColorSchemeContrast, reduceTransparency: Bool
    ) -> Bool {
        contrast != .increased && !reduceTransparency
    }

    static func purpleOpacity(colorScheme: ColorScheme) -> Double {
        colorScheme == .dark ? 0.45 : 0.16
    }

    static func amberOpacity(colorScheme: ColorScheme) -> Double {
        colorScheme == .dark ? 0.28 : 0.16
    }

    /// Strongest mix at the purple / amber stops, blended over paper for the given appearance.
    static func peakHex(stop: PeakStop, appearance: InkPalette.Appearance) -> UInt32 {
        let paper = InkPalette.Token.paper.variant.hex(for: appearance)
        let isDark = appearance == .dark || appearance == .highContrastDark
        let scheme: ColorScheme = isDark ? .dark : .light
        switch stop {
        case .purple:
            return InkPalette.blend(
                foreground: purpleHex, alpha: purpleOpacity(colorScheme: scheme), over: paper)
        case .amber:
            return InkPalette.blend(
                foreground: amberHex, alpha: amberOpacity(colorScheme: scheme), over: paper)
        }
    }

    enum PeakStop: String, CaseIterable, Sendable {
        case purple
        case amber
    }
}

private struct InkGlowModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content.background {
            if InkGlowChrome.shouldDraw(
                contrast: contrast, reduceTransparency: reduceTransparency)
            {
                GeometryReader { geo in
                    let center = CGPoint(
                        x: geo.size.width * InkGlowChrome.centerXFraction,
                        y: geo.size.height * InkGlowChrome.centerYFraction)
                    EllipticalGradient(
                        stops: [
                            .init(
                                color: InkGlowChrome.purple.opacity(
                                    InkGlowChrome.purpleOpacity(colorScheme: colorScheme)),
                                location: InkGlowChrome.stopPurple),
                            .init(
                                color: InkGlowChrome.amber.opacity(
                                    InkGlowChrome.amberOpacity(colorScheme: colorScheme)),
                                location: InkGlowChrome.stopAmber),
                            .init(color: .clear, location: InkGlowChrome.stopClear),
                        ],
                        center: .center,
                        startRadiusFraction: 0,
                        endRadiusFraction: 1
                    )
                    .frame(width: InkGlowChrome.size.width, height: InkGlowChrome.size.height)
                    .position(center)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .ignoresSafeArea(edges: .top)
            }
        }
    }
}

extension View {
    /// Soft dawn glow at the top-leading corner. Omit under Increase Contrast or Reduce Transparency.
    func inkGlow() -> some View {
        modifier(InkGlowModifier())
    }
}
