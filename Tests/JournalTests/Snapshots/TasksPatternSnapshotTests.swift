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
        enum Subject { case project, detailSheet, recurrenceSheet, recurrenceInterval, recurrenceUnknown, dateSheet }

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
        /// "Her hafta" with an interval: the Stepper and "Tamamlanınca hesapla" rows.
        @Test func recurrenceSheetIntervalLight() async throws {
            try await run(.recurrenceInterval, "recurrenceSheetIntervalLight")
        }
        /// A rule the app cannot edit: the read-only "Tanınmayan tekrar" text.
        @Test func recurrenceSheetUnknownLight() async throws {
            try await run(.recurrenceUnknown, "recurrenceSheetUnknownLight")
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
            try Self.writeRecurringTasks(in: context.root, for: subject)
            await context.start()
            let store = context.store
            let defaults = context.defaults.defaults
            let row = try #require(store.content.tasks.first { $0.sourceIdentifier == "r3pe29" })
            let project = try #require(row.project)
            let recurring = try #require(
                store.content.tasks.first { $0.sourceIdentifier == Self.recurringIdentifier(for: subject) })
            let recurrence = TaskEditorModel(store: store, row: recurring)
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
                    case .recurrenceSheet, .recurrenceInterval, .recurrenceUnknown:
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

        private static func recurringIdentifier(for subject: Subject) -> String {
            switch subject {
            case .recurrenceInterval: "rcr2wk"
            case .recurrenceUnknown: "rcrunk"
            default: "r3pe29"
            }
        }

        /// The sample vault has no recurring task; the two extra cases add one line each
        /// (a two-week interval, and a rule the app does not recognize) to their own copy.
        private static func writeRecurringTasks(in root: URL, for subject: Subject) throws {
            let line: String
            switch subject {
            case .recurrenceInterval:
                line = "- [ ] Haftalık raporu gönder 🔁 every 2 weeks when done 📅 2026-09-25 ^rcr2wk"
            case .recurrenceUnknown:
                line = "- [ ] Yedekleri denetle 🔁 every weekday 📅 2026-09-25 ^rcrunk"
            default: return
            }
            let file = root.appendingPathComponent("journal/2026-09-23.md")
            var text = try String(contentsOf: file, encoding: .utf8)
            let anchor = try #require(text.range(of: "^r3pe29\n"))
            text.insert(contentsOf: line + "\n", at: anchor.upperBound)
            try text.write(to: file, atomically: true, encoding: .utf8)
        }
    }
#endif
