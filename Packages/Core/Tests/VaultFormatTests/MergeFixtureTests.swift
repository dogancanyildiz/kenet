import Testing
import VaultFormat

/// Every directory under `Fixtures/merge` holds two versions, their times and the merged file
/// they must produce byte for byte, together with the versions that must be preserved.
struct MergeFixtureTests {
    struct Case {
        let name: String
        let a: MergeVersion
        let b: MergeVersion
        let expected: [UInt8]
        let preservedNames: [String]

        init(name: String) throws {
            self.name = name
            let description = try Fixtures.json(at: "merge/\(name)/case.json")
            #expect(Set(description.keys) == ["times", "preserved"], "unknown keys in \(description.keys)")
            let times = try #require(description["times"])
            #expect(Set(times.keys) == ["a", "b"])
            a = MergeVersion(
                bytes: try Fixtures.bytes(at: "merge/\(name)/a.md"),
                modificationTime: try #require(times["a"]?.intValue))
            b = MergeVersion(
                bytes: try Fixtures.bytes(at: "merge/\(name)/b.md"),
                modificationTime: try #require(times["b"]?.intValue))
            expected = try Fixtures.bytes(at: "merge/\(name)/expected.md")
            preservedNames = try #require(description["preserved"]?.arrayValue).compactMap(\.stringValue)
            #expect(preservedNames == preservedNames.sorted(), "preserved names are sorted")
            #expect(Set(preservedNames).isSubset(of: ["a", "b"]))
        }

        /// The versions `preserved` names, in the order the merge reports them.
        func expectedPreserved() -> [MergeVersion] {
            let versions = [("a", a), ("b", b)].filter { preservedNames.contains($0.0) }.map(\.1)
            return versions.sorted { first, second in
                first.modificationTime != second.modificationTime
                    ? first.modificationTime < second.modificationTime
                    : first.bytes.lexicographicallyPrecedes(second.bytes)
            }
        }
    }

    @Test func casesExist() throws {
        #expect(try Fixtures.caseNames(in: "merge").count >= 30)
    }

    @Test(arguments: try Fixtures.caseNames(in: "merge"))
    func mergeProducesTheExpectedFile(name: String) throws {
        let fixture = try Case(name: name)
        #expect(try Fixtures.fileNames(in: "merge/\(name)") == ["a.md", "b.md", "case.json", "expected.md"])

        let result = ConflictMerge.merge(fixture.a, fixture.b)
        #expect(result.bytes == fixture.expected, "\(name) merges to:\n\(visible(result.bytes))")
        #expect(result.preserved == fixture.expectedPreserved(), "\(name) preserves \(describe(result, fixture))")
        #expect(ConflictMerge.merge(fixture.b, fixture.a) == result, "\(name) depends on the argument order")
        // Only the cases named for it may reach the last guard; everywhere else it would hide a bug.
        #expect(result.fellBack == name.contains("falls-back"), "\(name): fellBack is \(result.fellBack)")

        // The result is a file the reader accepts as it is.
        #expect(RawDocument(bytes: result.bytes).serialized() == result.bytes)
        #expect(losslessViolations(of: result.bytes) == [])

        // Merging the result again with either version, later than both, changes nothing.
        let later = max(fixture.a.modificationTime, fixture.b.modificationTime) + 1
        let merged = MergeVersion(bytes: result.bytes, modificationTime: later)
        #expect(ConflictMerge.merge(merged, fixture.a).bytes == result.bytes, "\(name): re-merge with a")
        #expect(ConflictMerge.merge(merged, fixture.b).bytes == result.bytes, "\(name): re-merge with b")

        for (label, version) in [("a", fixture.a), ("b", fixture.b)] {
            let violations = MergeLossCheck.violations(
                version: version.bytes, result: result.bytes, isPreserved: result.preserved.contains(version))
            #expect(violations == [], "\(name): version \(label) loses content")
        }
    }

    private func describe(_ result: MergeResult, _ fixture: Case) -> String {
        result.preserved.map { $0 == fixture.a ? "a" : ($0 == fixture.b ? "b" : "?") }.joined(separator: ", ")
    }

    /// The naming rule of `parse` and `write` cases applies, to at least one Markdown file of the case.
    @Test(arguments: try Fixtures.caseNames(in: "merge"))
    func caseNamesAnnounceByteProperties(name: String) throws {
        let files = try Fixtures.fileNames(in: "merge/\(name)").filter { $0.hasSuffix(".md") }
        let contents = try files.map { try Fixtures.bytes(at: "merge/\(name)/\($0)") }
        let words = FixtureCaseGuardTests.words(of: name)
        if words.contains("crlf") {
            #expect(
                contents.contains {
                    FixtureByteGuardTests.containsCRLF($0) && !FixtureByteGuardTests.containsBareLF($0)
                })
        }
        if words.contains("cr") {
            #expect(contents.contains { $0.count { $0 == 0x0D } >= 2 && !$0.contains(0x0A) })
        }
        if words.contains("bom") {
            #expect(contents.contains { Array($0.prefix(3)) == [0xEF, 0xBB, 0xBF] })
        }
        if name.contains("mixed-line-endings") {
            #expect(
                contents.contains {
                    FixtureByteGuardTests.containsCRLF($0) && FixtureByteGuardTests.containsBareLF($0)
                        && FixtureByteGuardTests.containsLoneCR($0)
                })
        }
        if name.contains("no-final-newline") {
            #expect(contents.contains { !$0.isEmpty && $0.last != 0x0A && $0.last != 0x0D })
        }
        if name.contains("invalid-utf8") || name.contains("read-only") {
            #expect(contents.contains { !ReferenceModel.isValidUTF8($0) })
        }
    }
}
