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

    /// A thrown cancellation is a cancellation; every other error stays an error.
    static func purchase(thrown error: any Error) throws -> SupportStorePurchase {
        if case StoreKitError.userCancelled = error { return .cancelled }
        throw error
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
/// the sandbox environment and carry no development profile; a build run from Xcode reports
/// `xcode` or carries one. A DEBUG build never asks the store.
enum SystemTesterProbe {
    @MainActor static func earns() async -> Bool {
        #if DEBUG || targetEnvironment(simulator)
            return false
        #else
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
            // Asked first: after 1.0.0 the store is never asked.
            guard TesterBadgePolicy.isPrerelease(version) else { return false }
            guard let result = try? await AppTransaction.shared else { return false }
            return TesterBadgePolicy.earns(
                distribution: SupportStoreTranslation.distribution(result.unsafePayloadValue.environment),
                hasDevelopmentProfile: hasDevelopmentProfile, isSimulator: false, version: version)
        #endif
    }

    /// iOS: App Store and TestFlight copies have no `embedded.mobileprovision`; development and
    /// ad hoc copies do. Mac copies from the store keep their profile (iCloud needs it), so the
    /// file says nothing there.
    static var hasDevelopmentProfile: Bool {
        #if os(iOS)
            Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") != nil
        #else
            false
        #endif
    }
}
