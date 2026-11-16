#if os(iOS)
    import Foundation
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    @testable import Kenet

    /// Screen roots on the inner canvas with a camera/hinge inset on either side.
    /// The 30 pt inset is provisional until D1 measures the real device safe area.
    enum SafeAreaDuoSnapshotCase: String, CaseIterable, Sendable {
        case todayLeading, tasksLeading, entitiesLeading
        case todayTrailing, tasksTrailing, entitiesTrailing

        enum Screen: Sendable { case today, tasks, entities }

        var screen: Screen {
            switch self {
            case .todayLeading, .todayTrailing: .today
            case .tasksLeading, .tasksTrailing: .tasks
            case .entitiesLeading, .entitiesTrailing: .entities
            }
        }

        var canvas: ShellCanvas {
            switch self {
            case .todayLeading, .tasksLeading, .entitiesLeading: .duoInner(leading: 30)
            case .todayTrailing, .tasksTrailing, .entitiesTrailing: .duoInner(trailing: 30)
            }
        }
    }

    /// A CI gate since 2026-11-16: the suite is in the default list of `snapshot-suites.sh`, so the
    /// iOS unit job skips it and the iPhone snapshot step runs it.
    @MainActor
    @Suite("Duo asymmetric safe area snapshots")
    struct SafeAreaDuoSnapshotTests {
        /// Same tab-bar inset as the phone Today references.
        private static let tabBarHeight: CGFloat = 84

        @Test(arguments: SafeAreaDuoSnapshotCase.allCases)
        func duo(_ snapshotCase: SafeAreaDuoSnapshotCase) async throws {
            let context = try SnapshotHost.makeContext()
            defer { context.clean() }
            await context.start()
            #expect(context.store.lastUpdated != nil)
            let store = context.store
            let defaults = context.defaults.defaults

            switch snapshotCase.screen {
            case .tasks:
                await SnapshotHost.assert(
                    named: snapshotCase.rawValue, screen: .tasks, colorScheme: .light,
                    dynamicType: .medium, increaseContrast: false, store: store, defaults: defaults,
                    shell: snapshotCase.canvas, testName: "duo")
            case .today, .entities:
                let goalsReady = SafeAreaGoalsReadyBox()
                let needsGoals = snapshotCase.screen == .today
                await SnapshotHost.assertView(
                    colorScheme: .light,
                    dynamicType: .medium,
                    increaseContrast: false,
                    named: snapshotCase.rawValue,
                    store: store,
                    shell: snapshotCase.canvas,
                    bottomSafeArea: snapshotCase.screen == .today ? Self.tabBarHeight : 0,
                    isReady: { !needsGoals || goalsReady.isReady },
                    testName: "duo",
                    content: {
                        Self.hostedView(snapshotCase.screen, store: store, defaults: defaults)
                            .onPreferenceChange(GoalsStripReadyKey.self) { goalsReady.isReady = $0 }
                    }
                )
            }
        }

        @ViewBuilder private static func hostedView(
            _ screen: SafeAreaDuoSnapshotCase.Screen, store: IndexStore, defaults: UserDefaults
        ) -> some View {
            let notifications = NotificationService(
                center: FakeNotificationCenter(), defaults: defaults,
                now: { snapshotNow },
                timeZone: { snapshotTimeZone })
            let location = LocationService(source: FakeLocationSource(), defaults: defaults)
            Group {
                switch screen {
                case .today:
                    NavigationStack { DayView(store: store, date: snapshotDay, isToday: true) }
                case .entities:
                    NavigationStack { EntitiesView(store: store) }
                case .tasks:
                    // Hosted by ``SnapshotHost/hostedView`` (frozen tasks model).
                    EmptyView()
                }
            }
            .environment(notifications)
            .environment(CalendarService(source: SnapshotCalendarSource()))
            .environment(location)
            .environment(
                GeofenceService(location: location, center: FakeGeofenceCenter(), defaults: defaults)
            )
            .environment(IntentNavigation())
            .environment(\.locale, snapshotLocale)
            .environment(\.timeZone, snapshotTimeZone)
            .environment(\.openSearch, .nothing)
            // Without an action the masthead hides its Settings button.
            .environment(\.openSettings, {})
        }
    }

    @MainActor private final class SafeAreaGoalsReadyBox {
        var isReady = false
    }
#endif
