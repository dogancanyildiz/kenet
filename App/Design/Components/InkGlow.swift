import SwiftUI

/// Dawn glow drawn behind root-page content. Scrolls with content; never animated.
enum InkGlowChrome {
    static let size = CGSize(width: 900, height: 600)
    static let center = UnitPoint(x: 0.12, y: -0.08)
    static let purple = Color(red: 0x8E / 255, green: 0x3F / 255, blue: 0x80 / 255)
    static let amber = Color(red: 0xC9 / 255, green: 0x8B / 255, blue: 0x2F / 255)

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
}

private struct InkGlowModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content.background(alignment: .topLeading) {
            if InkGlowChrome.shouldDraw(
                contrast: contrast, reduceTransparency: reduceTransparency)
            {
                glowLayer
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    private var glowLayer: some View {
        let purple = InkGlowChrome.purple.opacity(
            InkGlowChrome.purpleOpacity(colorScheme: colorScheme))
        let amber = InkGlowChrome.amber.opacity(
            InkGlowChrome.amberOpacity(colorScheme: colorScheme))
        return Ellipse()
            .fill(
                RadialGradient(
                    stops: [
                        .init(color: purple, location: 0),
                        .init(color: amber, location: 0.38),
                        .init(color: .clear, location: 0.70),
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: InkGlowChrome.size.width / 2
                )
            )
            .frame(width: InkGlowChrome.size.width, height: InkGlowChrome.size.height)
            .offset(
                x: InkGlowChrome.size.width * (InkGlowChrome.center.x - 0.5),
                y: InkGlowChrome.size.height * (InkGlowChrome.center.y - 0.5)
            )
            .ignoresSafeArea(edges: .top)
    }
}

extension View {
    /// Soft dawn glow at the top-leading corner. Omit under Increase Contrast or Reduce Transparency.
    func inkGlow() -> some View {
        modifier(InkGlowModifier())
    }
}
