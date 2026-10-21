#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import VaultFormat

    @testable import Journal

    /// Chain days (decision 67) on the fictional ``GraceDayVault``: the Today strip's badge, the
    /// Goals list's badge after the streak, the goal page's balance line and the heatmap's
    /// chain-day mark with its legend item, and the cell kinds side by side with the forgiven ones.
    enum GraceDaySnapshotCase: String, CaseIterable, Sendable {
        case todayLight, todayAX3
        case listLight, listAX3
        case goalDetailLight, goalDetailAX3
        case cellsLight

        var dynamicType: SnapshotDynamicType {
            self == .todayAX3 || self == .listAX3 || self == .goalDetailAX3 ? .accessibility3 : .medium
        }
    }

    @MainActor @Suite("Chain day snapshots", .serialized)
    struct GraceDaySnapshotTests {
        /// Tab bar + home indicator, as the Today references draw it.
        private static let tabBarHeight: CGFloat = 84

        @Test(arguments: GraceDaySnapshotCase.allCases)
        func graceDay(_ snapshotCase: GraceDaySnapshotCase) async throws {
            let context = try TaskTestContext()
            defer { context.clean() }
            try GraceDayVault.generate(at: context.root)
            await context.start()
            #expect(context.store.lastUpdated != nil)
            switch snapshotCase {
            case .todayLight, .todayAX3:
                await today(snapshotCase, context: context)
            case .listLight, .listAX3:
                await list(snapshotCase, store: context.store)
            case .goalDetailLight, .goalDetailAX3:
                await goalDetail(snapshotCase, store: context.store)
            case .cellsLight:
                await SnapshotHost.assertView(
                    colorScheme: .light, dynamicType: .medium, increaseContrast: false,
                    named: snapshotCase.rawValue, store: context.store, size: CGSize(width: 390, height: 160),
                    testName: "graceDay"
                ) {
                    Self.cells.environment(\.locale, snapshotLocale)
                }
            }
        }

        private func today(_ snapshotCase: GraceDaySnapshotCase, context: TaskTestContext) async {
            let defaults = context.defaults.defaults
            let notifications = NotificationService(
                center: FakeNotificationCenter(), defaults: defaults, now: { snapshotNow },
                timeZone: { snapshotTimeZone })
            let ready = GraceGoalsReadyBox()
            let store = context.store
            let root = NavigationStack {
                DayView(store: store, date: GraceDayVault.today, isToday: true)
            }
            .environment(notifications)
            .environment(CalendarService(source: SnapshotCalendarSource()))
            .environment(LocationService(source: FakeLocationSource(), defaults: defaults))
            .environment(\.locale, snapshotLocale)
            .environment(\.calendar, makeSnapshotCalendar())
            .environment(\.timeZone, snapshotTimeZone)
            .environment(\.clockNow, { snapshotNow })
            .environment(\.openSearch, {})
            .environment(\.openSettings, {})
            .onPreferenceChange(GoalsStripReadyKey.self) { ready.isReady = $0 }
            await SnapshotHost.assertView(
                colorScheme: .light, dynamicType: snapshotCase.dynamicType, increaseContrast: false,
                named: snapshotCase.rawValue, store: store, size: snapshotCanvasSize,
                bottomSafeArea: Self.tabBarHeight, isReady: { ready.isReady }, testName: "graceDay",
                content: { root })
        }

        /// The Goals list on the vault's today: "Esneme" has the badge after its streak, "Okuma"
        /// none.
        private func list(_ snapshotCase: GraceDaySnapshotCase, store: IndexStore) async {
            let isLarge = snapshotCase.dynamicType == .accessibility3
            let root = NavigationStack {
                GoalsView(store: store)
            }
            .environment(\.locale, snapshotLocale)
            .environment(\.timeZone, snapshotTimeZone)
            .environment(\.openSearch, {})
            .environment(\.openSettings, {})
            await SnapshotHost.assertView(
                colorScheme: .light, dynamicType: snapshotCase.dynamicType, increaseContrast: false,
                named: snapshotCase.rawValue, store: store,
                size: CGSize(width: 390, height: isLarge ? 1000 : 420), testName: "graceDay",
                content: { root })
        }

        private func goalDetail(_ snapshotCase: GraceDaySnapshotCase, store: IndexStore) async {
            let isLarge = snapshotCase.dynamicType == .accessibility3
            await SnapshotHost.assertView(
                colorScheme: .light, dynamicType: snapshotCase.dynamicType, increaseContrast: false,
                named: snapshotCase.rawValue, store: store,
                size: CGSize(width: 390, height: isLarge ? 2200 : 1100), clock: snapshotNow,
                testName: "graceDay"
            ) {
                NavigationStack {
                    GoalDetailView(store: store, goal: GraceDayVault.stretching, day: GraceDayVault.today)
                }
                .environment(\.locale, snapshotLocale)
                .environment(\.timeZone, snapshotTimeZone)
                .environment(\.openSearch, {})
                .environment(\.openSettings, {})
            }
        }

        /// Both forgiven kinds next to both chain-day kinds and today, at heatmap and legend size.
        private static let cellKinds: [(kind: HeatmapCellKind, isToday: Bool, label: String)] = [
            (.empty, false, "empty"), (.partial, false, "partial"), (.forgiven, false, "forgiven"),
            (.forgivenPartial, false, "f+part"), (.graceSpent, false, "grace"),
            (.graceSpentPartial, false, "g+part"), (.empty, true, "today"),
        ]

        private static var cells: some View {
            HStack(alignment: .top, spacing: 10) {
                ForEach(cellKinds, id: \.label) { cell in
                    VStack(spacing: 6) {
                        HeatmapCell(
                            kind: cell.kind, size: 22, isToday: cell.isToday,
                            accessibilityValue: Text(verbatim: cell.label),
                            accessibilityLabel: Text(verbatim: cell.label))
                        HeatmapCell(
                            kind: cell.kind, size: 10, isToday: cell.isToday,
                            accessibilityValue: Text(verbatim: cell.label),
                            accessibilityLabel: Text(verbatim: cell.label))
                        Text(verbatim: cell.label)
                            .font(.ink.meta)
                            .foregroundStyle(Color.ink.secondaryText)
                    }
                }
            }
            .padding(InkSpacing.margin)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .inkPage()
        }
    }

    @MainActor private final class GraceGoalsReadyBox {
        var isReady = false
    }
#endif
