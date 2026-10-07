#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import VaultFormat

    @testable import Journal

    /// Görevler alanında görüntü testi olmayan sayfa ve her sheet türü: proje sayfası, görev
    /// ayrıntısı (yalnız okunan sheet), tekrar (düzenleyen sheet), zaman çizelgesi tarihi
    /// (kapanan sheet). Separate `@Test` methods so one case can be re-recorded alone.
    @MainActor @Suite("Tasks pattern snapshots", .serialized)
    struct TasksPatternSnapshotTests {
        enum Subject { case project, detailSheet, recurrenceSheet, dateSheet }

        @Test func projectLight() async throws { try await run(.project, "projectLight") }
        @Test func projectDark() async throws { try await run(.project, "projectDark", scheme: .dark) }
        @Test func projectAX3() async throws {
            try await run(.project, "projectAX3", type: .accessibility3)
        }
        @Test func projectContrast() async throws {
            try await run(.project, "projectContrast", contrast: true)
        }
        @Test func detailSheetLight() async throws { try await run(.detailSheet, "detailSheetLight") }
        @Test func detailSheetDark() async throws {
            try await run(.detailSheet, "detailSheetDark", scheme: .dark)
        }
        @Test func detailSheetAX3() async throws {
            try await run(.detailSheet, "detailSheetAX3", type: .accessibility3)
        }
        @Test func recurrenceSheetLight() async throws {
            try await run(.recurrenceSheet, "recurrenceSheetLight")
        }
        @Test func recurrenceSheetDark() async throws {
            try await run(.recurrenceSheet, "recurrenceSheetDark", scheme: .dark)
        }
        @Test func recurrenceSheetAX3() async throws {
            try await run(.recurrenceSheet, "recurrenceSheetAX3", type: .accessibility3)
        }
        @Test func dateSheetLight() async throws { try await run(.dateSheet, "dateSheetLight") }
        @Test func dateSheetDark() async throws {
            try await run(.dateSheet, "dateSheetDark", scheme: .dark)
        }
        @Test func dateSheetAX3() async throws {
            try await run(.dateSheet, "dateSheetAX3", type: .accessibility3)
        }

        private func run(
            _ subject: Subject, _ name: String, scheme: SnapshotColorScheme = .light,
            type: SnapshotDynamicType = .medium, contrast: Bool = false
        ) async throws {
            let context = try SnapshotHost.makeContext()
            defer { context.clean() }
            await context.start()
            let store = context.store
            let defaults = context.defaults.defaults
            let row = try #require(store.content.tasks.first { $0.sourceIdentifier == "r3pe29" })
            let project = try #require(row.project)
            let recurrence = TaskEditorModel(store: store, row: row)
            await recurrence.load()
            await SnapshotHost.assertView(
                colorScheme: scheme, dynamicType: type, increaseContrast: contrast, named: name,
                store: store, testName: "tasksPattern"
            ) {
                NavigationStack {
                    switch subject {
                    case .project:
                        ProjectView(store: store, name: project)
                    case .detailSheet:
                        TaskDetailView(store: store, row: row) { _ in }
                            .inkSheet("Görev", onClose: {})
                    case .recurrenceSheet:
                        TaskRecurrenceEditor(model: recurrence)
                    case .dateSheet:
                        TimelineDateEditor(
                            model: TimelineModel(tasks: TasksModel(store: store, today: { snapshotDay })),
                            selection: TimelineDateSelection(row: row, edge: .due, root: store.vaultURL))
                    }
                }
                .environment(
                    NotificationService(
                        center: FakeNotificationCenter(), defaults: defaults, now: { snapshotNow },
                        timeZone: { snapshotTimeZone })
                )
                .environment(CalendarService(source: SnapshotCalendarSource()))
                .environment(LocationService(source: FakeLocationSource(), defaults: defaults))
                .environment(IntentNavigation())
                .environment(\.locale, snapshotLocale)
                .environment(\.timeZone, snapshotTimeZone)
                .environment(\.openSearch, {})
                .environment(\.openSettings, {})
            }
        }
    }
#endif
