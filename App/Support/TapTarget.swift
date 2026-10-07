import SwiftUI

/// Shared iPhone touch-target floor (Apple HIG: 44×44 pt). Mac is a no-op.
/// Length is fixed — it must not scale with Dynamic Type (AX5 would push past 100 pt).
enum TapTarget {
    static let minimumLength: CGFloat = 44
}

extension View {
    /// Expands layout and hit-testing to at least ``TapTarget/minimumLength`` on iOS.
    ///
    /// Apply this to a **Button label** (inside `label: { … }`) or to `configuration.label`
    /// in a `ButtonStyle`. Applying it *outside* a plain/borderless `Button` only pads the
    /// surrounding layout; taps in that padding do not activate the button.
    /// When used with `onTapGesture`, place this modifier *before* the gesture.
    func tapTarget() -> some View {
        #if os(iOS)
            frame(minWidth: TapTarget.minimumLength, minHeight: TapTarget.minimumLength)
                .contentShape(Rectangle())
        #else
            self
        #endif
    }
}
