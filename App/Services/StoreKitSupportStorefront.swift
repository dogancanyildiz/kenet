import StoreKit

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
            switch try await product.purchase() {
            case .success(let result): return .completed(Self.transaction(result))
            case .userCancelled: return .cancelled
            case .pending: return .pending
            @unknown default: return .cancelled
            }
        } catch StoreKitError.userCancelled {
            return .cancelled
        }
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

    /// An unverified transaction is still handed over, so it gets finished; the app does not
    /// thank for it.
    nonisolated private static func transaction(
        _ result: VerificationResult<Transaction>
    ) -> SupportStoreTransaction {
        let transaction = result.unsafePayloadValue
        let isVerified: Bool
        switch result {
        case .verified: isVerified = true
        case .unverified: isVerified = false
        }
        return SupportStoreTransaction(
            productID: transaction.productID, isVerified: isVerified,
            isRevoked: transaction.revocationDate != nil,
            finish: { await transaction.finish() })
    }
}
