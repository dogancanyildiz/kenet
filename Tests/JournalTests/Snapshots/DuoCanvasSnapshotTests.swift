#if os(iOS)
    import Foundation
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    @testable import Journal

    /// Today's phone screens on the iPhone Duo canvases: outer screen (compact × regular) and
    /// inner screen (regular × regular) with the phone layout. Screen roots are hosted like their
    /// phone references (frozen day and clock), so a difference comes from the canvas alone.
    /// The real `PhoneNavigation` is left out: SnapshotTesting draws its tab content blank.
    enum DuoCanvasSnapshotCase: String, CaseIterable, Sendable {
        case todayOuter, tasksOuter, entitiesOuter
        case todayInner, tasksInner, entitiesInner

        enum Screen: Sendable { case today, tasks, entities }

        var screen: Screen {
            switch self {
            case .todayOuter, .todayInner: .today
            case .tasksOuter, .tasksInner: .tasks
            case .entitiesOuter, .entitiesInner: .entities
            }
        }

        var canvas: ShellCanvas {
            switch self {
            case .todayOuter, .tasksOuter, .entitiesOuter: .duoOuter
            case .todayInner, .tasksInner, .entitiesInner: .duoInner()
            }
        }
    }

    /// Duo references are not a CI gate yet: the suite runs only when `SNAPSHOT_DUO=1` reaches the
    /// test host (`record-screen-snapshots.sh --duo` passes it as `TEST_RUNNER_SNAPSHOT_DUO`).
    /// Without it the iOS unit job, which skips only the default snapshot suites, would run them.
    @MainActor
    @Suite(
        "Duo canvas snapshots",
        .enabled(if: ProcessInfo.processInfo.environment["SNAPSHOT_DUO"] == "1"))
    struct PhoneScreensDuoSnapshotTests {
        /// Same tab-bar inset as the phone Today references.
        private static let tabBarHeight: CGFloat = 84

        @Test(arguments: DuoCanvasSnapshotCase.allCases)
        func duo(_ snapshotCase: DuoCanvasSnapshotCase) async throws {
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
                let goalsReady = GoalsReadyBox()
                let needsGoals = snapshotCase.screen == .today && !store.content.goals.isEmpty
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
            _ screen: DuoCanvasSnapshotCase.Screen, store: IndexStore, defaults: UserDefaults
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
            .environment(\.openSearch, {})
            // Without an action the masthead hides its Settings button.
            .environment(\.openSettings, {})
        }
    }

    /// Probes what SwiftUI reads under each canvas: the trait overrides must give the inner
    /// screen regular × regular, or every Duo reference is a phone picture in disguise.
    @MainActor @Suite("Duo canvas traits")
    struct DuoCanvasTraitTests {
        @Test(arguments: [
            (ShellCanvas.phone, UserInterfaceSizeClass.compact, UserInterfaceSizeClass.regular),
            (.duoOuter, .compact, .regular),
            (.duoInner(), .regular, .regular),
            (.duoInner(leading: 30), .regular, .regular),
        ])
        func sizeClasses(
            _ canvas: ShellCanvas, horizontal: UserInterfaceSizeClass, vertical: UserInterfaceSizeClass
        ) async throws {
            let box = SizeClassBox()
            await SnapshotHostGate.exclusive {
                let host = UIHostingController(rootView: SizeClassProbe(box: box))
                canvas.applySizeClasses(to: host)
                guard
                    let scene = UIApplication.shared.connectedScenes
                        .compactMap({ $0 as? UIWindowScene }).first
                else {
                    Issue.record("Probe needs a UIWindowScene (run under the Journal test host).")
                    return
                }
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(origin: .zero, size: canvas.size)
                window.rootViewController = host
                window.makeKeyAndVisible()
                defer {
                    window.isHidden = true
                    window.rootViewController = nil
                    window.windowScene = nil
                }
                for _ in 0..<20 where box.horizontal == nil {
                    host.view.layoutIfNeeded()
                    await Task.yield()
                }
            }
            #expect(box.horizontal == horizontal)
            #expect(box.vertical == vertical)
        }
    }

    @MainActor private final class SizeClassBox {
        var horizontal: UserInterfaceSizeClass?
        var vertical: UserInterfaceSizeClass?
    }

    private struct SizeClassProbe: View {
        let box: SizeClassBox
        @Environment(\.horizontalSizeClass) private var horizontal
        @Environment(\.verticalSizeClass) private var vertical

        var body: some View {
            Color.clear.onAppear {
                box.horizontal = horizontal
                box.vertical = vertical
            }
        }
    }

    @MainActor private final class GoalsReadyBox {
        var isReady = false
    }
#endif
