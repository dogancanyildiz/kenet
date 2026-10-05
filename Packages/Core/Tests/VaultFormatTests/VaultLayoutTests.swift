import Foundation
import Testing
import VaultFormat

struct VaultLayoutTests {
    @Test func detectsJournalCaseVariant() {
        #expect(VaultLayout.caseVariantFolders(among: ["Journal", "people", "notes"]) == ["Journal"])
        #expect(VaultLayout.expectedFolder(forVariant: "Journal") == "journal")
        #expect(VaultLayout.caseVariantFolders(among: ["journal", "People"]) == ["People"])
        #expect(VaultLayout.caseVariantFolders(among: ["journal", "people"]).isEmpty)
    }
}

struct VaultFormatVersionParseTests {
    @Test func parsesIntegerVersion() {
        #expect(VaultFormatVersion.formatVersion(in: Data("{ \"formatVersion\": 1 }\n".utf8)) == 1)
        #expect(VaultFormatVersion.formatVersion(in: Data("{ \"formatVersion\": 2 }\n".utf8)) == 2)
    }

    @Test func rejectsBooleanAndMissingVersion() {
        #expect(VaultFormatVersion.formatVersion(in: Data("{ \"formatVersion\": true }\n".utf8)) == nil)
        #expect(VaultFormatVersion.formatVersion(in: Data("{}\n".utf8)) == nil)
        #expect(VaultFormatVersion.formatVersion(in: Data("not-json".utf8)) == nil)
    }

    @Test func canWriteUsesParsedVersions() {
        #expect(VaultFormatVersion.canWrite(vaultVersion: 1))
        #expect(!VaultFormatVersion.canWrite(vaultVersion: 2))
    }
}
