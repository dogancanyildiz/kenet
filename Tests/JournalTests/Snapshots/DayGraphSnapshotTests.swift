#if os(iOS)
    import Foundation
    import SnapshotTesting
    import SwiftUI
    import Testing
    import VaultFormat

    @testable import Journal

    /// The day's own graph on the graph fixture vault (`Fixtures/vaults/graph`, 2026-10-01: two
    /// people, two places and a custom type book around the day), and the day page's manşet with
    /// its Graph icon.
    enum DayGraphSnapshotCase: String, CaseIterable, Sendable {
        case dayGraphLight, dayGraphDark, dayGraphAX3
        case dayMastheadLight

        var colorScheme: SnapshotColorScheme { self == .dayGraphDark ? .dark : .light }
        var dynamicType: SnapshotDynamicType { self == .dayGraphAX3 ? .accessibility3 : .medium }
    }

    @MainActor @Suite("Day graph snapshots")
    struct DayGraphSnapshotTests {
        static let day = CalendarDate("2026-10-01")!

        @Test(arguments: DayGraphSnapshotCase.allCases)
        func dayGraph(_ snapshotCase: DayGraphSnapshotCase) async throws {
            let context = try TaskTestContext()
            defer { context.clean() }
            let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/vaults/graph")
            try FileManager.default.copyItem(at: fixture, to: context.root)
            await context.start()
            #expect(context.store.lastUpdated != nil)

            let defaults = context.defaults.defaults
            let notifications = NotificationService(
                center: FakeNotificationCenter(), defaults: defaults, now: { snapshotNow },
                timeZone: { snapshotTimeZone })
            let calendar = CalendarService(source: SnapshotCalendarSource())
            let location = LocationService(source: FakeLocationSource(), defaults: defaults)
            let store = context.store
            let isMasthead = snapshotCase == .dayMastheadLight
            let root = NavigationStack {
                if isMasthead {
                    DayView(store: store, date: Self.day, isToday: true)
                } else {
                    GraphView(store: store, scope: .day(Self.day), liveMotion: false)
                }
            }
            .environment(notifications)
            .environment(calendar)
            .environment(location)
            .environment(\.locale, snapshotLocale)
            .environment(\.calendar, makeSnapshotCalendar())
            .environment(\.timeZone, snapshotTimeZone)
            .environment(\.clockNow, { snapshotNow })
            .environment(\.openSearch, {})
            .environment(\.openSettings, {})
            await SnapshotHost.assertView(
                colorScheme: snapshotCase.colorScheme,
                dynamicType: snapshotCase.dynamicType,
                increaseContrast: false,
                named: snapshotCase.rawValue,
                store: store,
                testName: "dayGraph",
                content: { root }
            )
        }
    }
#endif
