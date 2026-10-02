import Foundation
import Testing

struct FixtureLoaderTests {
    @Test func findsTheRepositoryFixturesDirectory() throws {
        let root = try Fixtures.root()

        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("roundtrip/day-basic.md").path))
    }

    @Test func listsMarkdownFilesSortedWithPathsRelativeToTheRoot() throws {
        let paths = try Fixtures.markdownPaths(in: "roundtrip")

        #expect(paths == paths.sorted())
        #expect(paths.contains("roundtrip/day-basic.md"))
        #expect(paths.allSatisfy { $0.hasPrefix("roundtrip/") && $0.hasSuffix(".md") })
        #expect(Set(paths).isSubset(of: Set(try Fixtures.markdownPaths())))
    }

    @Test func environmentVariableOverridesTheLocation() throws {
        let expected = try Fixtures.root()
        let root = try Fixtures.root(
            environment: [Fixtures.overrideVariable: expected.path],
            searchFrom: "/nonexistent/Tests/File.swift"
        )

        #expect(root.path == expected.path)
    }

    @Test func overrideThatIsNotADirectoryFailsWithAClearError() {
        let path = "/nonexistent/fixtures-override"

        #expect(throws: FixtureError.overrideIsNotADirectory(path: path)) {
            try Fixtures.root(environment: [Fixtures.overrideVariable: path])
        }
        #expect(FixtureError.overrideIsNotADirectory(path: path).description.contains(path))
    }

    @Test func missingDirectoryFailsWithAClearError() {
        let source = "/nonexistent/Tests/File.swift"

        #expect(throws: FixtureError.rootNotFound(searchedFrom: source)) {
            try Fixtures.root(environment: [:], searchFrom: source)
        }
        let message = FixtureError.rootNotFound(searchedFrom: source).description
        #expect(message.contains(Fixtures.overrideVariable))
        #expect(message.contains(source))
    }

    @Test func missingFileFailsWithAClearError() {
        #expect {
            try Fixtures.bytes(at: "roundtrip/does-not-exist.md")
        } throws: { error in
            String(describing: error).contains("does-not-exist.md")
        }
    }
}
