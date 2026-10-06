#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit
    import VaultFormat

    @testable import Journal

    /// Günlük listesi, varlık okuma sayfası ve arama: açık / koyu / AX3 / Kontrastı Artır.
    @MainActor @Suite("Journal entity snapshots", .serialized)
    struct JournalEntitySnapshotTests {
        enum Case: String, CaseIterable, Sendable {
            case daysLight, daysDark, daysAX3, daysContrast, daysSelected
            case entityLight, entityDark, entityAX3, entityContrast
            case searchLight, searchDark, searchAX3, searchContrast

            var screen: Screen {
                switch self {
                case .daysLight, .daysDark, .daysAX3, .daysContrast, .daysSelected: .days
                case .entityLight, .entityDark, .entityAX3, .entityContrast: .entity
                case .searchLight, .searchDark, .searchAX3, .searchContrast: .search
                }
            }

            var colorScheme: SnapshotColorScheme {
                switch self {
                case .daysDark, .entityDark, .searchDark: .dark
                default: .light
                }
            }

            var dynamicType: SnapshotDynamicType {
                switch self {
                case .daysAX3, .entityAX3, .searchAX3: .accessibility3
                default: .medium
                }
            }

            var increaseContrast: Bool {
                switch self {
                case .daysContrast, .entityContrast, .searchContrast: true
                default: false
                }
            }

            var selectedDay: CalendarDate? {
                switch self {
                case .daysSelected: CalendarDate("2026-09-20")
                default: nil
                }
            }
        }

        enum Screen: String, Sendable {
            case days, entity, search
        }

        @Test func entityScreens() async throws {
            let context = try SnapshotHost.makeContext()
            defer { context.clean() }
            await context.start()
            #expect(context.store.lastUpdated != nil)
            let filter = ProcessInfo.processInfo.environment["SNAPSHOT_ONLY"]
                .map { Set($0.split(separator: ",").map(String.init)) }
            for snapshotCase in Case.allCases {
                if let filter, !filter.contains(snapshotCase.rawValue) { continue }
                await assert(snapshotCase, store: context.store, defaults: context.defaults.defaults)
            }
        }

        private func hostedView(
            screen: Screen, store: IndexStore, defaults: UserDefaults, selectedDay: CalendarDate?
        ) -> some View {
            let notifications = NotificationService(
                center: FakeNotificationCenter(), defaults: defaults,
                now: { snapshotNow },
                timeZone: { snapshotTimeZone })
            let calendar = CalendarService(source: DeniedCalendarSource())
            let location = LocationService(source: FakeLocationSource(), defaults: defaults)
            let intent = IntentNavigation()
            let root: AnyView =
                switch screen {
                case .days:
                    AnyView(DaysView(store: store, previewSelectedDay: selectedDay))
                case .entity:
                    AnyView(
                        EntityView(
                            store: store,
                            entity: store.content.entities.first { $0.name == "Deniz Arıkan" }
                                ?? store.content.entities[0]))
                case .search:
                    AnyView(SearchView(store: store, initialQuery: "Deniz"))
                }
            return NavigationStack { root }
                .environment(notifications)
                .environment(calendar)
                .environment(location)
                .environment(intent)
                .environment(\.locale, snapshotLocale)
                .environment(\.calendar, makeCalendar())
                .environment(\.timeZone, snapshotTimeZone)
                .environment(\.clockNow, { snapshotNow })
                .environment(\.openSearch, {})
        }

        private func assert(
            _ snapshotCase: Case, store: IndexStore, defaults: UserDefaults,
            file: StaticString = #filePath, line: UInt = #line
        ) async {
            let view =
                hostedView(
                    screen: snapshotCase.screen, store: store, defaults: defaults,
                    selectedDay: snapshotCase.selectedDay
                )
                .environment(\.colorScheme, snapshotCase.colorScheme.colorScheme)
                .environment(\.dynamicTypeSize, snapshotCase.dynamicType.size)
                .environment(\.calendar, makeCalendar())
                .environment(\.clockNow, { snapshotNow })
                .transaction { $0.animation = nil }
                .frame(width: snapshotCanvasSize.width, height: snapshotCanvasSize.height)

            let traits = UITraitCollection { mutable in
                mutable.userInterfaceStyle = snapshotCase.colorScheme.userInterfaceStyle
                mutable.preferredContentSizeCategory = snapshotCase.dynamicType.contentSize
                mutable.accessibilityContrast = snapshotCase.increaseContrast ? .high : .normal
                mutable.displayScale = 2
            }

            let previousAnimations = UIView.areAnimationsEnabled
            UIView.setAnimationsEnabled(false)
            defer { UIView.setAnimationsEnabled(previousAnimations) }

            let host = UIHostingController(rootView: view)
            host.overrideUserInterfaceStyle = snapshotCase.colorScheme.userInterfaceStyle
            host.view.frame = CGRect(origin: .zero, size: snapshotCanvasSize)

            let scene =
                UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
                ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            guard let scene else {
                Issue.record("Snapshot host needs a UIWindowScene (run under the Journal test host).")
                return
            }
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: snapshotCanvasSize)
            window.overrideUserInterfaceStyle = snapshotCase.colorScheme.userInterfaceStyle
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            for _ in 0..<40 {
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(50))
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                if !store.isProcessing { break }
            }
            try? await Task.sleep(for: .milliseconds(800))
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(200))
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()

            let record = ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"]
                .flatMap(SnapshotTestingConfiguration.Record.init(rawValue:))

            assertSnapshot(
                of: host,
                as: .image(
                    on: .iPhone13,
                    precision: snapshotPrecision,
                    perceptualPrecision: snapshotPerceptualPrecision,
                    size: snapshotCanvasSize,
                    traits: traits
                ),
                named: snapshotCase.rawValue,
                record: record,
                file: file,
                testName: "entityScreen",
                line: line
            )
            window.isHidden = true
            window.rootViewController = nil
        }

        private func makeCalendar() -> Calendar {
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = snapshotLocale
            calendar.timeZone = snapshotTimeZone
            return calendar
        }

        @MainActor private final class DeniedCalendarSource: CalendarEventSource {
            var authorization = CalendarAuthorization.denied
            var onChange: (@MainActor @Sendable () -> Void)?
            func requestFullAccess() async throws -> Bool { false }
            func events(from start: Date, to end: Date) async throws -> [CalendarEvent] { [] }
        }
    }
#endif
