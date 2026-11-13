import Foundation
import Testing
@testable import VaultFormat

struct VaultLayoutTests {
    @Test func detectsDiaryCaseVariant() {
        #expect(VaultLayout.caseVariantFolders(among: ["Diary", "people", "notes"]) == ["Diary"])
        #expect(VaultLayout.expectedFolder(forVariant: "Diary") == "diary")
        #expect(VaultLayout.caseVariantFolders(among: ["diary", "People"]) == ["People"])
        #expect(VaultLayout.caseVariantFolders(among: ["diary", "people"]).isEmpty)
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
        #expect(VaultFormatVersion.canWrite(vaultVersion: 0))
        #expect(VaultFormatVersion.canWrite(vaultVersion: 1))
        #expect(!VaultFormatVersion.canWrite(vaultVersion: 2))
    }
}
