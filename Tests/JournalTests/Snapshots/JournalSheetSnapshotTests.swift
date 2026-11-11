#if os(iOS)
    import GoalTracking
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit
    import VaultFormat

    @testable import Journal

    /// Sheet türleri (Bugün, Günlük): günlük düzenleyicisi, olay metni, görev tarihi. Her biri açık, koyu ve AX3; ayrıca tek vakalar. Hedef tanımı formu kendi
    /// kümesindedir: `GoalFormSnapshotTests`.
    enum JournalSheetSnapshotSubject: String, CaseIterable, Sendable {
        /// Toplu kaydeden: "Vazgeç / Kaydet".
        case journalEditor
        /// Olay metni düzenleme (paylaşılan tek satır iskelet + anma şeridi).
        case eventEditor
        /// Her seçim anında yazar: yalnız "Kapat".
        case taskDate
    }

    enum JournalSheetSnapshotVariant: String, CaseIterable, Sendable {
        case light = "Light"
        case dark = "Dark"
        case accessibility3 = "AX3"

        var colorScheme: SnapshotColorScheme { self == .dark ? .dark : .light }
        var dynamicType: SnapshotDynamicType { self == .accessibility3 ? .accessibility3 : .medium }
    }

    @MainActor @Suite("Journal sheet snapshots")
    struct JournalSheetSnapshotTests {
        @Test(arguments: JournalSheetSnapshotSubject.allCases, JournalSheetSnapshotVariant.allCases)
        func sheet(_ subject: JournalSheetSnapshotSubject, _ variant: JournalSheetSnapshotVariant)
            async throws
        {
            let context = try SnapshotHost.makeContext()
            defer { context.clean() }
            await context.start()
            #expect(context.store.lastUpdated != nil)
            let view = try await Self.sheetView(subject, store: context.store)
            await Self.assert(
                view, named: subject.rawValue + variant.rawValue, variant: variant,
                store: context.store, clock: Self.clock(for: subject))
        }

        /// Yeni hedef sheet'inin koyu hâli (açık ve AX3 `GoalsSummarySnapshotTests` içinde).
        @Test func goalCreationDark() async throws {
            let context = try SnapshotHost.makeContext()
            defer { context.clean() }
            await context.start()
            await SnapshotHost.assert(
                named: "goalCreationDark", screen: .goalCreation, colorScheme: .dark,
                dynamicType: .medium, increaseContrast: false, store: context.store,
                defaults: context.defaults.defaults, testName: "sheet")
        }

        /// Geçmiş gün (alt sayfa): çubukta yalnız geri, arama manşet satırında.
        @Test(arguments: [JournalSheetSnapshotVariant.light, .accessibility3])
        func dayPast(_ variant: JournalSheetSnapshotVariant) async throws {
            let context = try SnapshotHost.makeContext()
            defer { context.clean() }
            await context.start()
            let store = context.store
            let defaults = context.defaults.defaults
            let notifications = NotificationService(
                center: FakeNotificationCenter(), defaults: defaults, now: { snapshotNow },
                timeZone: { snapshotTimeZone })
            let calendar = CalendarService(source: SnapshotCalendarSource())
            let location = LocationService(source: FakeLocationSource(), defaults: defaults)
            let ready = JournalSheetReadyBox()
            let day = try #require(CalendarDate("2026-09-18"))
            let root = NavigationStack {
                DayView(store: store, date: day)
            }
            .environment(notifications)
            .environment(calendar)
            .environment(location)
            .environment(\.locale, snapshotLocale)
            .environment(\.timeZone, snapshotTimeZone)
            .environment(\.openSearch, .nothing)
            .onPreferenceChange(GoalsStripReadyKey.self) { ready.isReady = $0 }
            await SnapshotHost.assertView(
                colorScheme: variant.colorScheme, dynamicType: variant.dynamicType,
                increaseContrast: false, named: "dayPast" + variant.rawValue, store: store,
                isReady: { ready.isReady }, testName: "sheet",
                file: #filePath, line: #line, content: { root })
        }

        // MARK: - Builders

        private static func clock(for subject: JournalSheetSnapshotSubject) -> Date {
            switch subject {
            case .journalEditor, .eventEditor, .taskDate: snapshotNow
            }
        }

        private static func sheetView(_ subject: JournalSheetSnapshotSubject, store: IndexStore)
            async throws -> AnyView
        {
            switch subject {
            case .journalEditor:
                return AnyView(JournalView(store: store, date: snapshotDay, focusesOnLoad: false))
            case .eventEditor:
                let row = try #require(try await store.computeDay(on: snapshotDay).events.first)
                let model = EventEditorModel(store: store, day: snapshotDay, row: row)
                await model.load()
                return AnyView(EventTextEditor(model: model))
            case .taskDate:
                // A dated task: the picker otherwise starts from the wall clock.
                let row = try #require(
                    try await store.allTasks().first { $0.due == snapshotDay && !$0.isClosed })
                return AnyView(TaskDateEditor(model: TaskEditorModel(store: store, row: row)))
            }
        }

        private static func assert(
            _ view: AnyView, named name: String, variant: JournalSheetSnapshotVariant,
            store: IndexStore, clock: Date
        ) async {
            await SnapshotHost.assertView(
                colorScheme: variant.colorScheme, dynamicType: variant.dynamicType,
                increaseContrast: false, named: name, store: store, clock: clock,
                testName: "sheet", file: #filePath, line: #line
            ) {
                NavigationStack { view }
                    .environment(\.locale, snapshotLocale)
                    .environment(\.timeZone, snapshotTimeZone)
                    .environment(\.openSearch, .nothing)
            }
        }
    }

    @MainActor private final class JournalSheetReadyBox {
        var isReady = false
    }
#endif
