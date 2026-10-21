import Foundation

protocol UbiquityContainerProviding: Sendable {
    func containerURL() async -> URL?
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
}

struct FakeUbiquityContainer: UbiquityContainerProviding {
    let url: URL?
    func containerURL() async -> URL? { url }
}
