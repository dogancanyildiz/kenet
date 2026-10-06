#if os(iOS)
    import SnapshotTesting
    import Testing

    @testable import Journal

    /// Görevler listesi, kanban ve zaman çizelgesi: açık, koyu, AX3, Kontrastı Artır.
    @MainActor @Suite("Tasks screen snapshots")
    struct TasksSnapshotTests {
        @Test(arguments: TasksSnapshotCase.allCases)
        func tasksScreen(_ snapshotCase: TasksSnapshotCase) async throws {
            let context = try SnapshotHost.makeContext()
            defer { context.clean() }
            await context.start()
            #expect(context.store.lastUpdated != nil)
            await SnapshotHost.assert(
                snapshotCase, store: context.store, defaults: context.defaults.defaults)
        }
    }
#endif
