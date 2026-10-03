import Foundation

/// A test host must never create or index the developer's real vault automatically.
enum AppLaunchPolicy {
    static func allowsAutomaticStart(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        environment["XCTestConfigurationFilePath"] == nil
            && environment["JOURNAL_NO_AUTOSTART"] == nil
            && !arguments.contains("JOURNAL_NO_AUTOSTART")
    }
}
