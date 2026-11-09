import Testing

@testable import Journal

/// The Settings vault card's index line follows the store: an error first, then a refresh.
struct VaultCardIndexStateTests {
    @Test func errorOutranksIndexingAndIndexingOutranksCurrent() {
        #expect(VaultCardIndexState(hasError: false, isProcessing: false) == .current)
        #expect(VaultCardIndexState(hasError: false, isProcessing: true) == .indexing)
        #expect(VaultCardIndexState(hasError: true, isProcessing: true) == .failed)
        #expect(VaultCardIndexState(hasError: true, isProcessing: false) == .failed)
    }

    @Test func onlyAnUpToDateCloudVaultShowsTheCloudCheck() {
        #expect(VaultCardIndexState.current.symbol(isCloudVault: true) == "checkmark.icloud")
        #expect(VaultCardIndexState.current.symbol(isCloudVault: false) == "checkmark.circle")
        #expect(VaultCardIndexState.indexing.symbol(isCloudVault: true) != "checkmark.icloud")
        #expect(VaultCardIndexState.failed.symbol(isCloudVault: true) == "exclamationmark.triangle")
    }
}
