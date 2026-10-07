#if os(iOS)
    import GoalTracking
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit
    import VaultFormat

    @testable import Journal

    /// Sheet türleri (Bugün, Günlük, Hedefler alanı): günlük düzenleyicisi, görev tarihi,
    /// hedef miktarı, hedef alanı. Her biri açık, koyu ve AX3; ayrıca tek vakalar.
    enum JournalSheetSnapshotSubject: String, CaseIterable, Sendable {
        /// Toplu kaydeden: "Vazgeç / Kaydet".
        case journalEditor
        /// Her seçim anında yazar: yalnız "Kapat".
        case taskDate
        /// Sayı hedefi: çukur zeminli miktar alanı, "Vazgeç / Kaydet".
        case goalValue
        /// Dönem alanı: manşetin altında sekme, "Vazgeç / Kaydet".
        case goalField
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

        /// Evet / hayır hedefi: vurgu renkli anahtar.
        @Test func goalValueToggleLight() async throws {
            let context = try SnapshotHost.makeContext()
            defer { context.clean() }
            await context.start()
            let goal = try #require(context.store.content.goals.first { $0.key == "spor" })
            let view = try await Self.goalValueEditor(goal: goal, store: context.store)
            await Self.assert(
                view, named: "goalValueToggleLight", variant: .light, store: context.store,
                clock: goalsSnapshotNow)
        }

        /// Ad alanı: tek metin satırı.
        @Test func goalFieldNameLight() async throws {
            let context = try SnapshotHost.makeContext()
            defer { context.clean() }
            await context.start()
            let goal = try #require(context.store.content.goals.first { $0.key == "kitap" })
            await Self.assert(
                AnyView(GoalFieldEditor(store: context.store, goal: goal, field: .name)),
                named: "goalFieldNameLight", variant: .light, store: context.store,
                clock: goalsSnapshotNow)
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
            .environment(\.openSearch, {})
            .onPreferenceChange(GoalsStripReadyKey.self) { ready.isReady = $0 }
            await SnapshotHost.assertView(
                colorScheme: variant.colorScheme, dynamicType: variant.dynamicType,
                increaseContrast: false, named: "dayPast" + variant.rawValue, store: store,
                isReady: { store.content.goals.isEmpty || ready.isReady }, testName: "sheet",
                file: #filePath, line: #line, content: { root })
        }

        // MARK: - Builders

        private static func clock(for subject: JournalSheetSnapshotSubject) -> Date {
            switch subject {
            case .goalValue, .goalField: goalsSnapshotNow
            case .journalEditor, .taskDate: snapshotNow
            }
        }

        private static func sheetView(_ subject: JournalSheetSnapshotSubject, store: IndexStore)
            async throws -> AnyView
        {
            switch subject {
            case .journalEditor:
                return AnyView(JournalView(store: store, date: snapshotDay, focusesOnLoad: false))
            case .taskDate:
                // A dated task: the picker otherwise starts from the wall clock.
                let row = try #require(
                    store.content.tasks.first { $0.due == snapshotDay && !$0.isClosed })
                return AnyView(TaskDateEditor(model: TaskEditorModel(store: store, row: row)))
            case .goalValue:
                let goal = try #require(store.content.goals.first { $0.key == "kitap" })
                return try await goalValueEditor(goal: goal, store: store)
            case .goalField:
                let goal = try #require(store.content.goals.first { $0.key == "kitap" })
                return AnyView(GoalFieldEditor(store: store, goal: goal, field: .period))
            }
        }

        private static func goalValueEditor(goal: GoalDefinition, store: IndexStore) async throws
            -> AnyView
        {
            let dayModel = GoalDayModel(store: store, day: goalsSnapshotDay)
            await dayModel.load()
            #expect(dayModel.canEdit)
            return AnyView(GoalValueEditor(model: GoalValueModel(dayModel: dayModel, goal: goal)))
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
                    .environment(\.openSearch, {})
            }
        }
    }

    @MainActor private final class JournalSheetReadyBox {
        var isReady = false
    }
#endif
