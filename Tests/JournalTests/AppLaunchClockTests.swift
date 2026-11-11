import Foundation
import Testing

@testable import Journal

/// The screen tour freezes the app's clock at 09:41; production and plain launches keep `Date()`.
@MainActor
struct AppLaunchClockTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }()
    private static let evening = Date(timeIntervalSince1970: 1_794_426_000)  // 2026-11-11 22:40 +03

    @Test func tourWithVaultFreezesTheTimeOfToday() {
        let clock = AppLaunchPolicy.clockNow(
            environment: ["JOURNAL_UITEST_VAULT": "/tmp/vault", "JOURNAL_UITEST_CLOCK": "09:41"],
            calendar: Self.calendar, now: Self.evening)
        let parts = Self.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: clock())
        #expect([parts.year, parts.month, parts.day, parts.hour, parts.minute] == [2026, 11, 11, 9, 41])
        #expect(clock() == clock())
    }

    @Test func withoutAVaultOrWithABadValueTheClockRuns() {
        let cases: [[String: String]] = [
            ["JOURNAL_UITEST_CLOCK": "09:41"],
            ["JOURNAL_UITEST_VAULT": "/tmp/vault", "JOURNAL_UITEST_CLOCK": "9.41"],
            ["JOURNAL_UITEST_VAULT": "/tmp/vault", "JOURNAL_UITEST_CLOCK": "24:00"],
            ["JOURNAL_UITEST_VAULT": "/tmp/vault"],
        ]
        for environment in cases {
            let clock = AppLaunchPolicy.clockNow(environment: environment, calendar: Self.calendar, now: Self.evening)
            #expect(abs(clock().timeIntervalSinceNow) < 5, "\(environment)")
        }
    }
}
