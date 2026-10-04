import Foundation

struct VaultImportReport: Sendable {
    static let folders = ["journal", "people", "places", "goals", "notes", "templates"]
    struct Candidate: Sendable {
        let path: String
        let kind: String
    }
    let root: URL
    var foundFolders: [String] = []
    var missingFolders: [String] = []
    var missingTemplates: [String] = []
    var markdownCount = 0
    var journalDays: [String] = []
    var externalDays: [String] = []
    var typed: [String: Int] = [:]
    var candidates: [Candidate] = []
    var skipped: [String] = []
    var needsSettings = false
    var canPrepare = true
    var needsPreparation: Bool {
        !canPrepare || !missingFolders.isEmpty || !missingTemplates.isEmpty || needsSettings || !candidates.isEmpty
    }
}
struct VaultImportOptions: Sendable {
    var folders = true
    var settings = true
    var types = true
}
struct VaultImportResult: Sendable {
    var created: [String] = []
    var typed: [String] = []
    var skipped: [String] = []
    var failures: [String] = []
}
