import CoreGraphics
import SwiftUI

/// Spacing, control sizes, and stroke widths for Mürekkep.
/// Margin and gutter bases are meant for `@ScaledMetric(relativeTo:)`.
enum InkSpacing {
    /// Page horizontal margin (pt). Pair with `@ScaledMetric(relativeTo: .body)`.
    static let margin: CGFloat = 16

    /// Edge column for marks (pt). Pair with `@ScaledMetric(relativeTo: .body)`.
    static let gutter: CGFloat = 44

    /// Mac reading column max width (pt).
    static let macPageWidth: CGFloat = 680
}

enum InkSize {
    static let taskBox: CGFloat = 22
    static let taskBoxCorner: CGFloat = 5
    static let goalRing: CGFloat = 22
    static let plus: CGFloat = 30
    static let send: CGFloat = 36
    /// Design table large number at default Dynamic Type (scales via ``LargeNumberText``).
    static let largeNumber: CGFloat = 48
    /// Selected mode underline under quick-entry kip words.
    static let modeUnderline: CGFloat = 2
    /// Heatmap / chip corner radius.
    static let chipCorner: CGFloat = 4
    static let kanbanCorner: CGFloat = 8
}

enum InkStroke {
    /// Empty task box and ring track.
    static let control: CGFloat = 1.5

    /// High-priority task box frame.
    static let highPriority: CGFloat = 2

    /// Section hairline (1 px intent; use ``hairline(scale:)`` for true device pixels).
    static let rule: CGFloat = 1

    /// Link underline at default contrast.
    static let underline: CGFloat = 1

    /// Link underline when Increase Contrast is on.
    static let underlineHighContrast: CGFloat = 2

    /// 1-pixel decorative rule for the current display scale.
    static func hairline(scale: CGFloat) -> CGFloat {
        scale > 0 ? 1 / scale : rule
    }
}
