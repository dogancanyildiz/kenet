import Foundation

/// Asks iCloud to bring originals that are only placeholders on this device (`.X.icloud`).
/// The bytes arrive later; the vault watcher and the next refresh index them.
protocol CloudDownloading: Sendable {
    /// Requests each item once, without waiting for its bytes, and returns how many requests the
    /// system refused.
    func startDownloading(_ items: [URL]) async -> Int
}

/// The system request, off the main actor: it may block on iCloud's daemon.
struct SystemCloudDownloader: CloudDownloading {
    func startDownloading(_ items: [URL]) async -> Int {
        await Task.detached {
            var refused = 0
            for item in items {
                do { try FileManager.default.startDownloadingUbiquitousItem(at: item) } catch { refused += 1 }
            }
            return refused
        }.value
    }

    /// The system downloader in the app; outside it (tests, previews) nothing reaches iCloud.
    static func forLaunch(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> any CloudDownloading {
        if AppLaunchPolicy.allowsAutomaticStart(environment: environment, arguments: arguments) {
            return SystemCloudDownloader()
        }
        return NoCloudDownloader()
    }
}

/// Requests nothing; every request counts as accepted.
struct NoCloudDownloader: CloudDownloading {
    func startDownloading(_ items: [URL]) async -> Int { 0 }
}
