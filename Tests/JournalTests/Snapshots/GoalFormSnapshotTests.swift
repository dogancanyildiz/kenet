#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import VaultFormat

    @testable import Journal

    /// Hedef tanımı formu: sayısal hedef (sekmeler, miktar, birim) ve kilometre taşı (dönem ve
    /// tür salt okunur). Her biri açık, koyu ve AX3.
    @MainActor @Suite("Goal form snapshots", .serialized)
    struct GoalFormSnapshotTests {
        @Test func numberLight() async throws { try await run("kitap", "numberLight") }
        @Test func numberDark() async throws { try await run("kitap", "numberDark", scheme: .dark) }
        @Test func numberAX3() async throws { try await run("kitap", "numberAX3", type: .accessibility3) }
        @Test func milestoneLight() async throws { try await run("portfolyo", "milestoneLight") }
        @Test func milestoneDark() async throws { try await run("portfolyo", "milestoneDark", scheme: .dark) }
        @Test func milestoneAX3() async throws {
            try await run("portfolyo", "milestoneAX3", type: .accessibility3)
        }

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
