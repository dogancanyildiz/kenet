import Foundation
import VaultIndex

protocol UbiquityContainerProviding: Sendable {
    func containerURL() async -> URL?
    /// Asks iCloud to download `items`, then waits up to `timeout` for a coordinated read of `file`.
    /// Returns whether `file` is on disk afterwards.
    func download(_ items: [URL], waitingFor file: URL, timeout: Duration) async throws -> Bool
}

extension UbiquityContainerProviding {
    /// Fakes never reach iCloud: a file is ready only if it is already on disk.
    func download(_ items: [URL], waitingFor file: URL, timeout: Duration) async throws -> Bool {
        FileManager.default.fileExists(atPath: file.path)
    }
}

/// Both potentially blocking system calls run outside the main actor.
struct SystemUbiquityContainer: UbiquityContainerProviding {
    var hasIdentity: @Sendable () -> Bool = { FileManager.default.ubiquityIdentityToken != nil }
    var lookup: @Sendable () -> URL? = {
        FileManager.default.url(forUbiquityContainerIdentifier: AppIdentifiers.iCloudContainer)
    }

    func containerURL() async -> URL? {
        await Task.detached {
            guard hasIdentity() else { return nil }
            return lookup()
        }.value
    }

    func download(_ items: [URL], waitingFor file: URL, timeout: Duration) async throws -> Bool {
        for item in items { try FileManager.default.startDownloadingUbiquitousItem(at: item) }
        // A coordinated read is granted only once iCloud has the file's bytes on disk.
        let coordinator = CancellableCoordinator()
        let timer = Task {
            guard (try? await Task.sleep(for: timeout)) != nil else { return }
            coordinator.cancel()
        }
        defer { timer.cancel() }
        let granted = await coordinator.read(file)
        return granted && FileManager.default.fileExists(atPath: file.path)
    }
}

/// `NSFileCoordinator.cancel()` may be called from any thread.
private final class CancellableCoordinator: @unchecked Sendable {
    private let coordinator = NSFileCoordinator()
    private let queue = OperationQueue()

    func read(_ url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            coordinator.coordinate(with: [.readingIntent(with: url)], queue: queue) { error in
                continuation.resume(returning: error == nil)
            }
        }
    }

    func cancel() { coordinator.cancel() }
}

struct FakeUbiquityContainer: UbiquityContainerProviding {
    let url: URL?
    func containerURL() async -> URL? { url }
}

/// How a folder in the container shows itself as a vault: by its settings file `.app/vault.json`.
enum CloudVaultMarker: Equatable {
    case present
    /// Only iCloud's placeholder `.app/.vault.json.icloud` is on this device so far.
    case awaitingDownload
    case absent

    static func at(_ root: URL) -> Self {
        let app = root.appendingPathComponent(".app", isDirectory: true)
        if FileManager.default.fileExists(atPath: app.appendingPathComponent("vault.json").path) { return .present }
        let placeholder = PlaceholderName.placeholderName(for: "vault.json")
        if FileManager.default.fileExists(atPath: app.appendingPathComponent(placeholder).path) {
            return .awaitingDownload
        }
        return .absent
    }
}

/// The container's vault is still downloading; nothing was created, moved or registered.
enum CloudVaultError: LocalizedError {
    case downloading

    var errorDescription: String? {
        String(localized: "Kasa iCloud’dan iniyor. Biraz sonra yeniden dene.")
    }
}
