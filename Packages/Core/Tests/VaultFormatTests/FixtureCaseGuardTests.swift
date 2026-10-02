import Testing

/// Guards the byte-level properties that `parse` and `write` cases announce in their names.
///
/// Like `FixtureByteGuardTests`, these read the raw files without the model and turn red if
/// git, an editor or a formatter rewrites a fixture.
struct FixtureCaseGuardTests {
    /// Every Markdown file of the case directories, as (case name, path).
    static func files() throws -> [(name: String, path: String)] {
        try ["parse", "write"].flatMap { category in
            try Fixtures.caseNames(in: category).flatMap { name in
                try Fixtures.fileNames(in: "\(category)/\(name)")
                    .filter { $0.hasSuffix(".md") }
                    .map { (name, "\(category)/\(name)/\($0)") }
            }
        }
    }

    static func words(of name: String) -> [String] {
        name.split(separator: "-").map(String.init)
    }

    @Test func crlfCasesUseOnlyCRLF() throws {
        let files = try Self.files().filter { Self.words(of: $0.name).contains("crlf") }

        #expect(files.count >= 4)
        for file in files {
            let bytes = try Fixtures.bytes(at: file.path)
            #expect(FixtureByteGuardTests.containsCRLF(bytes), "\(file.path)")
            #expect(!FixtureByteGuardTests.containsBareLF(bytes), "\(file.path)")
            #expect(!FixtureByteGuardTests.containsLoneCR(bytes), "\(file.path)")
        }
    }

    @Test func crCasesUseOnlyCR() throws {
        let files = try Self.files().filter { Self.words(of: $0.name).contains("cr") }

        #expect(files.count >= 4)
        for file in files {
            let bytes = try Fixtures.bytes(at: file.path)
            #expect(bytes.count { $0 == 0x0D } >= 2, "\(file.path)")
            #expect(!bytes.contains(0x0A), "\(file.path)")
        }
    }

    @Test func mixedLineEndingCasesHaveAllThreeEndings() throws {
        let files = try Self.files().filter { $0.name.contains("mixed-line-endings") }

        #expect(files.count >= 2)
        for file in files {
            let bytes = try Fixtures.bytes(at: file.path)
            #expect(FixtureByteGuardTests.containsCRLF(bytes), "\(file.path)")
            #expect(FixtureByteGuardTests.containsBareLF(bytes), "\(file.path)")
            #expect(FixtureByteGuardTests.containsLoneCR(bytes), "\(file.path)")
        }
    }

    @Test func byteOrderMarkCasesStartWithTheMark() throws {
        let files = try Self.files().filter { Self.words(of: $0.name).contains("bom") }

        #expect(files.count >= 4)
        for file in files {
            #expect(Array(try Fixtures.bytes(at: file.path).prefix(3)) == [0xEF, 0xBB, 0xBF], "\(file.path)")
        }
    }

    @Test func noFinalNewlineCasesEndWithoutLineEnding() throws {
        let files = try Self.files().filter { $0.name.contains("no-final-newline") }

        #expect(files.count >= 4)
        for file in files {
            let bytes = try Fixtures.bytes(at: file.path)
            #expect(!bytes.isEmpty && bytes.last != 0x0A && bytes.last != 0x0D, "\(file.path)")
        }
    }

    @Test func invalidUTF8CasesAreNotValidUTF8() throws {
        let files = try Self.files().filter { $0.name.contains("invalid-utf8") || $0.name.contains("read-only") }

        #expect(files.count >= 4)
        for file in files {
            #expect(!ReferenceModel.isValidUTF8(try Fixtures.bytes(at: file.path)), "\(file.path)")
        }
    }

    @Test func exactKeyMatchCasesHoldDecomposedLetters() throws {
        let files = try Self.files().filter { $0.name.contains("exact-key-match") }
        let decomposed: [UInt8] = [0x67, 0xCC, 0x86]  // "g" followed by a combining breve

        #expect(files.count >= 3)
        for file in files {
            let bytes = try Fixtures.bytes(at: file.path)
            let found = bytes.indices.contains { bytes[$0...].starts(with: decomposed) }
            #expect(found, "\(file.path)")
        }
    }

    @Test func tabCasesHoldATab() throws {
        #expect(try Fixtures.bytes(at: "parse/unreadable-tab-indentation/input.md").contains(0x09))
        #expect(try Fixtures.bytes(at: "parse/unreadable-tab-after-dash/input.md").contains(0x09))
        #expect(try Fixtures.bytes(at: "parse/unreadable-tab-after-indentation/input.md").contains(0x09))
        #expect(try Fixtures.bytes(at: "parse/unreadable-closing-with-trailing-space/input.md").contains(0x09))
        #expect(
            try Fixtures.bytes(at: "parse/unreadable-opening-with-trailing-space/input.md").starts(
                with: Array("--- \n".utf8)))
    }
}
