#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import VaultFormat

    @testable import Journal

    /// Hedef tanımı formu: sayısal hedef (sekmeler, miktar, birim) ve kilometre taşı (dönem ve
    /// tür salt okunur). Her biri açık temada.
    @MainActor @Suite("Goal form snapshots", .serialized)
    struct GoalFormSnapshotTests {
        @Test func numberLight() async throws { try await run("kitap", "numberLight") }
        @Test func milestoneLight() async throws { try await run("portfolyo", "milestoneLight") }

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
            let deletion = DefinitionDeletionModel()
            await SnapshotHost.assertView(
                colorScheme: scheme, dynamicType: type, increaseContrast: false, named: name, store: store,
                size: type == .accessibility3 ? CGSize(width: snapshotCanvasSize.width, height: 1800) : nil,
                testName: "goalForm", file: #filePath, line: #line
            ) {
                NavigationStack {
                    GoalDefinitionForm(store: store, goal: goal, deletion: deletion)
                }
                .environment(\.locale, snapshotLocale)
                .environment(\.timeZone, snapshotTimeZone)
                .environment(\.openSearch, {})
            }
        }
    }
#endif
