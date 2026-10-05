import Foundation
import Testing

@testable import VaultStore

struct RenameScalingTests {
    // Keep the former scan as an independent oracle for filename ownership.
    private func scannedMatch(_ target: String, oldPath: String, files: [String]) -> Bool {
        guard !target.isEmpty else { return false }
        var normalized = target
        while normalized.hasPrefix("/") || normalized.hasPrefix("./") {
            normalized.removeFirst(normalized.hasPrefix("./") ? 2 : 1)
        }
        let key = storeComparisonKey(normalized)
        return files.first {
            let stem = String($0.dropLast(3))
            let candidate = target.contains("/") ? stem : (stem as NSString).lastPathComponent
            return storeComparisonKey(candidate).utf8.elementsEqual(key.utf8)
        } == oldPath
    }

    @Test func ownershipMatchesFormerScan() {
        let files = [
            "notes/Élan.md", "people/e\u{301}LAN.md", "people/Élan.md",
            "places/ÉLAN.md", "people/Mira.md", "notes/MIRA.md",
            "notes/İris.md", "people/i\u{307}ris.md",
        ]
        let queries = [
            "", "Missing", "Élan", "E\u{301}LAN", "élan", "people/Élan", "PEOPLE/e\u{301}lan",
            "notes/ÉLAN", "places/élan", "/./people/Élan", "././notes/Élan",
            "Mira", "MIRA", "notes/mira", "İris", "i\u{307}ris", "people/İRIS", "/", "./",
        ]
        for orderedFiles in [files, Array(files.reversed())] {
            for oldPath in orderedFiles {
                let targets = RenameTargets(oldPath: oldPath, newPath: "people/New.md", files: orderedFiles)
                for query in queries {
                    #expect(targets.matches(query) == scannedMatch(query, oldPath: oldPath, files: orderedFiles))
                }
            }
        }
    }

    @Test func ownershipNormalizationWorkIsLinear() {
        let files = (0..<600).map { "people/Person \($0).md" }
        var normalizations = 0
        let targets = RenameTargets(
            oldPath: files.last!, newPath: "people/New.md", files: files,
            comparisonKey: {
                normalizations += 1
                return storeComparisonKey($0)
            })
        #expect(normalizations == 2 * files.count)
        for query in 0..<24_000 {
            #expect(targets.matches(query.isMultiple(of: 2) ? "Person 599" : "people/Person 599"))
        }
        #expect(normalizations == 2 * files.count + 24_000)
    }

    @Test func syntheticVaultRenameStaysWithinBudget() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let fileCount = Int(ProcessInfo.processInfo.environment["RENAME_SCALE_FILES"] ?? "600") ?? 600
        let linksPerFile = Int(ProcessInfo.processInfo.environment["RENAME_SCALE_LINKS"] ?? "40") ?? 40
        let oldPath = "people/Zora Example.md"
        try vault.write(oldPath, "---\ntype: person\nname: Zora Example\n---\n")
        try vault.write("people/Luma Example.md", "---\ntype: person\nname: Luma Example\n---\n")
        for file in 0..<fileCount {
            let links = (0..<linksPerFile).map { link in
                // All links exercise resolution, but only 100 files reference the renamed person.
                link == 0 && file < 100 ? "[[Zora Example|Zora]]" : "[[Luma Example|Luma]]"
            }.joined(separator: " ")
            try vault.write("notes/Page \(file).md", links + "\n")
        }
        try vault.index.refresh(vaultRoot: vault.root)
        let clock = ContinuousClock()
        let start = clock.now
        let result = try await vault.store.renamingEntity(at: oldPath, to: "Zora Renamed")
        let elapsed = start.duration(to: clock.now)
        print("RENAME_SCALE files=\(fileCount + 2) links=\(fileCount * linksPerFile) elapsed=\(elapsed)")
        // Wall-clock time depends on the machine (shared CI runners measured 41 s for the linear code),
        // so the budget is enforced only when asked for; the normalization count above is the regression guard.
        if let budget = ProcessInfo.processInfo.environment["RENAME_SCALE_BUDGET_SECONDS"].flatMap(Int.init) {
            #expect(elapsed < .seconds(budget), "Rename exceeded the \(budget)-second budget: \(elapsed)")
        }
        #expect(result.failures.isEmpty)
        #expect(result.updatedFiles.count == min(fileCount, 100) + 1)
        #expect(try vault.index.links(to: result.path).count == min(fileCount, 100))
        for file in 0..<fileCount {
            let target = file < 100 ? "[[Zora Renamed|Zora]]" : "[[Luma Example|Luma]]"
            let expected =
                ([target] + Array(repeating: "[[Luma Example|Luma]]", count: linksPerFile - 1))
                .joined(separator: " ") + "\n"
            #expect(try vault.bytes("notes/Page \(file).md") == Data(expected.utf8))
        }
    }
}
