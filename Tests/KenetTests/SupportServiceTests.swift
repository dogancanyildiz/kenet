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
    var purchaseResult: Result<SupportStorePurchase, any Error> = .success(.cancelled)
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

    var history: [SupportHistoryEntry] = []
    /// When set, the next history read waits until the test resumes it, and then answers with
    /// what the history was when the read began (a stale read).
    var holdsNextHistory = false
    private(set) var historyRequests = 0
    private var heldHistory: [CheckedContinuation<Void, Never>] = []

    func purchaseHistory() async -> [SupportHistoryEntry] {
        historyRequests += 1
        let read = history
        if holdsNextHistory {
            holdsNextHistory = false
            await withCheckedContinuation { heldHistory.append($0) }
        }
        return read
    }

    func releaseHistory() {
        for continuation in heldHistory { continuation.resume() }
        heldHistory = []
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

    /// The store refused before any payment: the page may invite a retry.
    @Test(arguments: [SupportStoreError.refused, .productNotLoaded])
    func anErrorThatRulesOutPaymentIsFailed(_ error: SupportStoreError) async {
        store.purchaseResult = .failure(error)
        let service = SupportService(storefront: store)
        await service.buy(.small)
        #expect(service.purchase == .failed)
        #expect(store.finishes.count == 0)
    }

    /// Every other error leaves the payment open: the state must not invite a second purchase.
    @Test func anyOtherThrownErrorIsUnconfirmedAndNotFailed() async {
        let errors: [any Error] = [
            FakeSupportStorefront.Failure.offline, URLError(.networkConnectionLost), CancellationError(),
            StoreKitError.unknown,
        ]
        for error in errors {
            store.purchaseResult = .failure(error)
            let service = SupportService(storefront: store)
            await service.buy(.small)
            #expect(service.purchase == .unconfirmed)
            #expect(service.supporterLevel == nil)
        }
        #expect(store.finishes.count == 0)
    }

    /// The purchase call threw, but the payment went through and the transaction arrives through
    /// the update listener: it is finished, thanked and the note leaves.
    @Test(arguments: [true, false])
    func aTransactionThatArrivesAfterAThrownErrorIsFinishedAndThanked(refused: Bool) async {
        store.purchaseResult = .failure(refused ? SupportStoreError.refused : FakeSupportStorefront.Failure.offline)
        let service = SupportService(storefront: store)
        service.start()
        await service.buy(.medium)
        #expect(service.purchase == (refused ? .failed : .unconfirmed))
        #expect(store.finishes.count == 0)

        store.send(store.transaction(.medium))
        await settle { service.purchase == .thanked }
        #expect(service.purchase == .thanked)
        #expect(service.supporterLevel == .medium)
        #expect(store.finishes.count == 1)
        service.stop()
    }

    @Test func reopeningThePageKeepsTheUnconfirmedNoteAndALaterTransactionStillThanks() async {
        store.purchaseResult = .failure(FakeSupportStorefront.Failure.offline)
        let service = SupportService(storefront: store)
        service.start()
        await service.buy(.small)
        await service.pageAppeared()
        #expect(service.purchase == .unconfirmed)

        store.send(store.transaction(.small))
        await settle { service.purchase == .thanked }
        #expect(service.purchase == .thanked)
        service.stop()
    }

    /// An unverified or revoked arrival is no proof of this payment: the note stays.
    @Test func anUnverifiedOrRevokedArrivalKeepsTheUnconfirmedNote() async {
        store.purchaseResult = .failure(FakeSupportStorefront.Failure.offline)
        let service = SupportService(storefront: store)
        service.start()
        await service.buy(.small)
        store.send(store.transaction(.small, verified: false))
        store.send(store.transaction(.small, revoked: true))
        await settle { store.finishes.count == 2 }
        #expect(store.finishes.count == 2)
        #expect(service.purchase == .unconfirmed)
        service.stop()
    }

    @Test func aNewPurchaseIsAllowedAfterAnUnconfirmedOne() async {
        store.purchaseResult = .failure(FakeSupportStorefront.Failure.offline)
        let service = SupportService(storefront: store)
        await service.buy(.small)
        store.purchaseResult = .success(.completed(store.transaction(.small)))
        await service.buy(.small)
        #expect(store.purchaseRequests.count == 2)
        #expect(service.purchase == .thanked)
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

        // The kept approval is used once: the next purchase reports its own result.
        await service.buy(.small)
        #expect(service.purchase == .cancelled)
        service.stop()
    }

    /// The approval is a verified payment: the thank-you takes the place of the unconfirmed note.
    /// Neither text invites a second purchase.
    @Test func approvalDuringAnUnconfirmedPurchaseThanks() async {
        store.holdsNextPurchase = true
        store.purchaseResult = .failure(FakeSupportStorefront.Failure.offline)
        let service = SupportService(storefront: store)
        service.start()
        let buying = Task { await service.buy(.small) }
        await settle { store.purchaseRequests.count == 1 }
        store.send(store.transaction(.large))
        await settle { store.finishes.count == 1 }
        #expect(service.purchase == .purchasing(.small))
        store.releasePurchases()
        await buying.value
        #expect(service.purchase == .thanked)
        #expect(service.supporterLevel == .large)
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
        store.purchaseResult = .failure(SupportStoreError.refused)
        await service.buy(.small)
        #expect(service.purchase == .failed)
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

@MainActor private final class TesterProbe {
    var earns = false
    private(set) var asked = 0

    func ask() -> Bool {
        asked += 1
        return earns
    }
}

/// The badges: the supporter level comes from the purchase history, the test team badge from the
/// kind of build that ran.
@MainActor @Suite(.timeLimit(.minutes(1))) struct SupportBadgeTests {
    private let store = FakeSupportStorefront()

    private func entry(_ tier: SupportTier, verified: Bool = true, revoked: Bool = false) -> SupportHistoryEntry {
        SupportHistoryEntry(productID: tier.productID, isVerified: verified, isRevoked: revoked)
    }

    @Test func tiersAreOrderedSmallToLarge() {
        #expect(SupportTier.small < .medium && SupportTier.medium < .large)
        #expect(SupportTier.allCases.max() == .large)
    }

    @Test func levelIsTheHighestTierInTheHistory() {
        #expect(SupporterLevel.level(history: []) == nil)
        #expect(SupporterLevel.level(history: [entry(.small)]) == .small)
        #expect(SupporterLevel.level(history: [entry(.medium), entry(.small), entry(.small)]) == .medium)
        #expect(SupporterLevel.level(history: [entry(.small), entry(.large), entry(.medium)]) == .large)
    }

    @Test func revokedUnverifiedAndForeignEntriesDoNotCount() {
        let history = [
            entry(.large, revoked: true), entry(.medium, verified: false), entry(.small),
            SupportHistoryEntry(productID: "com.dogancanyildiz.kenet.other"),
        ]
        #expect(SupporterLevel.level(history: history) == .small)
        #expect(SupporterLevel.level(history: [entry(.large, revoked: true)]) == nil)
    }

    @Test func refreshReadsTheLevelFromTheHistory() async {
        let service = SupportService(storefront: store)
        #expect(service.supporterLevel == nil)
        store.history = [entry(.medium)]
        await service.refreshBadges()
        #expect(service.supporterLevel == .medium)
        store.history = [entry(.medium), entry(.large)]
        await service.refreshBadges()
        #expect(service.supporterLevel == .large)
        // A read never lowers the level: only a refund does.
        store.history = []
        await service.refreshBadges()
        #expect(service.supporterLevel == .large)
    }

    @Test func aStaleHistoryReadDoesNotTakeAwayTheBadgeOfAPurchaseThatEndedMeanwhile() async {
        let service = SupportService(storefront: store)
        store.holdsNextHistory = true
        let reading = Task { await service.refreshBadges() }
        for _ in 0..<200 where store.historyRequests == 0 { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(store.historyRequests == 1)

        store.purchaseResult = .success(.completed(store.transaction(.medium)))
        await service.buy(.medium)
        #expect(service.supporterLevel == .medium)
        #expect(service.purchase == .thanked)

        // The read began before the purchase: it answers with an empty history.
        store.releaseHistory()
        await reading.value
        #expect(service.supporterLevel == .medium)
        #expect(service.purchase == .thanked)
    }

    @Test func aVerifiedPurchaseRaisesTheLevelAndNeverLowersIt() async {
        let service = SupportService(storefront: store)
        store.purchaseResult = .success(.completed(store.transaction(.medium)))
        await service.buy(.medium)
        #expect(service.supporterLevel == .medium)
        store.purchaseResult = .success(.completed(store.transaction(.small)))
        await service.buy(.small)
        #expect(service.supporterLevel == .medium)
        store.purchaseResult = .success(.completed(store.transaction(.large)))
        await service.buy(.large)
        #expect(service.supporterLevel == .large)
    }

    @Test func unverifiedCancelledPendingAndFailedPurchasesGiveNoBadge() async {
        let service = SupportService(storefront: store)
        let results: [Result<SupportStorePurchase, any Error>] = [
            .success(.completed(store.transaction(.large, verified: false))), .success(.cancelled),
            .success(.pending), .failure(SupportStoreError.refused),
            .failure(FakeSupportStorefront.Failure.offline),
        ]
        for result in results {
            store.purchaseResult = result
            await service.buy(.large)
            #expect(service.supporterLevel == nil)
        }
    }

    @Test func anApprovalFromTheListenerRaisesTheLevelAndARefundRereadsTheHistory() async {
        let service = SupportService(storefront: store)
        service.start()
        store.send(store.transaction(.large))
        for _ in 0..<200 where service.supporterLevel != .large { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(service.supporterLevel == .large)

        store.history = [entry(.large, revoked: true), entry(.small)]
        store.send(store.transaction(.large, revoked: true))
        for _ in 0..<200 where service.supporterLevel != .small { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(service.supporterLevel == .small)
        service.stop()
    }

    private func earns(
        _ distribution: SupportDistribution = .sandbox, local: Bool = false, simulator: Bool = false,
        version: String = "0.17.0"
    ) -> Bool {
        TesterBadgePolicy.earns(
            distribution: distribution, isLocalBuild: local, isSimulator: simulator, version: version)
    }

    @Test func testerBadgeNeedsATestFlightBuildBeforeLaunch() {
        #expect(earns())
        #expect(earns(version: "0.9"))
    }

    @Test func testerBadgeNeedsTheSandboxEnvironment() {
        #expect(!earns(.production))
        #expect(!earns(.unknown))
    }

    @Test func testerBadgeIsNotGivenInTheXcodeEnvironment() {
        #expect(!earns(.xcode))
    }

    /// What TestFlight returns is not measured: an unverified sandbox answer must not cost a
    /// real tester the badge.
    @Test func testerBadgeIsGivenForAnUnverifiedSandboxAppTransaction() {
        #expect(earns(.sandboxUnverified))
    }

    /// The profile check, not the verification, keeps local builds out.
    @Test func testerBadgeIsNotGivenToALocallySignedBuildWithAnUnverifiedAppTransaction() {
        #expect(!earns(.sandboxUnverified, local: true))
        #expect(!earns(.sandboxUnverified, simulator: true))
        #expect(!earns(.sandboxUnverified, version: "1.0.0"))
    }

    @Test func testerBadgeIsNotGivenToALocallySignedBuild() {
        #expect(!earns(local: true))
    }

    @Test func testerBadgeIsNotGivenInTheSimulator() {
        #expect(!earns(simulator: true))
    }

    @Test func testerBadgeIsNotGivenFromLaunchOn() {
        #expect(!earns(version: "1.0.0"))
        #expect(!earns(version: "2.3"))
        #expect(!earns(version: ""))
    }

    @Test func storeEnvironmentsMapToDistributions() {
        #expect(SupportStoreTranslation.distribution(.xcode) == .xcode)
        #expect(SupportStoreTranslation.distribution(.sandbox) == .sandbox)
        #expect(SupportStoreTranslation.distribution(.production) == .production)
        #expect(SupportStoreTranslation.distribution(AppStore.Environment(rawValue: "Other")) == .unknown)
    }

    @Test func aVerifiedAppTransactionGivesItsEnvironment() {
        func verified(_ environment: AppStore.Environment) -> SupportDistribution {
            SupportStoreTranslation.distribution(VerificationResult<Int>.verified(1)) { _ in environment }
        }
        #expect(verified(.sandbox) == .sandbox)
        #expect(verified(.production) == .production)
        #expect(verified(.xcode) == .xcode)
    }

    @Test func anUnverifiedAppTransactionInTheSandboxIsKeptApart() {
        func unverified(_ environment: AppStore.Environment) -> SupportDistribution {
            SupportStoreTranslation.distribution(VerificationResult<Int>.unverified(1, .invalidSignature)) { _ in
                environment
            }
        }
        #expect(unverified(.sandbox) == .sandboxUnverified)
    }

    @Test func anUnverifiedAppTransactionOutsideTheSandboxKeepsItsEnvironment() {
        func unverified(_ environment: AppStore.Environment) -> SupportDistribution {
            SupportStoreTranslation.distribution(VerificationResult<Int>.unverified(1, .invalidSignature)) { _ in
                environment
            }
        }
        #expect(unverified(.production) == .production)
        #expect(unverified(.xcode) == .xcode)
        #expect(unverified(AppStore.Environment(rawValue: "Other")) == .unknown)
        for distribution in [
            unverified(.production), unverified(.xcode), unverified(AppStore.Environment(rawValue: "Other")),
        ] {
            #expect(!earns(distribution))
        }
    }

    /// A profile as it sits in a bundle: a signed envelope (here: stand-in bytes) around an XML
    /// property list.
    private func profile(_ keys: [String: Any]) throws -> Data {
        let xml = try PropertyListSerialization.data(fromPropertyList: keys, format: .xml, options: 0)
        return Data([0x30, 0x82, 0x1F, 0x00, 0xFF]) + xml + Data([0x00, 0xA0, 0x82])
    }

    @Test func aPhoneBuildIsLocalWhenItCarriesAProfile() {
        #expect(SupportSigningProfile.isLocalPhoneBuild(hasEmbeddedProfile: true))
        #expect(!SupportSigningProfile.isLocalPhoneBuild(hasEmbeddedProfile: false))
    }

    @Test func aMacBuildWithAStoreProfileIsNotLocal() throws {
        let store = try profile([
            "Platform": ["OSX"], "Entitlements": ["com.apple.application-identifier": "TEAM.app"],
        ])
        #expect(!SupportSigningProfile.isLocalMacBuild(profile: store))
        let explicit = try profile([
            "ProvisionsAllDevices": false, "Entitlements": ["com.apple.security.get-task-allow": false],
        ])
        #expect(!SupportSigningProfile.isLocalMacBuild(profile: explicit))
    }

    @Test func aMacBuildWithoutAProfileIsLocal() {
        #expect(SupportSigningProfile.isLocalMacBuild(profile: nil))
    }

    @Test func aMacBuildWithAnUnreadableProfileIsLocal() throws {
        #expect(SupportSigningProfile.isLocalMacBuild(profile: Data()))
        #expect(SupportSigningProfile.isLocalMacBuild(profile: Data("no property list here".utf8)))
        #expect(SupportSigningProfile.isLocalMacBuild(profile: Data("<?xml version=\"1.0\"?><plist>".utf8)))
        let array = try PropertyListSerialization.data(fromPropertyList: ["a"], format: .xml, options: 0)
        #expect(SupportSigningProfile.isLocalMacBuild(profile: array))
    }

    @Test func aMacBuildWhoseProfileListsDevicesIsLocal() throws {
        #expect(SupportSigningProfile.isLocalMacBuild(profile: try profile(["ProvisionedDevices": ["0001"]])))
        #expect(SupportSigningProfile.isLocalMacBuild(profile: try profile(["ProvisionedDevices": [String]()])))
    }

    @Test func aMacBuildWhoseProfileCoversEveryDeviceIsLocal() throws {
        #expect(SupportSigningProfile.isLocalMacBuild(profile: try profile(["ProvisionsAllDevices": true])))
    }

    @Test func aMacBuildWhoseProfileAllowsADebuggerIsLocal() throws {
        for key in ["com.apple.security.get-task-allow", "get-task-allow"] {
            #expect(SupportSigningProfile.isLocalMacBuild(profile: try profile(["Entitlements": [key: true]])))
        }
    }

    @Test func testerBadgeIsKeptOnceEarnedAndTheProbeRunsOncePerRun() async throws {
        let suite = "SupportBadgeTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let probe = TesterProbe()
        let service = SupportService(storefront: store, defaults: defaults, testerProbe: { probe.ask() })
        #expect(!service.isTester)
        await service.refreshBadges()
        await service.refreshBadges()
        #expect(!service.isTester)
        #expect(probe.asked == 1)
        #expect(!defaults.bool(forKey: SupportService.testerBadgeKey))

        probe.earns = true
        let next = SupportService(storefront: store, defaults: defaults, testerProbe: { probe.ask() })
        await next.refreshBadges()
        #expect(next.isTester)
        #expect(defaults.bool(forKey: SupportService.testerBadgeKey))

        // A later run that no longer earns it (the store build) still shows it, and does not ask.
        probe.earns = false
        let later = SupportService(storefront: store, defaults: defaults, testerProbe: { probe.ask() })
        #expect(later.isTester)
        await later.refreshBadges()
        #expect(probe.asked == 2)
    }

    @Test func withoutDefaultsNothingIsKeptAndTheDefaultProbeNeverEarns() async {
        let service = SupportService(storefront: store)
        await service.refreshBadges()
        #expect(!service.isTester)
        let earning = SupportService(storefront: store, testerProbe: { true })
        await earning.refreshBadges()
        #expect(earning.isTester)
        #expect(!SupportService(storefront: store).isTester)
    }

    @Test func uiTestLaunchBuildsAStoreInMemory() async {
        let environment = [
            AppLaunchPolicy.uiTestVaultEnvironmentKey: "/tmp/vault",
            AppLaunchPolicy.uiTestSupportKey: "medium,small,tester,unverified",
        ]
        let service = AppLaunchPolicy.supportService(environment: environment)
        await service.refreshBadges()
        #expect(service.supporterLevel == .medium)
        #expect(service.isTester)
        await service.buy(.large)
        #expect(service.purchase == .unverified)
        #expect(service.supporterLevel == .medium)

        let offline = AppLaunchPolicy.supportService(
            environment: [
                AppLaunchPolicy.uiTestVaultEnvironmentKey: "/tmp/vault", AppLaunchPolicy.uiTestSupportKey: "offline",
            ])
        await offline.loadProducts()
        #expect(offline.products == .unavailable)
        #expect(!offline.isTester)

        for (word, state) in [("failed", SupportPurchaseState.failed), ("unconfirmed", .unconfirmed)] {
            let failing = AppLaunchPolicy.supportService(
                environment: [
                    AppLaunchPolicy.uiTestVaultEnvironmentKey: "/tmp/vault", AppLaunchPolicy.uiTestSupportKey: word,
                ])
            await failing.buy(.small)
            #expect(failing.purchase == state)
        }
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

    @Test func thrownCancellationIsACancellation() throws {
        #expect(try SupportStoreTranslation.purchase(thrown: StoreKitError.userCancelled).kind == "cancelled")
    }

    private static let underlying = URLError(.notConnectedToInternet)

    @Test func aStorefrontOrEntitlementErrorRulesOutPayment() {
        #expect(SupportStoreTranslation.rulesOutPayment(StoreKitError.notAvailableInStorefront))
        #expect(SupportStoreTranslation.rulesOutPayment(StoreKitError.notEntitled))
    }

    @Test func anUnavailableProductOrAForbiddenPurchaseRulesOutPayment() {
        #expect(SupportStoreTranslation.rulesOutPayment(Product.PurchaseError.productUnavailable))
        #expect(SupportStoreTranslation.rulesOutPayment(Product.PurchaseError.purchaseNotAllowed))
    }

    @Test func aNetworkErrorLeavesPaymentOpen() {
        #expect(!SupportStoreTranslation.rulesOutPayment(StoreKitError.networkError(Self.underlying)))
        #expect(!SupportStoreTranslation.rulesOutPayment(Self.underlying))
    }

    @Test func aSystemErrorLeavesPaymentOpen() {
        #expect(!SupportStoreTranslation.rulesOutPayment(StoreKitError.systemError(Self.underlying)))
    }

    /// The original StoreKit API's errors are not named: whatever their code, they stay open.
    @Test func anOriginalStoreKitErrorLeavesPaymentOpen() {
        for code in [0, 2, 5] {
            let error = NSError(domain: "SKErrorDomain", code: code)
            #expect(!SupportStoreTranslation.rulesOutPayment(error))
            #expect(throws: NSError.self) { try SupportStoreTranslation.purchase(thrown: error) }
        }
    }

    @Test func anUnknownErrorLeavesPaymentOpen() {
        #expect(!SupportStoreTranslation.rulesOutPayment(StoreKitError.unknown))
        #expect(!SupportStoreTranslation.rulesOutPayment(CancellationError()))
    }

    /// Never sent by this app (no quantity, no offer): not named, so they stay open.
    @Test func purchaseErrorsTheAppCannotCauseLeavePaymentOpen() {
        #expect(!SupportStoreTranslation.rulesOutPayment(Product.PurchaseError.invalidQuantity))
        #expect(!SupportStoreTranslation.rulesOutPayment(Product.PurchaseError.invalidOfferSignature))
    }

    @Test func anErrorThatRulesOutPaymentIsThrownAsRefused() {
        let refusing: [any Error] = [
            StoreKitError.notAvailableInStorefront, StoreKitError.notEntitled,
            Product.PurchaseError.productUnavailable, Product.PurchaseError.purchaseNotAllowed,
        ]
        for error in refusing {
            #expect(throws: SupportStoreError.refused) { try SupportStoreTranslation.purchase(thrown: error) }
        }
    }

    @Test func anErrorThatLeavesPaymentOpenIsThrownAsItCame() {
        #expect(throws: StoreKitError.self) {
            try SupportStoreTranslation.purchase(thrown: StoreKitError.networkError(Self.underlying))
        }
        #expect(throws: StoreKitError.self) {
            try SupportStoreTranslation.purchase(thrown: StoreKitError.systemError(Self.underlying))
        }
        #expect(throws: StoreKitError.self) { try SupportStoreTranslation.purchase(thrown: StoreKitError.unknown) }
        #expect(throws: URLError.self) { try SupportStoreTranslation.purchase(thrown: Self.underlying) }
        #expect(throws: SupportStoreError.productNotLoaded) {
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
