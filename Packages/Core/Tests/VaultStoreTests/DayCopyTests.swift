import Foundation
import Testing
import VaultFormat

@testable import VaultIndex
@testable import VaultStore

struct DayCopyTests {
    private struct NameTable: Decodable {
        struct Name: Decodable {
            let path: String
            let day: String?
        }
        let names: [Name]
        let mergeOrder: [String]
    }

    @Test func copyNamesFollowTheTable() throws {
        let table = try JSONDecoder().decode(
            NameTable.self, from: Data(contentsOf: DayCopyVault.fixture().appendingPathComponent("names.json")))
        for name in table.names {
            #expect(DayCopyName.isDayCopy(path: name.path) == (name.day != nil), "\(name.path)")
            #expect(DayCopyName.day(ofCopy: name.path)?.description == name.day, "\(name.path)")
            #expect(DayCopyName.dayPath(ofCopy: name.path) == name.day.map { "journal/" + $0 + ".md" })
        }
        let paths = table.names.map(\.path)
        #expect(DayCopyName.copies(in: paths) == table.mergeOrder)
        #expect(DayCopyName.copies(in: paths.reversed()) == table.mergeOrder)
    }

    @Test func conflictStampsAreUTC() {
        let cases: [(Int, String)] = [
            (0, "19700101T000000Z"), (-1, "19691231T235959Z"), (-86_400, "19691231T000000Z"),
            (951_782_400, "20000229T000000Z"), (1_790_852_733, "20261001T110533Z"),
            (1_798_761_599, "20261231T235959Z"), (4_107_542_400, "21000301T000000Z"),
        ]
        for (seconds, stamp) in cases { #expect(ConflictStamp.utc(seconds) == stamp, "\(seconds)") }
    }

    /// Copies are reported, never indexed: none of their blocks reach the index before a merge.
    @Test func scansReportCopiesWithoutIndexingThem() throws {
        let vault = try DayCopyVault()
        defer { vault.remove() }
        // Not copies by name: a decomposed mark after the number, and a decomposed note name.
        let decomposed = ["journal/2026-10-02 2\u{301}.md", "journal/Gu\u{308}nlu\u{308}k 2.md"]
        for path in decomposed { try Data("Not.\n".utf8).write(to: vault.url(path)) }
        let indexed = (vault.cases.indexedFiles + decomposed.map(\.precomposedStringWithCanonicalMapping)).sorted {
            $0.utf8.lexicographicallyPrecedes($1.utf8)
        }
        let results = [
            try vault.index.rebuild(vaultRoot: vault.root), try vault.index.refresh(vaultRoot: vault.root),
            try vault.index.update(paths: ["journal"], vaultRoot: vault.root),
        ]
        for result in results {
            #expect(result.dayCopies == vault.cases.dayCopies)
            #expect(try vault.index.files().map(\.path) == indexed)
        }
        let copy = "journal/2026-10-02 3.md"
        try Data("---\ntype: journal\n---\n\n## Events\n- Yeni ^e2c009\n".utf8).write(to: vault.url(copy))
        let notified = try vault.index.update(paths: [copy], vaultRoot: vault.root)
        #expect(notified.dayCopies == [copy])
        #expect(notified.addedPaths.isEmpty && notified.updatedPaths.isEmpty)
        #expect(try vault.index.update(paths: ["notes"], vaultRoot: vault.root).dayCopies.isEmpty)
        let identifiers = try vault.index.blockIdentifiers()
        for absent in ["e1b001", "e2b001", "e2c001", "e2c009", "e3b001", "e5b001"] {
            #expect(!identifiers.contains(absent), "\(absent)")
        }
        #expect(try vault.index.blocks(on: CalendarDate("2026-10-03")!).isEmpty)
    }

    /// Merging every reported copy in order yields `expected/` byte for byte; each step's day file is
    /// exactly what `ConflictMerge` returns and each conflict copy is the preserved version.
    @Test func mergingEveryCopyProducesTheExpectedVault() async throws {
        let vault = try DayCopyVault()
        defer { vault.remove() }
        let store = vault.store()
        let copies = try vault.index.refresh(vaultRoot: vault.root).dayCopies
        #expect(copies == vault.cases.outcomes.map(\.copy))
        for (copy, expected) in zip(copies, vault.cases.outcomes) {
            let dayPath = try #require(DayCopyName.dayPath(ofCopy: copy))
            let copyVersion = try vault.version(copy)
            let dayVersion =
                FileManager.default.fileExists(atPath: vault.url(dayPath).path)
                ? try vault.version(dayPath) : nil
            let outcome = try await store.mergingDayCopy(copy)
            #expect(String(describing: outcome.kind) == expected.kind, "\(copy)")
            #expect(outcome.dayPath == dayPath)
            #expect(outcome.dayFileChanged == (dayVersion?.bytes != Array(try Data(contentsOf: vault.url(dayPath)))))
            #expect(outcome.conflictPaths == expected.conflicts, "\(copy)")
            #expect(outcome.fellBack == expected.fellBack)
            #expect(!FileManager.default.fileExists(atPath: vault.url(copy).path), "\(copy) remains")
            if let dayVersion {
                let merge = ConflictMerge.merge(dayVersion, copyVersion)
                #expect(Array(try Data(contentsOf: vault.url(dayPath))) == merge.bytes, "\(copy)")
                #expect(merge.preserved.count == outcome.conflictPaths.count)
                for (version, path) in zip(merge.preserved, outcome.conflictPaths) {
                    #expect(Array(try Data(contentsOf: vault.url(path))) == version.bytes, "\(path)")
                }
                // A replaced day file follows the later version by one second; an unchanged one keeps its time.
                let time =
                    merge.bytes == dayVersion.bytes
                    ? dayVersion.modificationTime : max(dayVersion.modificationTime, copyVersion.modificationTime) + 1
                #expect(try vault.time(dayPath) == time, "\(copy)")
            } else {
                #expect(Array(try Data(contentsOf: vault.url(dayPath))) == copyVersion.bytes)
                #expect(try vault.time(dayPath) == copyVersion.modificationTime)
            }
            try equivalent(vault.index, vault.root)
        }
        let expectedTree = try DayCopyVault.tree(DayCopyVault.fixture().appendingPathComponent("expected"))
        #expect(try vault.tree() == expectedTree)
        let after = try vault.index.refresh(vaultRoot: vault.root)
        #expect(after.dayCopies.isEmpty)
        // Every event and task of both versions is indexed exactly once, in its day.
        let blocks = try vault.index.snapshot().blocks.filter { $0.identifier != nil }
        let identifiers = blocks.compactMap(\.identifier)
        #expect(Set(identifiers).count == identifiers.count)
        let days = [
            "e1a001": "01", "e1b001": "01", "e2a001": "02", "e2b001": "02", "e2c001": "02", "e3b001": "03",
            "e4a001": "04", "e5a001": "05", "e8a001": "08", "e8b001": "08",
        ]
        for (identifier, day) in days {
            #expect(blocks.first { $0.identifier == identifier }?.file == "journal/2026-10-\(day).md", "\(identifier)")
        }
    }

    /// An interrupted merge whose copy survived, or the other version arriving again, merges to
    /// the same day file and reuses the conflict copy already saved.
    @Test func mergingAgainChangesNothing() async throws {
        let vault = try DayCopyVault()
        defer { vault.remove() }
        let store = vault.store()
        let copy = "journal/2026-10-01 2.md"
        let dayPath = "journal/2026-10-01.md"
        let originalCopy = try Data(contentsOf: vault.url(copy))
        let originalDay = try Data(contentsOf: vault.url(dayPath))
        let conflict = "conflicts/2026-10-01 (conflict 20261001T090000Z 2).md"
        #expect(try await store.mergingDayCopy(copy).conflictPaths == [conflict])
        let merged = try vault.tree()
        for (bytes, time) in [
            (originalCopy, vault.cases.times[copy]!), (originalDay, vault.cases.times[dayPath]!),
        ] {
            try bytes.write(to: vault.url(copy))
            try vault.setTime(copy, time)
            let outcome = try await store.mergingDayCopy(copy)
            #expect(outcome.kind == .merged)
            #expect(outcome.conflictPaths == (bytes == originalDay ? [conflict] : []))
            #expect(try vault.tree() == merged)
            try equivalent(vault.index, vault.root)
        }
    }

    /// Two devices that merge the same pair separately write the same day file; when those two
    /// results meet as a new copy, the copy is identical and simply removed.
    @Test func twoDevicesReachTheSameContent() async throws {
        let first = try DayCopyVault()
        let second = try DayCopyVault()
        defer {
            first.remove()
            second.remove()
        }
        for copy in first.cases.dayCopies {
            _ = try await first.store().mergingDayCopy(copy)
            _ = try await second.store().mergingDayCopy(copy)
        }
        #expect(try first.tree() == second.tree())
        // Only the paths `cases.json` gives a time are compared: the others keep the copy's wall-clock
        // time, which differs between the two vaults whenever their writes straddle a second boundary.
        for path in first.cases.times.keys.sorted()
        where FileManager.default.fileExists(atPath: first.url(path).path) {
            #expect(try first.time(path) == second.time(path), "\(path)")
        }
        let copy = "journal/2026-10-02 2.md"
        try Data(contentsOf: second.url("journal/2026-10-02.md")).write(to: first.url(copy))
        let outcome = try await first.store().mergingDayCopy(copy)
        #expect(outcome.kind == .identical)
        #expect(outcome.conflictPaths.isEmpty)
        #expect(try first.tree() == second.tree())
    }

    @Test func identicalVersionsWriteNoConflictCopy() async throws {
        let vault = try DayCopyVault()
        defer { vault.remove() }
        try FileManager.default.removeItem(at: vault.url("conflicts"))
        let before = try vault.tree()
        let outcome = try await vault.store().mergingDayCopy("journal/2026-10-04 2.md")
        #expect(
            outcome
                == DayCopyMergeOutcome(
                    kind: .identical, dayPath: "journal/2026-10-04.md", dayFileChanged: false, conflictPaths: [],
                    fellBack: false))
        var expected = before
        expected.removeValue(forKey: "journal/2026-10-04 2.md")
        #expect(try vault.tree() == expected)
    }

