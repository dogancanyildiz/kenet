import Testing
import VaultFormat

/// Every directory under `Fixtures/parse` holds an `input.md` and the `expected.json` a reader must produce.
struct ParseFixtureTests {
    /// The top-level keys of `expected.json` this client checks. A file may hold any subset.
    static let knownSections: Set<String> = ["frontmatter"]

    @Test func casesExist() throws {
        #expect(try !Fixtures.caseNames(in: "parse").isEmpty)
    }

    @Test(arguments: try Fixtures.caseNames(in: "parse"))
    func inputReadsAsExpected(name: String) throws {
        #expect(try Fixtures.fileNames(in: "parse/\(name)") == ["expected.json", "input.md"])
        let document = RawDocument(bytes: try Fixtures.bytes(at: "parse/\(name)/input.md"))
        let expected = try Fixtures.json(at: "parse/\(name)/expected.json")

        #expect(!expected.keys.isEmpty, "expected.json checks nothing")
        #expect(Set(expected.keys).isSubset(of: Self.knownSections), "unknown keys in \(expected.keys)")

        if let frontmatter = expected["frontmatter"] {
            let actual = FrontmatterSnapshot.json(document.frontmatter)
            #expect(actual == frontmatter, "the frontmatter reads as:\n\(actual)")
        }
    }
}
