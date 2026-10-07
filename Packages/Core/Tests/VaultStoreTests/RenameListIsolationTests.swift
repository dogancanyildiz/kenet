import Foundation
import Testing
import VaultFormat
@testable import VaultStore

struct RenameListIsolationTests {
    @Test func emptyBlockListItemIsLocatedAmongNeighbors() throws {
        let document = RawDocument(
            bytes: Data(
                """
                ---
                rel:
                  - "[[Deniz Arıkan]]"
                  -
                  - "[[Deniz Arıkan|A]]"
                ---
                [[Deniz Arıkan]]
                """.utf8))
        guard case .parsed(let frontmatter) = document.frontmatter,
            case .list(let items, .block) = frontmatter.field(named: "rel")?.value
        else {
            Issue.record("Expected parsed block list")
            return
        }
        #expect(items.count == 3)
        #expect(items[1].kind == .empty)
        let ranges = try RenameListTokens.ranges(in: document, key: "rel", items: items)
        #expect(ranges.count == 3)
        #expect(ranges[1].isEmpty)
    }

    @Test func listRewriteFailureLeavesDocumentAndReportsReason() throws {
        let document = RawDocument(bytes: Data("---\nrel:\n  - Su\n---\n".utf8))
        guard case .parsed(let frontmatter) = document.frontmatter,
            case .list(let items, _) = frontmatter.field(named: "rel")?.value
        else {
            Issue.record("Expected list")
            return
        }
        let targets = RenameTargets(
            oldPath: "people/Deniz Arıkan.md", newPath: "people/Deniz Arıkan Yılmaz.md",
            files: ["people/Deniz Arıkan.md", "people/Deniz Arıkan Yılmaz.md"])
        let outcome = RenameDocument.applyList(
            document, key: "rel", items: items, targets: targets,
            rewrite: { _, _, _, _ in throw EditError.invalidValue })
        #expect(outcome.document == document)
        #expect(outcome.failure == .unmatchedTokens)
    }

    @Test func bodyUpdatesEvenWhenListRewriteFails() throws {
        let original = RawDocument(
            bytes: Data(
                """
                ---
                rel:
                  - "[[Deniz Arıkan]]"
                ---
                Body [[Deniz Arıkan]] here
                """.utf8))
        let files = ["people/Deniz Arıkan.md", "people/Deniz Arıkan Yılmaz.md", "notes/Su.md"]
        let targets = RenameTargets(
            oldPath: "people/Deniz Arıkan.md", newPath: "people/Deniz Arıkan Yılmaz.md", files: files)
        // Simulate a list token failure after body rewrite by patching through applyList in rewrite path:
        // use a document whose list links match but force failure via a one-off rewrite of RenameDocument.
        var document = original
        document = try targets.body(
            original,
            links: original.links.filter { $0.source == .body && targets.matches($0.target) })
        guard case .parsed(let frontmatter) = document.frontmatter,
            case .list(let items, _) = frontmatter.field(named: "rel")?.value
        else {
            Issue.record("Expected list")
            return
        }
        let list = RenameDocument.applyList(
            document, key: "rel", items: items, targets: targets,
            rewrite: { _, _, _, _ in throw EditError.invalidValue })
        let text = String(decoding: list.document.serialized(), as: UTF8.self)
        #expect(text.contains("Body [[Deniz Arıkan Yılmaz]] here"))
        #expect(text.contains("\"[[Deniz Arıkan]]\""))
        #expect(list.failure == .unmatchedTokens)
    }
}
