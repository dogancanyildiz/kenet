import Foundation
import StoreKit
import Testing

@testable import Kenet

/// Counts `finish()` calls from the `@Sendable` closure a transaction carries.
private final class FinishCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int { lock.withLock { value } }

    func increment() { lock.withLock { value += 1 } }
}

@MainActor private final class FakeSupportStorefront: SupportStorefront {
    enum Failure: Error { case offline, declined }

    var catalog: [SupportStoreProduct] = [
        // Deliberately out of order, and the cheapest price on the largest tier.
        SupportStoreProduct(id: SupportTier.large.productID, displayPrice: "₺1,00"),
        SupportStoreProduct(id: SupportTier.small.productID, displayPrice: "₺249,00"),
        SupportStoreProduct(id: SupportTier.medium.productID, displayPrice: "₺99,00"),
    ]
    var productsError: (any Error)?
    var purchaseResult: Result<SupportStorePurchase, Failure> = .success(.cancelled)
    /// When set, the next purchase waits here until the test resumes it. Only that one: a later
    /// purchase returns at once, so a test whose guard is gone fails on its counts and does not hang.
    var holdsNextPurchase = false
    private(set) var updateStreams = 0
    private(set) var productRequests: [[String]] = []
    private(set) var purchaseRequests: [String] = []
    private var held: [CheckedContinuation<Void, Never>] = []
    private var updates: AsyncStream<SupportStoreTransaction>.Continuation?
    let finishes = FinishCounter()

    func products(for ids: [String]) async throws -> [SupportStoreProduct] {
        productRequests.append(ids)
        if let productsError { throw productsError }
        return catalog
    }

    func purchase(productID: String) async throws -> SupportStorePurchase {
        purchaseRequests.append(productID)
        if holdsNextPurchase {
            holdsNextPurchase = false
            await withCheckedContinuation { held.append($0) }
        }
        return try purchaseResult.get()
    }

    func transactionUpdates() -> AsyncStream<SupportStoreTransaction> {
        updateStreams += 1
        return AsyncStream { updates = $0 }
    }

    func releasePurchases() {
        for continuation in held { continuation.resume() }
        held = []
    }

    func transaction(
        _ tier: SupportTier = .small, verified: Bool = true, revoked: Bool = false
    ) -> SupportStoreTransaction {
        transaction(productID: tier.productID, verified: verified, revoked: revoked)
    }

    func transaction(productID: String, verified: Bool = true, revoked: Bool = false) -> SupportStoreTransaction {
        let finishes = finishes
        return SupportStoreTransaction(
            productID: productID, isVerified: verified, isRevoked: revoked, finish: { finishes.increment() })
    }

    func send(_ transaction: SupportStoreTransaction) { updates?.yield(transaction) }
}

