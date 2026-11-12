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

    /// Production writes nothing into the environment: only the screen tour gets a frozen clock.
    @Test func onlyTheTourHasAFrozenClock() {
        #expect(AppLaunchPolicy.frozenClock(environment: [:]) == nil)
        #expect(AppLaunchPolicy.frozenClock(environment: ["JOURNAL_UITEST_CLOCK": "09:41"]) == nil)
        #expect(
            AppLaunchPolicy.frozenClock(
                environment: ["JOURNAL_UITEST_VAULT": "/tmp/vault", "JOURNAL_UITEST_CLOCK": "09:41"]) != nil)
    }

    /// The screen tour's calendar has full access and today's three fictional events; without a
    /// vault the app keeps EventKit.
    @Test func tourCalendarHasTodaysSampleEvents() async throws {
        let source = AppLaunchPolicy.calendarSource(
            environment: ["JOURNAL_UITEST_VAULT": "/tmp/vault", "JOURNAL_UITEST_CALENDAR": "sample"])
        let memory = try #require(source as? InMemoryCalendarSource)
        #expect(memory.authorization == .fullAccess)
        let day = Calendar.current.startOfDay(for: Date())
        let events = try await memory.events(from: day, to: day.addingTimeInterval(86_400))
        #expect(events.count == 3)
        #expect(AppLaunchPolicy.calendarSource(environment: ["JOURNAL_UITEST_CALENDAR": "sample"]) is EventKitCalendarSource)
    }
}
