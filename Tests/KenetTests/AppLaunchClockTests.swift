import Foundation
import Testing

@testable import Kenet

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
            environment: ["KENET_UITEST_VAULT": "/tmp/vault", "KENET_UITEST_CLOCK": "09:41"],
            calendar: Self.calendar, now: Self.evening)
        let parts = Self.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: clock())
        #expect([parts.year, parts.month, parts.day, parts.hour, parts.minute] == [2026, 11, 11, 9, 41])
        #expect(clock() == clock())
    }

    @Test func withoutAVaultOrWithABadValueTheClockRuns() {
        let cases: [[String: String]] = [
            ["KENET_UITEST_CLOCK": "09:41"],
            ["KENET_UITEST_VAULT": "/tmp/vault", "KENET_UITEST_CLOCK": "9.41"],
            ["KENET_UITEST_VAULT": "/tmp/vault", "KENET_UITEST_CLOCK": "24:00"],
            ["KENET_UITEST_VAULT": "/tmp/vault"],
        ]
        for environment in cases {
            let clock = AppLaunchPolicy.clockNow(environment: environment, calendar: Self.calendar, now: Self.evening)
            #expect(abs(clock().timeIntervalSinceNow) < 5, "\(environment)")
        }
    }

    /// Production writes nothing into the environment: only the screen tour gets a frozen clock.
    @Test func onlyTheTourHasAFrozenClock() {
        #expect(AppLaunchPolicy.frozenClock(environment: [:]) == nil)
        #expect(AppLaunchPolicy.frozenClock(environment: ["KENET_UITEST_CLOCK": "09:41"]) == nil)
        #expect(
            AppLaunchPolicy.frozenClock(
                environment: ["KENET_UITEST_VAULT": "/tmp/vault", "KENET_UITEST_CLOCK": "09:41"]) != nil)
    }

    /// The screen tour's calendar has full access and today's three fictional events; without a
    /// vault the app keeps EventKit.
    @Test func tourCalendarHasTodaysSampleEvents() async throws {
        let source = AppLaunchPolicy.calendarSource(
            environment: ["KENET_UITEST_VAULT": "/tmp/vault", "KENET_UITEST_CALENDAR": "sample"])
        let memory = try #require(source as? InMemoryCalendarSource)
        #expect(memory.authorization == .fullAccess)
        let day = Calendar.current.startOfDay(for: Date())
        let events = try await memory.events(from: day, to: day.addingTimeInterval(86_400))
        #expect(events.count == 3)
        // Days read it on their own, as they read the `memory` calendar.
        #expect(
            AppLaunchPolicy.allowsCalendarLoad(
                environment: ["KENET_UITEST_VAULT": "/tmp/vault", "KENET_UITEST_CALENDAR": "sample"]))
        let withoutVault = AppLaunchPolicy.calendarSource(environment: ["KENET_UITEST_CALENDAR": "sample"])
        #expect(withoutVault is EventKitCalendarSource)
    }
}
