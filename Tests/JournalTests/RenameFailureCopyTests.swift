import Foundation
import Testing
import VaultStore

@testable import Journal

struct RenameFailureCopyTests {
    @Test func frontmatterListUsesCatalogKeysNotEnglishCorePhrases() {
        let unmatched = RenameFailureCopy.frontmatterList(key: "rel", reason: .unmatchedTokens)
        let unexpected = RenameFailureCopy.frontmatterList(key: "tags", reason: .unexpected)
        #expect(unmatched == String(localized: "Ön bilgi listesi güncellenemedi (\("rel")): öğeler eşleştirilemedi."))
        #expect(unexpected == String(localized: "Ön bilgi listesi güncellenemedi (\("tags"))."))
        #expect(!unmatched.contains("list tokens could not be matched"))
        #expect(!unmatched.contains("frontmatter list"))
        #expect(!unexpected.contains("list tokens could not be matched"))
    }

    @Test func structuredReasonSurfacesAsFrontmatterListCase() {
        let failure = RenameFailure(
            path: "notes/Su.md", reason: .frontmatterList(key: "rel", reason: .unmatchedTokens))
        guard case .frontmatterList(let key, let reason) = failure.reason else {
            Issue.record("Expected structured frontmatterList reason")
            return
        }
        #expect(key == "rel")
        #expect(reason == .unmatchedTokens)
    }
}