@MainActor @Suite(.timeLimit(.minutes(1))) struct SupportServiceTests {
    private let store = FakeSupportStorefront()

    /// Lets the update listener and suspended purchases run.
    private func settle(until condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func productIdentifiersArePermanent() {
        #expect(
            SupportTier.allCases.map(\.productID) == [
                "com.dogancanyildiz.kenet.support.small",
                "com.dogancanyildiz.kenet.support.medium",
                "com.dogancanyildiz.kenet.support.large",
            ])
        #expect(SupportTier(productID: "com.dogancanyildiz.kenet.support.medium") == .medium)
        #expect(SupportTier(productID: "com.dogancanyildiz.kenet.other") == nil)
    }

    @Test func productsLoadInTierOrderNotStoreOrPriceOrder() async {
        let service = SupportService(storefront: store)
        #expect(service.products == .loading)
        await service.pageAppeared()
        #expect(store.productRequests == [SupportTier.allCases.map(\.productID)])
        #expect(
            service.products
                == .loaded([
                    SupportProduct(tier: .small, displayPrice: "₺249,00"),
                    SupportProduct(tier: .medium, displayPrice: "₺99,00"),
                    SupportProduct(tier: .large, displayPrice: "₺1,00"),
                ]))
    }

    @Test func loadedProductsAreNotRequestedAgain() async {
        let service = SupportService(storefront: store)
        await service.pageAppeared()
        await service.pageAppeared()
        #expect(store.productRequests.count == 1)
    }

    @Test func unknownAndMissingProductsAreLeftOut() async {
        store.catalog = [
            SupportStoreProduct(id: "com.dogancanyildiz.kenet.other", displayPrice: "₺5,00"),
            SupportStoreProduct(id: SupportTier.large.productID, displayPrice: "₺249,00"),
        ]
        let service = SupportService(storefront: store)
        await service.loadProducts()
        #expect(service.products == .loaded([SupportProduct(tier: .large, displayPrice: "₺249,00")]))
    }

    @Test func emptyStoreAnswerIsUnavailable() async {
        store.catalog = []
        let service = SupportService(storefront: store)
        await service.loadProducts()
        #expect(service.products == .unavailable)
    }

    @Test func failedLoadIsUnavailableAndRetryLoads() async {
        store.productsError = FakeSupportStorefront.Failure.offline
        let service = SupportService(storefront: store)
        await service.pageAppeared()
        #expect(service.products == .unavailable)
        store.productsError = nil
        await service.loadProducts()
        #expect(service.products.loadedTiers == SupportTier.allCases)
        #expect(store.productRequests.count == 2)
    }

    @Test func verifiedPurchaseIsFinishedAndThanked() async {
        store.purchaseResult = .success(.completed(store.transaction(.medium)))
        let service = SupportService(storefront: store)
        await service.buy(.medium)
        #expect(store.purchaseRequests == [SupportTier.medium.productID])
        #expect(store.finishes.count == 1)
        #expect(service.purchase == .thanked)
    }

    @Test func unverifiedPurchaseIsFinishedAndNeitherThankedNorAnError() async {
        store.purchaseResult = .success(.completed(store.transaction(.small, verified: false)))
        let service = SupportService(storefront: store)
        await service.buy(.small)
        #expect(store.finishes.count == 1)
        // The payment went through: the state must not invite a second purchase.
        #expect(service.purchase == .unverified)
        await service.pageAppeared()
        #expect(service.purchase == .unverified)
    }

    @Test func cancelledPurchaseFinishesNothing() async {
        store.purchaseResult = .success(.cancelled)
        let service = SupportService(storefront: store)
        await service.buy(.small)
        #expect(service.purchase == .cancelled)
        #expect(store.finishes.count == 0)
    }

    @Test func pendingPurchaseWaitsAndTheLaterApprovalThanks() async {
        store.purchaseResult = .success(.pending)
        let service = SupportService(storefront: store)
        service.start()
        await service.buy(.large)
        #expect(service.purchase == .pending)
        #expect(store.finishes.count == 0)

        store.send(store.transaction(.large))
        await settle { service.purchase == .thanked }
        #expect(service.purchase == .thanked)
        #expect(store.finishes.count == 1)
        service.stop()
    }

    @Test func thrownPurchaseErrorIsFailed() async {
        store.purchaseResult = .failure(.declined)
        let service = SupportService(storefront: store)
        await service.buy(.small)
        #expect(service.purchase == .failed)
        #expect(store.finishes.count == 0)
    }

    @Test func secondTapWhilePurchasingBuysOnce() async {
        store.holdsNextPurchase = true
        store.purchaseResult = .success(.completed(store.transaction(.small)))
        let service = SupportService(storefront: store)
        let first = Task { await service.buy(.small) }
        await settle { store.purchaseRequests.count == 1 }
        #expect(service.purchase == .purchasing(.small))

        await service.buy(.small)
        await service.buy(.large)
        #expect(store.purchaseRequests == [SupportTier.small.productID])
        #expect(service.purchase == .purchasing(.small))

        store.releasePurchases()
        await first.value
        #expect(service.purchase == .thanked)
        #expect(store.finishes.count == 1)
    }

    @Test func approvalDuringAnotherPurchaseWaitsThenThanks() async {
        store.holdsNextPurchase = true
        store.purchaseResult = .success(.cancelled)
        let service = SupportService(storefront: store)
        service.start()
        let buying = Task { await service.buy(.small) }
        await settle { store.purchaseRequests.count == 1 }

        store.send(store.transaction(.large))
        await settle { store.finishes.count == 1 }
        #expect(store.finishes.count == 1)
        // The purchase under way keeps the row busy; the approval does not cut in.
        #expect(service.purchase == .purchasing(.small))

        store.releasePurchases()
        await buying.value
        #expect(service.purchase == .thanked)
        service.stop()
    }

    @Test func approvalDuringAnUnverifiedPurchaseKeepsTheUnverifiedNote() async {
        store.holdsNextPurchase = true
        store.purchaseResult = .success(.completed(store.transaction(.small, verified: false)))
        let service = SupportService(storefront: store)
        service.start()
        let buying = Task { await service.buy(.small) }
        await settle { store.purchaseRequests.count == 1 }
        store.send(store.transaction(.large))
        await settle { store.finishes.count == 1 }
        store.releasePurchases()
        await buying.value
        #expect(service.purchase == .unverified)
        service.stop()
    }

    @Test func startingTwiceListensOnce() async {
        let service = SupportService(storefront: store)
        service.start()
        service.start()
        #expect(store.updateStreams == 1)
        store.send(store.transaction(.small))
        await settle { store.finishes.count == 1 }
        try? await Task.sleep(for: .milliseconds(30))
        #expect(store.finishes.count == 1)
        service.stop()
        service.start()
        #expect(store.updateStreams == 2)
        service.stop()
    }

    @Test func cancelledLoadIsNotUnavailableAndTheNextAppearanceLoads() async {
        store.productsError = CancellationError()
        let service = SupportService(storefront: store)
        await service.pageAppeared()
        #expect(service.products == .loading)
        store.productsError = nil
        await service.pageAppeared()
        #expect(service.products.loadedTiers == SupportTier.allCases)
        #expect(store.productRequests.count == 2)
    }

    @Test func reopeningThePageClearsPendingAndALaterApprovalStillThanks() async {
        store.purchaseResult = .success(.pending)
        let service = SupportService(storefront: store)
        service.start()
        await service.buy(.medium)
        #expect(service.purchase == .pending)
        await service.pageAppeared()
        #expect(service.purchase == .idle)
        store.send(store.transaction(.medium))
        await settle { service.purchase == .thanked }
        #expect(service.purchase == .thanked)
        service.stop()
    }

    @Test func aNewPurchaseIsAllowedAfterTheFirstEnds() async {
        store.purchaseResult = .success(.completed(store.transaction(.small)))
        let service = SupportService(storefront: store)
        await service.buy(.small)
        await service.buy(.small)
        #expect(store.purchaseRequests.count == 2)
        #expect(store.finishes.count == 2)
    }

    @Test func revokedUnverifiedAndForeignUpdatesDoNotThank() async {
        let service = SupportService(storefront: store)
        service.start()
        store.send(store.transaction(.small, revoked: true))
        store.send(store.transaction(.small, verified: false))
        store.send(store.transaction(productID: "com.dogancanyildiz.kenet.other"))
        // Both support transactions are finished; the foreign one is not this service's to finish.
        await settle { store.finishes.count == 2 }
        try? await Task.sleep(for: .milliseconds(30))
        #expect(store.finishes.count == 2)
        #expect(service.purchase == .idle)
        service.stop()
    }

    @Test func reopeningThePageClearsErrorAndCancelButKeepsThanks() async {
        let service = SupportService(storefront: store)
        store.purchaseResult = .failure(.declined)
        await service.buy(.small)
        await service.pageAppeared()
        #expect(service.purchase == .idle)

        store.purchaseResult = .success(.cancelled)
        await service.buy(.small)
        await service.pageAppeared()
        #expect(service.purchase == .idle)

        store.purchaseResult = .success(.completed(store.transaction(.small)))
        await service.buy(.small)
        await service.pageAppeared()
        #expect(service.purchase == .thanked)
    }
}

