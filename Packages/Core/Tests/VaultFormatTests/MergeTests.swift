import Testing
import VaultFormat

/// The merge contract on hand-written inputs, including the sample vault's conflict copy.
struct MergeTests {
    private func version(_ text: String, at time: Int) -> MergeVersion {
        MergeVersion(bytes: Array(text.utf8), modificationTime: time)
    }

    @Test func theLaterTimeMakesTheNewerVersion() {
        let early = version("## Journal\nbeta\n", at: 1)
        let late = version("## Journal\nalpha\n", at: 2)

        let result = ConflictMerge.merge(early, late)
        #expect(result.bytes == late.bytes)
        #expect(result.preserved == [early])
        #expect(ConflictMerge.merge(late, early) == result)
    }

    @Test func equalTimesFallBackToByteOrder() {
        let smaller = version("## Journal\nalpha\n", at: 5)
        let larger = version("## Journal\nbeta\n", at: 5)

        let result = ConflictMerge.merge(smaller, larger)
        #expect(result.bytes == larger.bytes)
        #expect(result.preserved == [smaller])
        #expect(ConflictMerge.merge(larger, smaller) == result)
    }

    @Test func identicalBytesNeedNoCopyWhateverTheTimes() {
        let first = version("## Journal\nalpha\n", at: 5)
        let second = version("## Journal\nalpha\n", at: 9)

        #expect(ConflictMerge.merge(first, second) == MergeResult(bytes: first.bytes, preserved: []))
        #expect(ConflictMerge.merge(first, first) == MergeResult(bytes: first.bytes, preserved: []))
    }

    @Test func readOnlyVersionIsNeverMerged() {
        let valid = version("## Tasks\n- [ ] Su ^r0a001\n", at: 9)
        let invalid = MergeVersion(
            bytes: Array("## Tasks\n- [ ] S".utf8) + [0xFF] + Array(" ^r0b001\n".utf8), modificationTime: 1)

        let result = ConflictMerge.merge(valid, invalid)
        #expect(result.bytes == valid.bytes)
        #expect(result.preserved == [invalid])

        let newerInvalid = MergeVersion(bytes: invalid.bytes, modificationTime: 10)
        #expect(ConflictMerge.merge(valid, newerInvalid) == MergeResult(bytes: newerInvalid.bytes, preserved: [valid]))
    }

    @Test func bothVersionsCanBePreserved() {
        // The older version closed the task; the newer version changed its text and the journal.
        let older = version("## Tasks\n- [x] Su ✅ 2026-09-21 ^p1x001\n\n## Journal\nSabah.\n", at: 1)
        let newer = version("## Tasks\n- [ ] Su iç ^p1x001\n\n## Journal\nAkşam.\n", at: 2)

        let result = ConflictMerge.merge(older, newer)
        #expect(result.bytes == Array("## Tasks\n- [x] Su ✅ 2026-09-21 ^p1x001\n\n## Journal\nAkşam.\n".utf8))
        #expect(result.preserved == [older, newer])
    }

    @Test func sampleVaultConflictCopyMergesByTheEventRule() throws {
        let journal = try Fixtures.bytes(at: "vaults/sample/journal/2026-09-20.md")
        let copyName = try #require(try Fixtures.fileNames(in: "vaults/sample/conflicts").first)
        let copy = try Fixtures.bytes(at: "vaults/sample/conflicts/\(copyName)")
        #expect(journal != copy)

        // The two files differ in the text of one event; the newer text wins and the other is kept.
        let journalNewer = ConflictMerge.merge(
            MergeVersion(bytes: journal, modificationTime: 2), MergeVersion(bytes: copy, modificationTime: 1))
        #expect(journalNewer.bytes == journal)
        #expect(journalNewer.preserved == [MergeVersion(bytes: copy, modificationTime: 1)])

        let copyNewer = ConflictMerge.merge(
            MergeVersion(bytes: journal, modificationTime: 1), MergeVersion(bytes: copy, modificationTime: 2))
        #expect(copyNewer.bytes == copy)
        #expect(copyNewer.preserved == [MergeVersion(bytes: journal, modificationTime: 1)])

        for result in [journalNewer, copyNewer] {
            for version in [journal, copy] {
                let isPreserved = result.preserved.contains { $0.bytes == version }
                #expect(
                    MergeLossCheck.violations(version: version, result: result.bytes, isPreserved: isPreserved) == [])
            }
        }
    }

    @Test func largeFilesMergeInReasonableTime() {
        // Many blocks without identifiers and much free text must not make matching quadratic.
        var older = "---\ntype: journal\n---\n\n## Tasks\n"
        var newer = older
        for index in 0..<20_000 {
            older += "- [ ] Görev \(index)\n"
            newer += "- [ ] Görev \(index)\n"
            if index % 7 == 0 { older += "- [ ] Ek \(index)\n" }
            if index % 11 == 0 { newer += "- [ ] Yeni \(index)\n" }
        }
        older += "\n## Journal\n"
        newer += "\n## Journal\n"
        for index in 0..<20_000 {
            older += "Satır \(index)\n"
            newer += "Satır \(index)\n"
        }
        older += "Son.\n"

        let result = ConflictMerge.merge(version(older, at: 1), version(newer, at: 2))
        #expect(result.preserved == [])
        #expect(RawDocument(bytes: result.bytes).bodyLines.tasks.count == 20_000 + 2858 + 1819)
        #expect(MergeLossCheck.violations(version: Array(older.utf8), result: result.bytes, isPreserved: false) == [])
        #expect(MergeLossCheck.violations(version: Array(newer.utf8), result: result.bytes, isPreserved: false) == [])
    }
}
