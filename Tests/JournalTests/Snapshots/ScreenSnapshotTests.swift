#if os(iOS)
    import SnapshotTesting
    import Testing

    @testable import Journal

    /// Görevler ve diğer ortak ekranlar. Bugün vakaları ``TodaySnapshotTests``.
    @MainActor @Suite("Screen snapshots")
    struct ScreenSnapshotTests {
        @Test(arguments: ScreenSnapshotCase.allCases)
        func screen(_ snapshotCase: ScreenSnapshotCase) async throws {
            let context = try SnapshotHost.makeContext()
            defer { context.clean() }
            await context.start()
            #expect(context.store.lastUpdated != nil)
            await SnapshotHost.assert(
                snapshotCase, store: context.store, defaults: context.defaults.defaults)
        }
    }
#endif
