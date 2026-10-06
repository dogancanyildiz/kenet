import Foundation

/// A test host must never create or index the developer's real vault automatically.
enum AppLaunchPolicy {
    /// DEBUG-only path to a vault folder for XCUITest. When set, automatic indexing of the
    /// developer's real vault, app lock, notifications, and geofences stay off; `ContentView`
    /// opens this folder via `IndexStore.select` instead.
    static let uiTestVaultEnvironmentKey = "JOURNAL_UITEST_VAULT"

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
