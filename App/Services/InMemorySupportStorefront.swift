import Foundation

/// A store in memory: snapshot tests and DEBUG UI test launches use it in place of the App Store.
/// Prices are fixed texts; nothing is charged.
@MainActor final class InMemorySupportStorefront: SupportStorefront {
    enum PurchaseOutcome: String, Sendable {
        case verified, unverified, cancelled, pending, failed
    }

    struct Unavailable: Error {}

    /// Nil: the store cannot be reached.
    var catalog: [SupportStoreProduct]?
    var purchaseOutcome: PurchaseOutcome

    static let sampleCatalog = [
        SupportStoreProduct(id: SupportTier.small.productID, displayPrice: "₺49,00"),
        SupportStoreProduct(id: SupportTier.medium.productID, displayPrice: "₺99,00"),
        SupportStoreProduct(id: SupportTier.large.productID, displayPrice: "₺249,00"),
    ]

    init(catalog: [SupportStoreProduct]? = sampleCatalog, purchaseOutcome: PurchaseOutcome = .verified) {
        self.catalog = catalog
        self.purchaseOutcome = purchaseOutcome
    }

    func products(for ids: [String]) async throws -> [SupportStoreProduct] {
        guard let catalog else { throw Unavailable() }
        return catalog.filter { ids.contains($0.id) }
    }

    func purchase(productID: String) async throws -> SupportStorePurchase {
        switch purchaseOutcome {
        case .verified, .unverified:
            return .completed(
                SupportStoreTransaction(
                    productID: productID, isVerified: purchaseOutcome == .verified, finish: {}))
        case .cancelled: return .cancelled
        case .pending: return .pending
        case .failed: throw Unavailable()
        }
    }

    func transactionUpdates() -> AsyncStream<SupportStoreTransaction> {
        AsyncStream { _ in }
    }
}
