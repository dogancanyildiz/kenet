import Foundation
import GRDB
import Testing

@testable import VaultIndex

@Suite(.serialized)
struct InitialIndexTests {
    @Test func ownershipQueryUsesIdentifierIndex() throws {
        let index = try VaultIndex()
        let plan = try index.database.read {
            try Row.fetchAll(
                $0,
                sql:
                    "EXPLAIN QUERY PLAN SELECT file,ordinal FROM blocks WHERE identifier=? ORDER BY file,ordinal LIMIT 1",
                arguments: ["shared"]
            )
            .map { (row: Row) -> String in row["detail"] }
        }
        #expect(plan.contains { $0.contains("USING INDEX block_identifiers") })
        #expect(!plan.contains { $0.contains("SCAN blocks") })
    }

    @Test(arguments: ["empty", "added", "removed", "scoped"])
    func emptyRefreshAndTypeChangesUseFullBuild(_ scenario: String) throws {
        try withVault { root in
            try write(root, "a.md", "## Events\n- [[books/Kitap]] ^shared\n- Aynı kimlik ^shared")
            try write(root, "z.md", "- [ ] Oku ^shared")
            try write(root, "books/Kitap.md", "---\ntype: book\nname: Kitap\n---\nKurgusal kitap")
            let index = try VaultIndex()
            let schema = try String(
                contentsOf: Fixtures.root().appendingPathComponent("vaults/typed/.app/types.json"), encoding: .utf8)
            if scenario == "removed" { try write(root, ".app/types.json", schema) }
            if scenario != "empty" { try index.rebuild(vaultRoot: root) }
            try write(
                root, ".app/types.json",
                (scenario == "removed" || scenario == "empty") ? "{\"formatVersion\":1,\"types\":[]}" : schema)
            // The incremental path repairs owners with UPDATE; the full build assigns them at insertion.
            try index.database.write {
                try $0.execute(
                    sql: """
                        CREATE TRIGGER reject_owner_repair BEFORE UPDATE OF ownsIdentifier ON blocks
                        BEGIN SELECT RAISE(ABORT,'incremental ownership repair'); END
                        """)
            }
            let result =
                try scenario == "scoped"
                ? index.update(paths: ["not-present.md"], vaultRoot: root) : index.refresh(vaultRoot: root)
            let rebuilt = try VaultIndex()
            #expect(try result == rebuilt.rebuild(vaultRoot: root))
            #expect(try index.snapshot() == rebuilt.snapshot())
            #expect(try index.search("Kitap") == rebuilt.search("Kitap"))
            #expect(try index.snapshot().blocks.filter { $0.ownsIdentifier }.count == 1)
        }
    }

    @Test func versionFiveIsErasedAndRefreshRepopulates() throws {
        try withVault { temporary in
            let root = temporary.appendingPathComponent("vault")
            try write(root, "Kitap.md", "- [ ] Oku ^read")
            let url = temporary.appendingPathComponent("index.sqlite")
            do {
                let index = try VaultIndex(databaseURL: url)
                try index.rebuild(vaultRoot: root)
                try index.database.write { try $0.execute(sql: "PRAGMA user_version=5") }
            }
            let index = try VaultIndex(databaseURL: url)
            #expect(try index.files().isEmpty)
            #expect(try index.database.read { try Int.fetchOne($0, sql: "PRAGMA user_version") } == 6)
            try index.refresh(vaultRoot: root)
            try equivalent(index, root)
        }
    }

    @Test func reclassificationFailurePreservesPreviousIndex() throws {
        try withVault { root in
            try write(root, "Kitap.md", "- [ ] Oku ^read")
            let index = try VaultIndex()
            try index.rebuild(vaultRoot: root)
            let before = try index.snapshot()
            try index.database.write {
                try $0.execute(
                    sql: """
                        CREATE TRIGGER reject_blocks BEFORE INSERT ON blocks
                        BEGIN SELECT RAISE(ABORT,'failed build'); END
                        """)
            }
            let fixture = try Fixtures.root().appendingPathComponent("vaults/typed/.app/types.json")
            try write(root, ".app/types.json", String(contentsOf: fixture, encoding: .utf8))
            #expect(throws: (any Error).self) { try index.refresh(vaultRoot: root) }
            #expect(try index.snapshot() == before)
            #expect(
                try index.database.read { try String.fetchOne($0, sql: "SELECT signature FROM entity_type_state") }
                    == "")
        }
    }

    @Test func syntheticInitialRefreshStaysNearRebuild() throws {
        try withVault { root in
            for file in 0..<2_000 {
                let events = (0..<8).map { "- Kurgusal olay \(file)-\($0) ^event-\(file)-\($0)" }
                try write(root, "notes/Note-\(file).md", "## Events\n" + events.joined(separator: "\n"))
            }
            let fresh = try VaultIndex()
            let incremental = try VaultIndex()
            let clock = ContinuousClock()
            let rebuildStart = clock.now
            let rebuiltResult = try fresh.rebuild(vaultRoot: root)
            let rebuildTime = rebuildStart.duration(to: clock.now)
            let refreshStart = clock.now
            let refreshedResult = try incremental.refresh(vaultRoot: root)
            let refreshTime = refreshStart.duration(to: clock.now)
            print("INITIAL_INDEX_SCALE files=2000 blocks=16000 rebuild=\(rebuildTime) refresh=\(refreshTime)")
            #expect(refreshedResult == rebuiltResult)
            #expect(try incremental.snapshot() == fresh.snapshot())
            // Generous allowance for shared CI load; query-plan and trigger tests provide deterministic guards.
            #expect(refreshTime < rebuildTime * 3 + .milliseconds(100))
            let fixture = try Fixtures.root().appendingPathComponent("vaults/typed/.app/types.json")
            try write(root, ".app/types.json", String(contentsOf: fixture, encoding: .utf8))
            let typeStart = clock.now
            try incremental.refresh(vaultRoot: root)
            let typeTime = typeStart.duration(to: clock.now)
            print("INITIAL_INDEX_SCALE typeChange=\(typeTime)")
            let typedStart = clock.now
            try fresh.rebuild(vaultRoot: root)
            let typedRebuildTime = typedStart.duration(to: clock.now)
            print("INITIAL_INDEX_SCALE typedRebuild=\(typedRebuildTime)")
            #expect(try incremental.snapshot() == fresh.snapshot())
            #expect(typeTime < typedRebuildTime * 3 + .milliseconds(100))
        }
    }
}
