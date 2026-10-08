#if os(macOS)
    import AppKit
    import Foundation
    import SwiftUI
    import Testing
    import VaultFormat

    @testable import Journal

    /// The Mac controls that replace system ones on paper, measured on the real AppKit views
    /// SwiftUI builds for them (hosted offscreen).
    @MainActor
    struct MacSystemControlTests {
        private static let turkish = Locale(identifier: "tr_TR")

        /// What the user does: the field's own stepper, which moves the first element (hour in a
        /// time field, day in a Turkish date field) and sends the control's action.
        private static func stepUp(_ picker: NSDatePicker) {
            _ = (picker.cell as? NSDatePickerCell)?.accessibilityPerformIncrement()
        }

        private static func local(_ hour: Int, _ minute: Int) -> Date {
            Calendar(identifier: .gregorian).date(
                from: DateComponents(year: 2026, month: 10, day: 8, hour: hour, minute: minute))!
        }

        private static func clock(_ date: Date) -> [Int] {
            let parts = Calendar(identifier: .gregorian).dateComponents(
                [.year, .month, .day, .hour, .minute], from: date)
            return [parts.year!, parts.month!, parts.day!, parts.hour!, parts.minute!]
        }

        // MARK: - Time field

        @Test func timeFieldIsAnHourAndMinuteFieldNamedForVoiceOver() async throws {
            let probe = PickerProbe(first: Self.local(22, 30), second: Self.local(7, 5))
            let mount = HostedLayout.Mount(
                TimeFieldProbe(probe: probe, locale: Self.turkish), size: CGSize(width: 480, height: 120))
            defer { mount.close() }
            await mount.settle()
            let picker = try #require(mount.views(NSDatePicker.self).first)
            #expect(mount.views(NSDatePicker.self).count == 1)
            #expect(picker.datePickerElements == .hourMinute)
            #expect(picker.datePickerStyle == .textFieldAndStepper)
            #expect(picker.accessibilityLabel() == "Görev saati")
            #expect(picker.isEnabled)

            probe.isEnabled = false
            await mount.settle()
            #expect(!picker.isEnabled)
        }

        @Test func timeFieldShowsOutsideChangesAndWritesOnlyHourAndMinute() async throws {
            let probe = PickerProbe(first: Self.local(22, 30), second: Self.local(7, 5))
            let mount = HostedLayout.Mount(
                TimeFieldProbe(probe: probe, locale: Self.turkish), size: CGSize(width: 480, height: 120))
            defer { mount.close() }
            await mount.settle()
            let picker = try #require(mount.views(NSDatePicker.self).first)
            #expect(picker.dateValue == probe.first)

            // Changed from outside (another window, a reset): the field follows.
            probe.first = Self.local(9, 15)
            await mount.settle()
            #expect(picker.dateValue == Self.local(9, 15))

            // The user steps the hour: the binding gets it, and nothing but the clock moves.
            Self.stepUp(picker)
            #expect(Self.clock(probe.first) == [2026, 10, 8, 10, 15])
            #expect(probe.second == Self.local(7, 5))
        }

        /// A row can be bound to another value while it stays on screen; the field must write to
        /// the binding it shows now.
        @Test func timeFieldWritesToTheBindingItShowsNow() async throws {
            let probe = PickerProbe(first: Self.local(22, 30), second: Self.local(7, 5))
            let mount = HostedLayout.Mount(
                TimeFieldProbe(probe: probe, locale: Self.turkish), size: CGSize(width: 480, height: 120))
            defer { mount.close() }
            await mount.settle()
            let picker = try #require(mount.views(NSDatePicker.self).first)

            probe.usesSecond = true
            await mount.settle()
            #expect(picker.dateValue == Self.local(7, 5))
            Self.stepUp(picker)
            #expect(Self.clock(probe.second) == [2026, 10, 8, 8, 5])
            #expect(probe.first == Self.local(22, 30))
        }

        /// "22:30" and "10:30 PM" need different widths: the field is as wide as its text.
        @Test func timeFieldIsAsWideAsItsTextInBothClockStyles() async throws {
            var widths: [String: CGFloat] = [:]
            for identifier in ["tr_TR", "en_US"] {
                let probe = PickerProbe(first: Self.local(22, 30), second: Self.local(7, 5))
                let mount = HostedLayout.Mount(
                    TimeFieldProbe(probe: probe, locale: Locale(identifier: identifier)),
                    size: CGSize(width: 480, height: 120))
                defer { mount.close() }
                await mount.settle()
                let picker = try #require(mount.views(NSDatePicker.self).first)
                let needed = picker.fittingSize.width
                #expect(
                    picker.frame.width >= needed - 0.5,
                    "\(identifier): field \(picker.frame.width) pt, text needs \(needed) pt")
                // The hosted frame includes the control's alignment insets (about 3 pt).
                #expect(picker.frame.width <= needed + 6, "\(identifier): no slack either")
                widths[identifier] = picker.frame.width
            }
            // The 12-hour text is the longer one; a fixed width would give both the same.
            let turkish = try #require(widths["tr_TR"])
            let american = try #require(widths["en_US"])
            #expect(american > turkish, "tr \(turkish) pt, en_US \(american) pt")
        }

        // MARK: - Date field

        @Test func dateFieldIsADayFieldNamedForVoiceOver() async throws {
            let day = CalendarDate(year: 2026, month: 10, day: 8)!
            let probe = PickerProbe(first: LocalDay.instant(for: day), second: LocalDay.instant(for: day))
            let mount = HostedLayout.Mount(
                DateFieldProbe(probe: probe, timeZone: .current), size: CGSize(width: 480, height: 120))
            defer { mount.close() }
            await mount.settle()
            let picker = try #require(mount.views(NSDatePicker.self).first)
            #expect(picker.datePickerElements == .yearMonthDay)
            #expect(picker.accessibilityLabel() == String(localized: "Görev tarihi"))
        }

        /// The field reads and steps the day in the zone the page converts with: no drift at
        /// either end of the world, nor here.
        @Test(arguments: ["Pacific/Kiritimati", "Pacific/Pago_Pago", TimeZone.current.identifier])
        func dateFieldKeepsTheDayInItsTimeZone(identifier: String) async throws {
            let zone = try #require(TimeZone(identifier: identifier))
            let day = CalendarDate(year: 2026, month: 10, day: 8)!
            let next = CalendarDate(year: 2026, month: 10, day: 9)!
            let other = CalendarDate(year: 2026, month: 3, day: 1)!
            let probe = PickerProbe(
                first: LocalDay.instant(for: day, timeZone: zone),
                second: LocalDay.instant(for: other, timeZone: zone))
            let mount = HostedLayout.Mount(
                DateFieldProbe(probe: probe, timeZone: zone), size: CGSize(width: 480, height: 120))
            defer { mount.close() }
            await mount.settle()
            let picker = try #require(mount.views(NSDatePicker.self).first)

            // The day the field displays is the day it was given.
            #expect(picker.timeZone == zone)
            let calendar = try #require(picker.calendar)
            let shown = calendar.dateComponents(in: picker.timeZone ?? .current, from: picker.dateValue)
            #expect([shown.year, shown.month, shown.day] == [2026, 10, 8])

            // One step is one day, still at noon of that zone.
            Self.stepUp(picker)
            #expect(LocalDay.today(at: probe.first, timeZone: zone) == next)
            #expect(probe.first == LocalDay.instant(for: next, timeZone: zone))

            // Changed from outside: the field follows.
            probe.first = LocalDay.instant(for: CalendarDate(year: 2027, month: 1, day: 31)!, timeZone: zone)
            await mount.settle()
            #expect(picker.dateValue == probe.first)

            // Bound to another value: the step goes there.
            let untouched = probe.first
            probe.usesSecond = true
            await mount.settle()
            #expect(picker.dateValue == LocalDay.instant(for: other, timeZone: zone))
            Self.stepUp(picker)
            #expect(LocalDay.today(at: probe.second, timeZone: zone) == CalendarDate(year: 2026, month: 3, day: 2)!)
            #expect(probe.first == untouched)
        }

        // MARK: - Graph weight filter

        @Test func graphWeightStepsByOneInsideItsBounds() {
            let step = GraphWeightStep(maximumWeight: 5)
            #expect(step.range(for: 1) == 1...5)
            #expect(!step.canDecrement(1))
            #expect(step.decremented(1) == 1)
            #expect(step.canIncrement(1))
            #expect(step.incremented(1) == 2)
            #expect(step.canDecrement(2))
            #expect(step.decremented(2) == 1)
            #expect(step.incremented(4) == 5)
            #expect(!step.canIncrement(5))
            #expect(step.incremented(5) == 5)
        }

        @Test func graphWeightAdjustActionUsesTheSameBounds() {
            let step = GraphWeightStep(maximumWeight: 5)
            #expect(step.adjusted(3, .increment) == 4)
            #expect(step.adjusted(3, .decrement) == 2)
            #expect(step.adjusted(5, .increment) == 5)
            #expect(step.adjusted(1, .decrement) == 1)
            // A filter above the graph's maximum stays where it is and can only come down.
            #expect(step.range(for: 9) == 1...9)
            #expect(step.adjusted(9, .increment) == 9)
            #expect(step.adjusted(9, .decrement) == 8)
            // A graph without edges still has the one valid value.
            #expect(GraphWeightStep(maximumWeight: 0).range(for: 1) == 1...1)
            #expect(GraphWeightStep(maximumWeight: 0).adjusted(1, .increment) == 1)
        }

        // MARK: - Settings tabs

        @Test func settingsTabsFollowTheDocumentedOrder() {
            let table = MacSettingsTab.allCases.map { "\($0.title.key)|\($0.systemImage)" }
            #expect(
                table == [
                    "Hızlı giriş|square.and.pencil", "Gizlilik|lock", "Bildirimler|bell",
                    "Takvim ve Konum|calendar", "Kasa|folder", "Tanılama|wrench.and.screwdriver",
                ])
        }

        /// Each page names itself (its navigation title becomes the window title), so a tab that
        /// showed another tab's page would be caught here.
        @Test func everySettingsTabShowsItsOwnPage() async throws {
            let fixture = try SettingsFixture()
            defer { fixture.clean() }
            await fixture.context.start()
            for tab in MacSettingsTab.allCases {
                let page = MacSettingsPage(tab: tab, store: fixture.context.store, shortcut: fixture.shortcut)
                let mount = HostedLayout.Mount(fixture.hosted(page), size: CGSize(width: 600, height: 700))
                defer { mount.close() }
                await mount.settle()
                #expect(mount.window.title == fixture.title(tab), "\(tab)")
            }
        }

        /// The whole tab view: selecting a tab brings up the page of that tab, not a neighbour's.
        @Test func selectingASettingsTabShowsThatTabsPage() async throws {
            let fixture = try SettingsFixture()
            defer { fixture.clean() }
            await fixture.context.start()
            for tab in MacSettingsTab.allCases {
                let settings = MacSettingsView(
                    store: fixture.context.store, shortcut: fixture.shortcut, selectedTab: tab)
                let mount = HostedLayout.Mount(fixture.hosted(settings), size: CGSize(width: 700, height: 700))
                defer { mount.close() }
                await mount.settle()
                #expect(mount.window.title == fixture.title(tab), "\(tab)")
            }
        }

        /// A Settings window wider than the reading width: each tab's list fills the window and
        /// keeps its rows in the centered column.
        @Test func settingsPagesFillAWideWindow() async throws {
            let fixture = try SettingsFixture()
            defer { fixture.clean() }
            await fixture.context.start()
            for tab in MacSettingsTab.allCases {
                let page = MacSettingsPage(tab: tab, store: fixture.context.store, shortcut: fixture.shortcut)
                try await InkPageScrollColumnTests.expectPage(fixture.hosted(page), minimumRows: 1)
            }
        }

        @Test func vaultTabFallsBackToItsRootWhenTheImportIsGone() {
            #expect(MacVaultSettingsPage.shown(nil, hasImport: true) == nil)
            #expect(MacVaultSettingsPage.shown(.entityTypes, hasImport: false) == .entityTypes)
            #expect(MacVaultSettingsPage.shown(.vaultImport, hasImport: true) == .vaultImport)
            #expect(MacVaultSettingsPage.shown(.vaultImport, hasImport: false) == nil)
        }

        // MARK: - Notification times

        @Test func reminderTimeHelpersReadAndWriteOneReminderInTheGivenZone() throws {
            let zone = try #require(TimeZone(identifier: "Pacific/Auckland"))
            let day = CalendarDate(year: 2026, month: 10, day: 8)!
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            var preferences = NotificationPreferences()

            let shown = preferences.fieldDate(\.goalTime, on: day, timeZone: zone)
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: shown)
            #expect([parts.year, parts.month, parts.day, parts.hour, parts.minute] == [2026, 10, 8, 20, 0])

            // Another day, another second: only hour and minute are kept.
            let picked = try #require(
                calendar.date(from: DateComponents(year: 2031, month: 2, day: 3, hour: 6, minute: 45, second: 59)))
            preferences.setTime(\.goalTime, from: picked, timeZone: zone)
            #expect(preferences.goalTime == NotificationTime(hour: 6, minute: 45))
            #expect(preferences.taskTime == NotificationTime(hour: 9))
            #expect(preferences.journalTime == NotificationTime(hour: 21))
        }

        /// The three time fields of the page, driven as the user drives them: each writes its
        /// own reminder and no other.
        @Test func notificationTimeFieldsWriteTheirOwnReminder() async throws {
            let defaults = try TestDefaults()
            defer { defaults.clean() }
            let service = NotificationService(center: FakeNotificationCenter(), defaults: defaults.defaults)
            let page = NotificationSettingsView()
                .environment(service)
                .environment(\.locale, Self.turkish)
            let mount = HostedLayout.Mount(page, size: CGSize(width: 700, height: 1200))
            defer { mount.close() }
            await mount.settle()
            let fields = Dictionary(
                mount.views(NSDatePicker.self).map { ($0.accessibilityLabel() ?? "", $0) },
                uniquingKeysWith: { first, _ in first })
            #expect(fields.keys.sorted() == ["Görev saati", "Günlük saati", "Hedef saati"])

            let goal = try #require(fields["Hedef saati"])
            #expect(Array(Self.clock(goal.dateValue).suffix(2)) == [20, 0])
            Self.stepUp(goal)
            #expect(service.preferences.goalTime == NotificationTime(hour: 21))
            #expect(service.preferences.taskTime == NotificationTime(hour: 9))
            #expect(service.preferences.journalTime == NotificationTime(hour: 21))

            let task = try #require(fields["Görev saati"])
            #expect(Array(Self.clock(task.dateValue).suffix(2)) == [9, 0])
            Self.stepUp(task)
            #expect(service.preferences.taskTime == NotificationTime(hour: 10))
            #expect(service.preferences.goalTime == NotificationTime(hour: 21))

            let journal = try #require(fields["Günlük saati"])
            #expect(Array(Self.clock(journal.dateValue).suffix(2)) == [21, 0])
            Self.stepUp(journal)
            #expect(service.preferences.journalTime == NotificationTime(hour: 22))
            #expect(service.preferences.taskTime == NotificationTime(hour: 10))
            #expect(service.preferences.goalTime == NotificationTime(hour: 21))

            // A reminder that is switched off cannot be retimed.
            service.preferences.goalsEnabled = false
            await mount.settle()
            #expect(!goal.isEnabled)
            #expect(task.isEnabled)
        }
    }

    // MARK: - Probes

    /// Two values a field can be bound to, so a test can change one from outside and rebind.
    @MainActor @Observable
    private final class PickerProbe {
        var first: Date
        var second: Date
        var usesSecond = false
        var isEnabled = true

        init(first: Date, second: Date) {
            self.first = first
            self.second = second
        }
    }

    private struct TimeFieldProbe: View {
        @Bindable var probe: PickerProbe
        let locale: Locale

        var body: some View {
            InkTimePicker(title: "Görev saati", selection: probe.usesSecond ? $probe.second : $probe.first)
                .disabled(!probe.isEnabled)
                .padding()
                .environment(\.locale, locale)
        }
    }

    private struct DateFieldProbe: View {
        @Bindable var probe: PickerProbe
        let timeZone: TimeZone

        var body: some View {
            TaskDateMacPicker(selected: probe.usesSecond ? $probe.second : $probe.first, timeZone: timeZone)
                .frame(width: 140, height: 24)
                .padding()
                .environment(\.locale, Locale(identifier: "tr_TR"))
        }
    }

    /// What the Settings pages read from their environment, on a temporary vault.
    @MainActor
    private struct SettingsFixture {
        let context: TaskTestContext
        let defaults: TestDefaults
        let shortcut: HotKeySettingsModel
        let lock: AppLockService
        let locale = Locale(identifier: "tr_TR")

        init() throws {
            context = try TaskTestContext()
            defaults = try TestDefaults()
            shortcut = HotKeySettingsModel(defaults: defaults.defaults, register: { _ in true })
            lock = AppLockService(
                defaults: defaults.defaults, makeContext: { FakeAppLockContext() }, now: { Date() })
        }

        func hosted(_ view: some View) -> some View {
            view
                .environment(NotificationService(center: FakeNotificationCenter(), defaults: defaults.defaults))
                .environment(CalendarService(source: IdleCalendarSource()))
                .environment(LocationService(source: FakeLocationSource(), defaults: defaults.defaults))
                .environment(lock)
                .environment(\.locale, locale)
        }

        /// The window title follows the app's language, not the environment's locale.
        func title(_ tab: MacSettingsTab) -> String { String(localized: tab.title) }

        func clean() {
            context.clean()
            defaults.clean()
        }
    }

    @MainActor
    private final class IdleCalendarSource: CalendarEventSource {
        var authorization = CalendarAuthorization.notDetermined
        var onChange: (@MainActor @Sendable () -> Void)?
        func requestFullAccess() async throws -> Bool { false }
        func events(from start: Date, to end: Date) async throws -> [CalendarEvent] { [] }
    }
#endif
