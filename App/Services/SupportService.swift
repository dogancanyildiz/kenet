import Foundation
import Observation

/// The three voluntary support amounts (docs/decisions.md, 2026-11-13). The product identifiers
/// are permanent: App Store Connect keeps an identifier forever, even after the product is deleted.
enum SupportTier: String, CaseIterable, Identifiable, Sendable {
    case small, medium, large

    var id: Self { self }

    var productID: String { "com.dogancanyildiz.kenet.support.\(rawValue)" }

    init?(productID: String) {
        guard let tier = Self.allCases.first(where: { $0.productID == productID }) else { return nil }
        self = tier
    }
}

/// A product as the store returned it. The price is the store's own localized text; the app never
/// writes a price itself.
struct SupportStoreProduct: Equatable, Sendable {
    let id: String
    let displayPrice: String
}

/// A transaction the store handed over. Every one must be finished, or the store delivers it
/// again on each launch.
struct SupportStoreTransaction: Sendable {
    let productID: String
    /// The store's signature checked out on this device.
    let isVerified: Bool
    /// Refunded or revoked by the store.
    var isRevoked = false
    let finish: @Sendable () async -> Void
}

enum SupportStorePurchase: Sendable {
    case completed(SupportStoreTransaction)
    case cancelled
    /// Waiting for an approval outside the app (Ask to Buy, bank confirmation). The transaction
    /// arrives later through ``SupportStorefront/transactionUpdates()``.
    case pending
}

enum SupportStoreError: Error, Equatable {
    /// A purchase was asked for a product the store did not return.
    case productNotLoaded
}

/// The store behind the support page. ``StoreKitSupportStorefront`` talks to the App Store; unit
/// tests use a fake.
@MainActor protocol SupportStorefront: AnyObject {
    func products(for ids: [String]) async throws -> [SupportStoreProduct]
    func purchase(productID: String) async throws -> SupportStorePurchase
    /// Transactions that arrive outside a purchase call: an approved pending purchase, a refund,
    /// one left unfinished by an earlier launch.
    func transactionUpdates() -> AsyncStream<SupportStoreTransaction>
}

struct SupportProduct: Equatable, Identifiable, Sendable {
    let tier: SupportTier
    let displayPrice: String

    var id: SupportTier { tier }
}

enum SupportProductsState: Equatable, Sendable {
    case loading
    case loaded([SupportProduct])
    /// The store returned nothing or could not be reached (offline, products not yet on sale).
    case unavailable
}

enum SupportPurchaseState: Equatable, Sendable {
    case idle
    case purchasing(SupportTier)
    case thanked
    case cancelled
    case pending
    /// The store took the payment but its signature did not check out on this device. Not an
    /// error to retry: a second purchase would charge again.
    case unverified
    case failed

    var isPurchasing: Bool {
        if case .purchasing = self { true } else { false }
    }
}

/// Voluntary support: three consumable purchases that unlock nothing. The app stores nothing about
/// them; it shows a thank-you and finishes the transaction.
@MainActor @Observable final class SupportService {
    private(set) var products: SupportProductsState = .loading
    private(set) var purchase: SupportPurchaseState = .idle

    @ObservationIgnored private let storefront: any SupportStorefront
    @ObservationIgnored private var isLoading = false
    @ObservationIgnored private var hasLoadedOnce = false
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    /// An approval that arrived while another purchase was under way; shown once that one ends.
    @ObservationIgnored private var hasDeferredThanks = false

    init(storefront: any SupportStorefront) {
        self.storefront = storefront
    }

    /// Starts listening for transactions that arrive outside a purchase call. Called once at
    /// launch, so an approval given while the app was closed is finished on the next start.
    func start() {
        guard updatesTask == nil else { return }
        let updates = storefront.transactionUpdates()
        updatesTask = Task { [weak self] in
            for await transaction in updates {
                await self?.receive(transaction)
            }
        }
    }

    func stop() {
        updatesTask?.cancel()
        updatesTask = nil
    }

    /// The page came on screen: products load once, and an old error, cancellation or pending
    /// note is cleared (a declined Ask to Buy sends nothing, so the note would never leave; a
    /// later approval still thanks through the update listener). A thank-you and the unverified
    /// note stay.
    func pageAppeared() async {
        if purchase == .failed || purchase == .cancelled || purchase == .pending { purchase = .idle }
        if case .loaded = products { return }
        await loadProducts()
    }

    func loadProducts() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        if hasLoadedOnce { products = .loading }
        hasLoadedOnce = true
        do {
            let found = try await storefront.products(for: SupportTier.allCases.map(\.productID))
            // Small to large by identifier; the store's order and the prices do not decide it.
            let ordered = SupportTier.allCases.compactMap { tier in
                found.first { $0.id == tier.productID }.map {
                    SupportProduct(tier: tier, displayPrice: $0.displayPrice)
                }
            }
            products = ordered.isEmpty ? .unavailable : .loaded(ordered)
        } catch {
            // The page left while loading: not the store's answer. The next appearance loads again.
            if error is CancellationError || Task.isCancelled {
                products = .loading
                hasLoadedOnce = false
            } else {
                products = .unavailable
            }
        }
    }

    /// One purchase at a time: a second tap while the store's sheet is up does nothing.
    func buy(_ tier: SupportTier) async {
        guard !purchase.isPurchasing else { return }
        purchase = .purchasing(tier)
        do {
            switch try await storefront.purchase(productID: tier.productID) {
            case .completed(let transaction):
                await transaction.finish()
                purchase = transaction.isVerified ? .thanked : .unverified
            case .cancelled:
                purchase = .cancelled
            case .pending:
                purchase = .pending
            }
        } catch {
            purchase = .failed
        }
        if hasDeferredThanks {
            hasDeferredThanks = false
            // The unverified note stays: it keeps the user from paying twice.
            if purchase != .unverified { purchase = .thanked }
        }
    }

    private func receive(_ transaction: SupportStoreTransaction) async {
        guard SupportTier(productID: transaction.productID) != nil else { return }
        await transaction.finish()
        guard transaction.isVerified, !transaction.isRevoked else { return }
        // A purchase under way reports its own result first; an approval that arrives meanwhile
        // is kept and shown when that purchase ends.
        if purchase.isPurchasing {
            hasDeferredThanks = true
        } else {
            purchase = .thanked
        }
    }
}
