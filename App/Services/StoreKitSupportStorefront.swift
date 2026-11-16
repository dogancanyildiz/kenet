import StoreKit

#if os(macOS)
    import AppKit
#endif

/// StoreKit's answers turned into the app's own values. Pure, so unit tests cover every branch
/// that can be built without the store.
enum SupportStoreTranslation {
    static func isVerified<Signed>(_ result: VerificationResult<Signed>) -> Bool {
        switch result {
        case .verified: true
        case .unverified: false
        }
    }

    static func isRevoked(revocationDate: Date?) -> Bool { revocationDate != nil }

    /// `completed` builds the transaction of a successful purchase. A result this build does not
    /// know is read as "nothing bought": the update listener still finishes whatever arrives.
    static func purchase(
        _ result: Product.PurchaseResult,
        completed: (VerificationResult<Transaction>) -> SupportStoreTransaction
    ) -> SupportStorePurchase {
        switch result {
        case .success(let verification): .completed(completed(verification))
        case .userCancelled: .cancelled
        case .pending: .pending
        @unknown default: .cancelled
        }
    }

    static func distribution(_ environment: AppStore.Environment) -> SupportDistribution {
        switch environment {
        case .xcode: .xcode
        case .sandbox: .sandbox
        case .production: .production
        default: .unknown
        }
    }

    /// The environment is read only from a result whose signature checked out; `environment` is
    /// not called for an unverified one.
    static func distribution<Signed>(
        _ result: VerificationResult<Signed>, environment: (Signed) -> AppStore.Environment
    ) -> SupportDistribution {
        switch result {
        case .verified(let signed): distribution(environment(signed))
        case .unverified: .unverified
        }
    }

    /// A thrown cancellation is a cancellation. An error that rules a payment out is thrown as
    /// ``SupportStoreError/refused``; every other error is thrown as it came, and the service
    /// reads it as "not known whether the payment was taken".
    static func purchase(thrown error: any Error) throws -> SupportStorePurchase {
        if case StoreKitError.userCancelled = error { return .cancelled }
        if rulesOutPayment(error) { throw SupportStoreError.refused }
        throw error
    }

    /// Whether a thrown purchase error means the store took no payment. Only the errors that
    /// refuse the purchase before a payment are named; a network, system or unknown error, and
    /// any error this build does not know, leaves it open.
    static func rulesOutPayment(_ error: any Error) -> Bool {
        switch error {
        case let error as StoreKitError:
            switch error {
            case .notAvailableInStorefront, .notEntitled: true
            default: false
            }
        case let error as Product.PurchaseError:
            switch error {
            case .productUnavailable, .purchaseNotAllowed: true
            default: false
            }
        default: false
        }
    }
}

/// The App Store through StoreKit 2. Holds the loaded `Product` values; a purchase needs the
/// value, not the identifier.
@MainActor final class StoreKitSupportStorefront: SupportStorefront {
    private var loaded: [String: Product] = [:]

    func products(for ids: [String]) async throws -> [SupportStoreProduct] {
        let products = try await Product.products(for: ids)
        for product in products { loaded[product.id] = product }
        return products.map { SupportStoreProduct(id: $0.id, displayPrice: $0.displayPrice) }
    }

    func purchase(productID: String) async throws -> SupportStorePurchase {
        guard let product = loaded[productID] else { throw SupportStoreError.productNotLoaded }
        do {
            return SupportStoreTranslation.purchase(try await Self.purchase(product)) { Self.transaction($0) }
        } catch {
            return try SupportStoreTranslation.purchase(thrown: error)
        }
    }

    /// On Mac the payment sheet is tied to the window the tap came from (the Settings window);
    /// without one StoreKit picks a window itself.
    private static func purchase(_ product: Product) async throws -> Product.PurchaseResult {
        #if os(macOS)
            if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                return try await product.purchase(confirmIn: window)
            }
        #endif
        return try await product.purchase()
    }

    func transactionUpdates() -> AsyncStream<SupportStoreTransaction> {
        AsyncStream { continuation in
            let task = Task {
                for await result in Transaction.updates {
                    continuation.yield(Self.transaction(result))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func purchaseHistory() async -> [SupportHistoryEntry] {
        var entries: [SupportHistoryEntry] = []
        for await result in Transaction.all {
            let transaction = result.unsafePayloadValue
            entries.append(
                SupportHistoryEntry(
                    productID: transaction.productID, isVerified: SupportStoreTranslation.isVerified(result),
                    isRevoked: SupportStoreTranslation.isRevoked(revocationDate: transaction.revocationDate)))
        }
        return entries
    }

    /// An unverified transaction is still handed over, so it gets finished; the app does not
    /// thank for it.
    nonisolated private static func transaction(
        _ result: VerificationResult<Transaction>
    ) -> SupportStoreTransaction {
        let transaction = result.unsafePayloadValue
        return SupportStoreTransaction(
            productID: transaction.productID, isVerified: SupportStoreTranslation.isVerified(result),
            isRevoked: SupportStoreTranslation.isRevoked(revocationDate: transaction.revocationDate),
            finish: { await transaction.finish() })
    }
}

/// Whether this run earns the test team badge (``TesterBadgePolicy``). TestFlight builds run in
/// the sandbox environment and are not signed on a developer's machine; a build run from Xcode
/// reports `xcode` or is signed locally. A DEBUG build never asks the store.
enum SystemTesterProbe {
    @MainActor static func earns() async -> Bool {
        #if DEBUG || targetEnvironment(simulator)
            return false
        #else
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
            // Asked first: after 1.0.0 the store is never asked.
            guard TesterBadgePolicy.isPrerelease(version) else { return false }
            // No app transaction (no store account, offline, a copy the store never issued): no badge.
            guard let result = try? await AppTransaction.shared else { return false }
            return TesterBadgePolicy.earns(
                distribution: SupportStoreTranslation.distribution(result) { $0.environment },
                isLocalBuild: isLocalBuild, isSimulator: false, version: version)
        #endif
    }

    static var isLocalBuild: Bool {
        #if os(iOS)
            SupportSigningProfile.isLocalPhoneBuild(
                hasEmbeddedProfile: Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") != nil)
        #else
            SupportSigningProfile.isLocalMacBuild(
                profile: try? Data(
                    contentsOf: Bundle.main.bundleURL.appendingPathComponent("Contents/embedded.provisionprofile")))
        #endif
    }
}