extension SupportProductsState {
    fileprivate var loadedTiers: [SupportTier] {
        if case .loaded(let products) = self { products.map(\.tier) } else { [] }
    }
}

/// StoreKit's answers turned into the app's values (``SupportStoreTranslation``). A successful
/// purchase result cannot be built without the store; the unit covers every other branch.
@MainActor @Suite(.timeLimit(.minutes(1))) struct SupportStoreTranslationTests {
    private static let marker = SupportStoreTransaction(productID: "marker", isVerified: true, finish: {})

    @Test func verificationDecidesIsVerified() {
        #expect(SupportStoreTranslation.isVerified(VerificationResult<Int>.verified(1)))
        #expect(!SupportStoreTranslation.isVerified(VerificationResult<Int>.unverified(1, .invalidSignature)))
    }

    @Test func revocationDateDecidesIsRevoked() {
        #expect(!SupportStoreTranslation.isRevoked(revocationDate: nil))
        #expect(SupportStoreTranslation.isRevoked(revocationDate: Date(timeIntervalSince1970: 0)))
    }

    @Test func cancelledAndPendingResultsBuildNoTransaction() {
        var built = 0
        let cancelled = SupportStoreTranslation.purchase(.userCancelled) { _ in
            built += 1
            return Self.marker
        }
        let pending = SupportStoreTranslation.purchase(.pending) { _ in
            built += 1
            return Self.marker
        }
        #expect(cancelled.kind == "cancelled")
        #expect(pending.kind == "pending")
        #expect(built == 0)
    }

    @Test func thrownCancellationIsACancellationAndOtherErrorsStayErrors() throws {
        #expect(try SupportStoreTranslation.purchase(thrown: StoreKitError.userCancelled).kind == "cancelled")
        #expect(throws: StoreKitError.self) {
            try SupportStoreTranslation.purchase(thrown: StoreKitError.notEntitled)
        }
        #expect(throws: SupportStoreError.self) {
            try SupportStoreTranslation.purchase(thrown: SupportStoreError.productNotLoaded)
        }
    }
}

extension SupportStorePurchase {
    fileprivate var kind: String {
        switch self {
        case .completed: "completed"
        case .cancelled: "cancelled"
        case .pending: "pending"
        }
    }
}
