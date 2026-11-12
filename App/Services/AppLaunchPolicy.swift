import Foundation

/// A test host must never create or index the developer's real vault automatically.
enum AppLaunchPolicy {
    /// DEBUG-only path to a vault folder for XCUITest. When set, automatic indexing of the
    /// developer's real vault, app lock, notifications, and geofences stay off; `ContentView`
    /// opens this folder via `IndexStore.select` instead.
    static let uiTestVaultEnvironmentKey = "JOURNAL_UITEST_VAULT"

    /// DEBUG-only text placed in quick entry at launch, so UI tests do not depend on the
    /// simulator's keyboard or paste menu (both vary between iOS versions).
    static let uiTestQuickEntryTextKey = "JOURNAL_UITEST_QUICK_ENTRY_TEXT"

    static func uiTestQuickEntryText(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        #if DEBUG
            if uiTestVaultPath(environment: environment) != nil,
                let value = environment[uiTestQuickEntryTextKey], !value.isEmpty
            {
                return value
            }
        #endif
        return nil
    }

    /// DEBUG-only: `memory` puts an in-memory calendar with full access in place of EventKit.
    static let uiTestCalendarKey = "JOURNAL_UITEST_CALENDAR"

    @MainActor static func calendarSource(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> any CalendarEventSource {
        #if DEBUG
            if uiTestVaultPath(environment: environment) != nil, environment[uiTestCalendarKey] == "memory" {
                return InMemoryCalendarSource()
            }
        #endif
        return EventKitCalendarSource()
    }

    /// DEBUG-only wall clock for the screen tour: `HH:mm` freezes `clockNow` at that time of
    /// today, so the quick-entry time and the greeting match the simulator's 9:41 status bar.
    static let uiTestClockKey = "JOURNAL_UITEST_CLOCK"

    /// The app's `clockNow`: `Date()` unless a UI test with a vault asks for a frozen time.
    static func clockNow(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        calendar: Calendar = .current, now: Date = Date()
    ) -> @MainActor @Sendable () -> Date {
        frozenClock(environment: environment, calendar: calendar, now: now) ?? { Date() }
    }

    /// The frozen clock of a UI test, or nil. The app writes `clockNow` into the environment only
    /// when this is non-nil: a closure cannot be compared, so writing one on every body pass would
    /// invalidate every view that reads `clockNow`.
    static func frozenClock(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        calendar: Calendar = .current, now: Date = Date()
    ) -> (@MainActor @Sendable () -> Date)? {
        #if DEBUG
            if uiTestVaultPath(environment: environment) != nil,
                let value = environment[uiTestClockKey],
                let fixed = fixedTime(value, calendar: calendar, now: now)
            {
                return { fixed }
            }
        #endif
        return nil
    }

    /// `HH:mm` on the day of `now`; nil for anything else.
    static func fixedTime(_ value: String, calendar: Calendar, now: Date) -> Date? {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
            (0..<24).contains(hour), (0..<60).contains(minute)
        else { return nil }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now)
    }

    /// Days read the calendar on their own when the app starts normally, or in a UI test whose
    /// calendar is the in-memory one (never the developer's real calendar).
    static func allowsCalendarLoad(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        if allowsAutomaticStart(environment: environment) { return true }
        #if DEBUG
            return uiTestVaultPath(environment: environment) != nil && environment[uiTestCalendarKey] == "memory"
        #else
            return false
        #endif
    }

    static func uiTestVaultPath(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> String? {
        #if DEBUG
            if let value = environment[uiTestVaultEnvironmentKey], !value.isEmpty { return value }
            let prefix = uiTestVaultEnvironmentKey + "="
            for argument in arguments where argument.hasPrefix(prefix) {
                let path = String(argument.dropFirst(prefix.count))
                if !path.isEmpty { return path }
            }
        #endif
        return nil
    }

    #if DEBUG
        /// Folder name, under the app's caches, of the copy a UI test vault is opened from. Only
        /// DEBUG builds open a UI test vault (``uiTestVaultPath(environment:arguments:)``). Each
        /// launch names its own copy, so a test reads the very files the app wrote.
        static let uiTestVaultCopyKey = "JOURNAL_UITEST_VAULT_COPY"
        static let uiTestVaultCopyDefaultName = "UITestVault"

        /// The copy's folder name: the test's name when it is a plain `UITestVault-…` name (letters,
        /// digits, `-`, `_`), else ``uiTestVaultCopyDefaultName``.
        static func uiTestVaultCopyName(
            environment: [String: String] = ProcessInfo.processInfo.environment
        ) -> String {
            guard let name = environment[uiTestVaultCopyKey], name.hasPrefix(uiTestVaultCopyDefaultName + "-"),
                name.unicodeScalars.allSatisfy({
                    $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "-_".unicodeScalars.contains($0))
                })
            else { return uiTestVaultCopyDefaultName }
            return name
        }
    #endif

    static func allowsAutomaticStart(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        uiTestVaultPath(environment: environment, arguments: arguments) == nil
            && environment["XCTestConfigurationFilePath"] == nil
            && environment["JOURNAL_NO_AUTOSTART"] == nil
            && !arguments.contains("JOURNAL_NO_AUTOSTART")
    }
}
