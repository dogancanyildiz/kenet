import SwiftUI

/// Dawn glow drawn behind root-page content. Scrolls with content; never animated.
/// CSS equivalent: `radial-gradient(900px 600px at 12% -8%)` — 900×600 are ellipse radii.
enum InkGlowChrome {
    /// Ellipse radii (pt). Bounding box is 2× these.
    static let radius = CGSize(width: 900, height: 600)
    static var size: CGSize {
        CGSize(width: radius.width * 2, height: radius.height * 2)
    }

    /// Center as fractions of the container (x of width, y of a reference height).
    static let centerXFraction: CGFloat = 0.12
    static let centerYFraction: CGFloat = -0.08
    /// The glow is anchored to the first screenful, not to the whole scrolled content:
    /// vertical center uses min(container height, reference height).
    static let referenceHeight: CGFloat = 900

    /// Vertical center for a container of the given height.
    static func centerY(containerHeight: CGFloat) -> CGFloat {
        min(containerHeight, referenceHeight) * centerYFraction
    }

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

extension InkGlowChrome {
    /// The glow is drawn this far above its container too, so a glow placed in scrolled content
    /// still reaches under the status bar (the drawing starts at the screen's top edge).
    static let topBleed: CGFloat = 400

    /// Past this scroll distance the glow has left the screen; the offset stops updating.
    static let maximumTrackedOffset: CGFloat = 800

    /// The vertical shift that makes a glow drawn behind a scroll view move with its content.
    /// `offset` and `topInset` are the scroll view's content offset and top content inset; at
    /// rest the offset is minus the inset (shift 0). Pulling down (negative) moves it down too.
    static func scrollShift(offset: CGFloat, topInset: CGFloat) -> CGFloat {
        min(offset + topInset, maximumTrackedOffset)
    }
}

extension EnvironmentValues {
    /// Set by ``View/inkGlow()`` for the view it wraps. ``View/inkPage()`` inside it then draws
    /// the glow over its own paper, so `.inkPage().inkGlow()` shows the glow (the outer
    /// background alone would sit under the page's opaque paper). Only the iPhone tab shell reads
    /// it; sheets reset it (``InkSheet``).
    @Entry var inkPageGlow = false
}

/// The glow layer: fills its container (and ``InkGlowChrome/topBleed`` above it), moved up by
/// `shift` so it follows scrolled content.
struct InkGlowLayer: View {
    var shift: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if InkGlowChrome.shouldDraw(contrast: contrast, reduceTransparency: reduceTransparency) {
            GeometryReader { geo in
                let center = CGPoint(
                    x: geo.size.width * InkGlowChrome.centerXFraction,
                    y: InkGlowChrome.centerY(containerHeight: geo.size.height) - shift)
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
                    // `endRadiusFraction` is a fraction of the frame size: 0.5 makes the
                    // ellipse radii equal to `InkGlowChrome.radius` and fade out inside the frame.
                    startRadiusFraction: 0,
                    endRadiusFraction: 0.5
                )
                .frame(width: InkGlowChrome.size.width, height: InkGlowChrome.size.height)
                .position(center)
            }
            // Clipped at the container's bottom only: above, the glow bleeds under the status
            // bar even when the container is scrolled content that starts below it.
            .mask(alignment: .bottom) {
                Rectangle().padding(.top, -InkGlowChrome.topBleed)
                    .padding(.horizontal, -InkGlowChrome.radius.width)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .ignoresSafeArea(edges: .top)
        }
    }
}

/// Tracks the scroll offset of the scroll view it is applied to (none inside scrolled content:
/// the shift stays 0 and the glow scrolls with that content by itself).
struct InkGlowScrollTracking: ViewModifier {
    @Binding var shift: CGFloat

    func body(content: Content) -> some View {
        content.onScrollGeometryChange(for: CGFloat.self) { geometry in
            InkGlowChrome.scrollShift(offset: geometry.contentOffset.y, topInset: geometry.contentInsets.top)
        } action: { _, value in
            shift = value
        }
    }
}

private struct InkGlowModifier: ViewModifier {
    @State private var shift: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .environment(\.inkPageGlow, true)
            .background { InkGlowLayer(shift: shift) }
            .modifier(InkGlowScrollTracking(shift: $shift))
    }
}

extension View {
    /// Soft dawn glow at the top-leading corner of a root page. Omit under Increase Contrast or
    /// Reduce Transparency. Works on either side of ``inkPage()``; on a `List` or `ScrollView`
    /// it moves with the scrolled content.
    func inkGlow() -> some View {
        modifier(InkGlowModifier())
    }
}