    /// Two preserved versions with one time, or a taken name, get the next free number.
    @Test func takenConflictNamesAreNumbered() async throws {
        let vault = try DayCopyVault()
        defer { vault.remove() }
        let taken = "conflicts/2026-10-05 (conflict 20261005T060000Z).md"
        let placeholder = "conflicts/.2026-10-05 (conflict 20261005T060000Z 2).md.icloud"
        try Data("Başka not.\n".utf8).write(to: vault.url(taken))
        try Data("bplist00".utf8).write(to: vault.url(placeholder))
        let outcome = try await vault.store().mergingDayCopy("journal/2026-10-05 2.md")
        #expect(outcome.conflictPaths == ["conflicts/2026-10-05 (conflict 20261005T060000Z 3).md"])
        #expect(try Data(contentsOf: vault.url(taken)) == Data("Başka not.\n".utf8))
        #expect(try Data(contentsOf: vault.url(placeholder)) == Data("bplist00".utf8))
    }

    private struct VersionCases: Decodable {
        let times: [String: Int]
        let dayPath: String
        let orders: [[String]]
        let conflicts: [[String]]
    }

    private static func date(_ seconds: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(seconds)) }

    /// A merged day file takes the later version's time plus one second, never the clock, so copy 3
    /// stays the newer version after copy 2 is merged. Both merge orders reach the same day file and
    /// both keep copy 3's change of the shared event.
    @Test func threeVersionsConvergeInEitherOrder() async throws {
        let fixture = try DayCopyVault.fixture().appendingPathComponent("three-versions")
        let cases = try JSONDecoder().decode(
            VersionCases.self, from: Data(contentsOf: fixture.appendingPathComponent("case.json")))
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: scratch) }
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let dayPath = cases.dayPath
        var days: [Data] = []
        for (order, conflicts) in zip(cases.orders, cases.conflicts) {
            let root = scratch.appendingPathComponent(String(days.count))
            try FileManager.default.copyItem(at: fixture.appendingPathComponent("source"), to: root)
            for (path, time) in cases.times {
                try FileManager.default.setAttributes(
                    [.modificationDate: Self.date(time)], ofItemAtPath: root.appendingPathComponent(path).path)
            }
            let index = try VaultIndex()
            try index.rebuild(vaultRoot: root)
            let store = VaultStore(vaultRoot: root, index: index)
            let dayURL = root.appendingPathComponent(dayPath)
            var later = try #require(cases.times[dayPath])
            for copy in order {
                #expect(try await store.mergingDayCopy(copy).kind == .merged, "\(order)")
                later = max(later, try #require(cases.times[copy])) + 1
                let time = try FileManager.default.attributesOfItem(atPath: dayURL.path)[.modificationDate] as? Date
                #expect(time == Self.date(later), "\(order) \(copy)")
            }
            #expect(
                try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("conflicts").path)
                    .map { "conflicts/" + $0 }.sorted() == conflicts.sorted())
            try equivalent(index, root)
            days.append(try Data(contentsOf: dayURL))
        }
        #expect(days[0] == days[1])
        #expect(days[0] == (try Data(contentsOf: fixture.appendingPathComponent("expected.md"))))
    }
}
