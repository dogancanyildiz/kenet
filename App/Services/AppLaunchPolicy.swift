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
