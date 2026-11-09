import CoreGraphics
import SwiftUI

/// Spacing, control sizes, and stroke widths for Şafak.
/// Margin, gutter, and card padding bases are meant for `@ScaledMetric(relativeTo:)`.
enum InkSpacing {
    /// Page horizontal margin (pt). Pair with `@ScaledMetric(relativeTo: .body)`.
    static let margin: CGFloat = 16

    /// Edge column for marks inside a card (pt). Pair with `@ScaledMetric(relativeTo: .body)`.
    static let gutter: CGFloat = 44

    /// Card inner padding (pt). Pair with `@ScaledMetric(relativeTo: .body)`.
    static let cardPadding: CGFloat = 16

    /// Vertical gap between rows inside a card (tasks, goals, events).
    static let row: CGFloat = 12

    /// Vertical gap between section cards on Today.
    static let section: CGFloat = 16

    /// Mac reading column max width (pt).
    static let macPageWidth: CGFloat = 680

    /// Main window minimum width (pt): sidebar + list + reading column.
    static let macWindowMinWidth: CGFloat = 1000

    /// Mac sidebar column (pt): wide enough for the longest built-in name.
    static let macSidebarMinWidth: CGFloat = 180
    static let macSidebarIdealWidth: CGFloat = 200
    static let macSidebarMaxWidth: CGFloat = 240

    /// Mac list column (pt): manşet, tabs and a row of text fit on one line.
    static let macListMinWidth: CGFloat = 280
    static let macListIdealWidth: CGFloat = 320
    static let macListMaxWidth: CGFloat = 400

    /// Main window minimum height (pt).
    static let macWindowMinHeight: CGFloat = 560

    /// Settings scene minimum width (pt).
    static let macSettingsMinWidth: CGFloat = 480

    /// Settings scene minimum height (pt).
    static let macSettingsMinHeight: CGFloat = 520

    /// Mac list-selection fill, inset from the row's leading and trailing edges.
    static let listSelectionHorizontal: CGFloat = 4

    /// Mac list-selection fill, inset from the row's top and bottom edges.
    static let listSelectionVertical: CGFloat = 2
}

enum InkCorner {
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24

    /// Section card: `lg` on iPhone/iPad, `sm` on Mac.
    static var card: CGFloat {
        #if os(macOS)
            sm
        #else
            lg
        #endif
    }
}

enum InkSize {
    static let taskBox: CGFloat = 22
    static let taskBoxCorner: CGFloat = 6
    static let goalRing: CGFloat = 22
    /// Day-header ring beside the manşet.
    static let dayRing: CGFloat = 44
    /// Timeline card leading color bar.
    static let timelineBar: CGFloat = 4
    static let plus: CGFloat = 30
    static let send: CGFloat = 36
    /// Design table large number at default Dynamic Type (scales via ``LargeNumberText``).
    static let largeNumber: CGFloat = 48
    /// Selected mode underline under quick-entry kip words.
    static let modeUnderline: CGFloat = 2
    /// Corner of the Mac list-selection fill (`r-md`).
    static let listSelectionCorner: CGFloat = InkCorner.md
    /// Legacy chip corner; ``TagChip`` draws a capsule. Screens still reading this get `sm`.
    static let chipCorner: CGFloat = InkCorner.sm
    static let kanbanCorner: CGFloat = InkCorner.sm
    /// Stacked (accessibility) quick-entry chrome; not a full capsule radius.
    static let quickEntryCorner: CGFloat = InkCorner.lg
    /// Week-strip day cell.
    static let weekDayWidth: CGFloat = 44
    static let weekDayHeight: CGFloat = 56
}

/// Floating chrome and primary-add halo. Prefer view helpers over raw numbers.
enum InkShadow {
    /// Floating element (quick entry, plus): dark 0/8/28 black 45%; light 0/6/20 navy 10%.
    static func floating(colorScheme: ColorScheme) -> (color: Color, radius: CGFloat, y: CGFloat) {
        switch colorScheme {
        case .dark:
            return (Color.black.opacity(0.45), 28, 8)
        default:
            return (Color(red: 0.05, green: 0.08, blue: 0.2).opacity(0.10), 20, 6)
        }
    }

    /// Halo around the primary send / add control (`glowShadow`).
    static func glow(colorScheme: ColorScheme) -> (color: Color, radius: CGFloat, y: CGFloat) {
        let accent = Color.ink.accent
        switch colorScheme {
        case .dark:
            return (accent.opacity(0.45), 16, 0)
        default:
            return (accent.opacity(0.28), 12, 0)
        }
    }
}

enum InkStroke {
    /// Empty task box and ring track.
    static let control: CGFloat = 1.5

    /// High-priority task box frame.
    static let highPriority: CGFloat = 2

    /// Section hairline (1 px intent; use ``hairline(scale:)`` for true device pixels).
    static let rule: CGFloat = 1

    /// 1-pixel decorative rule for the current display scale.
    static func hairline(scale: CGFloat) -> CGFloat {
        scale > 0 ? 1 / scale : rule
    }
}

extension View {
    /// Floating-element drop shadow (quick entry, plus). Skipped when Reduce Transparency is on.
    @ViewBuilder func inkFloatingShadow() -> some View {
        modifier(InkFloatingShadowModifier())
    }

    /// Primary-add halo (`glowShadow`). Skipped under Increase Contrast or Reduce Transparency.
    @ViewBuilder func inkGlowShadow() -> some View {
        modifier(InkGlowShadowModifier())
    }
}

private struct InkFloatingShadowModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
        } else {
            let shadow = InkShadow.floating(colorScheme: colorScheme)
            content.shadow(color: shadow.color, radius: shadow.radius, y: shadow.y)
        }
    }
}

private struct InkGlowShadowModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if contrast == .increased || reduceTransparency {
            content
        } else {
            let shadow = InkShadow.glow(colorScheme: colorScheme)
            content.shadow(color: shadow.color, radius: shadow.radius, y: shadow.y)
        }
    }
}
