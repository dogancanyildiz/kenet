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

    /// A folder out of reach is the vault's fault: "kasa hatası", even with the store's error set.
    @Test func anInaccessibleFolderIsAVaultErrorNotAnIndexError() {
        #expect(
            VaultCardIndexState(vaultInaccessible: true, hasError: true, isProcessing: false)
                == .vaultUnavailable)
        #expect(
            VaultCardIndexState(vaultInaccessible: true, hasError: false, isProcessing: true)
                == .vaultUnavailable)
        #expect(VaultCardIndexState.vaultUnavailable.isFailure)
        #expect(VaultCardIndexState.failed.isFailure)
        #expect(!VaultCardIndexState.indexing.isFailure)
    }

    @Test func onlyAnUpToDateCloudVaultShowsTheCloudCheck() {
        #expect(VaultCardIndexState.current.symbol(isCloudVault: true) == "checkmark.icloud")
        #expect(VaultCardIndexState.current.symbol(isCloudVault: false) == "checkmark.circle")
        #expect(VaultCardIndexState.indexing.symbol(isCloudVault: true) != "checkmark.icloud")
        #expect(VaultCardIndexState.failed.symbol(isCloudVault: true) == "exclamationmark.triangle")
    }
}
