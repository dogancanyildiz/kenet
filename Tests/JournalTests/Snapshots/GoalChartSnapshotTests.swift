#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import VaultFormat

    @testable import Journal

    @MainActor @Suite("Goal chart snapshots", .serialized)
    struct GoalChartSnapshotTests {
        @Test func dailyLight() async throws { try await run("kitap", "dailyLight") }
        /// AX3 keeps the last 30 days and two end labels (docs/design.md).
        @Test func dailyAX3() async throws { try await run("kitap", "dailyAX3", type: .accessibility3) }
        @Test func yearlyLight() async throws { try await run("okunan", "yearlyLight") }

        private func run(
            _ key: String, _ name: String,
            scheme: SnapshotColorScheme = .light, type: SnapshotDynamicType = .medium
        ) async throws {
            let context = try TaskTestContext()
            defer { context.clean() }
            try SummarySyntheticVault.generate(at: context.root)
            await context.start()
            #expect(context.store.lastUpdated != nil)
            let store = context.store
            let goal = try #require((try await store.goalDefinitions()).first { $0.key == key })
            await SnapshotHost.assertView(
                colorScheme: scheme, dynamicType: type, increaseContrast: false, named: name, store: store,
                size: CGSize(width: snapshotCanvasSize.width, height: 2000), testName: "goalChart",
                file: #filePath, line: #line
            ) {
                NavigationStack {
                    GoalDetailView(store: store, goal: goal, day: SummarySyntheticVault.today)
                }
                .environment(\.locale, snapshotLocale)
                .environment(\.timeZone, snapshotTimeZone)
                .environment(\.openSearch, {})
                .environment(\.openSettings, {})
            }
        }
    }
#endif
