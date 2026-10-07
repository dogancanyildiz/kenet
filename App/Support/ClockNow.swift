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
