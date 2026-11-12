import Foundation
import SwiftUI

private struct ClockNowKey: EnvironmentKey {
    static let defaultValue: @MainActor @Sendable () -> Date = { Date() }
}

extension EnvironmentValues {
    /// Wall clock for UI that shows "now" (quick-entry time, midnight rollover).
    /// Snapshot tests replace this with a fixed instant; production keeps `Date()`.
    var clockNow: @MainActor @Sendable () -> Date {
        get { self[ClockNowKey.self] }
        set { self[ClockNowKey.self] = newValue }
    }
}

extension View {
    /// Writes a frozen `clockNow` only when one is given. Production passes nil and keeps the
    /// default: a closure has no equality, so writing one on every body pass of the app would
    /// invalidate every view that reads `clockNow`. The value is fixed for the launch, so the
    /// branch never flips and the view keeps its identity.
    @ViewBuilder
    func frozenClock(_ clock: (@MainActor @Sendable () -> Date)?) -> some View {
        if let clock {
            environment(\.clockNow, clock)
        } else {
            self
        }
    }
}
