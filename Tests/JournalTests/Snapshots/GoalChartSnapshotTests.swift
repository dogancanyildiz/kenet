#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import VaultFormat

    @testable import Journal

    @MainActor @Suite("Goal chart snapshots", .serialized)
    struct GoalChartSnapshotTests {
        @Test func dailyLight() async throws { try await run("kitap", "dailyLight") }
        @Test func dailyDark() async throws { try await run("kitap", "dailyDark", scheme: .dark) }
        @Test func dailyAX3() async throws { try await run("kitap", "dailyAX3", type: .accessibility3) }
        @Test func yearlyLight() async throws { try await run("okunan", "yearlyLight") }
        @Test func yearlyDark() async throws { try await run("okunan", "yearlyDark", scheme: .dark) }
        @Test func yearlyAX3() async throws { try await run("okunan", "yearlyAX3", type: .accessibility3) }

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
            let goal = try #require(store.content.goals.first { $0.key == key })
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
