import Foundation
import Testing
import VaultFormat
import VaultIndex

@testable import Kenet

/// Quick alias change on the entity page: the rules, the bytes written and the order of file and index.
@MainActor
struct EntityAliasTests {
    private static let path = "people/Ece Yalın.md"

    private static func writeCase(_ name: String, _ file: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/write/\(name)/\(file)")
    }

    /// A vault holding the case's `input.md` as the person file, and that person's loaded model.
    private static func context(_ name: String) async throws -> (TaskTestContext, EntityDetailModel, URL) {
        let context = try TaskTestContext(sample: false)
        await context.start()
        let file = context.root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contentsOf: writeCase(name, "input.md")).write(to: file)
        await context.store.refreshAndSettle(rebuild: true)
        let model = EntityDetailModel(store: context.store, path: path)
        await model.load()
        #expect(model.isLoaded)
        return (context, model, file)
    }

    @Test(arguments: [
        ("alias-add-missing-key", "Ece"), ("alias-add-inline-keeps-quotes-and-comment", "Ecoş"),
        ("alias-add-block-keeps-comments", "Ece Hanım"), ("alias-add-crlf-bom", "Ecoş"),
        ("alias-add-single-value", "Ecoş"), ("alias-add-comma-is-quoted", "Yalın, Ece"),
    ])
    func addingWritesOnlyTheAliasesField(_ name: String, _ alias: String) async throws {
        let (context, model, file) = try await Self.context(name)
        defer { context.clean() }
        let expected = try Data(contentsOf: Self.writeCase(name, "expected.md"))
        // Surrounding blanks are trimmed; the alias itself is written as typed.
        #expect(await model.addAlias("  " + alias + "\n", name: "Ece Yalın"))
        #expect(model.aliasErrorText == nil)
        #expect(try Data(contentsOf: file) == expected)
        #expect(model.aliases.last == alias)
        // The index follows the file: the published entity carries the alias the file now has.
        #expect(context.store.content.entities.first { $0.id == Self.path }?.aliases == model.aliases)
        // A second add of the same alias is refused and leaves the bytes alone.
        #expect(await model.addAlias(alias, name: "Ece Yalın") == false)
        #expect(model.aliasErrorText == EntityAliasRules.Rejection.alreadyAlias.message)
        #expect(try Data(contentsOf: file) == expected)
    }

    @Test(arguments: [("alias-remove-inline-keeps-spelling", "Ecoş"), ("alias-remove-last-keeps-key", "Ece")])
    func removingWritesOnlyTheAliasesField(_ name: String, _ alias: String) async throws {
        let (context, model, file) = try await Self.context(name)
        defer { context.clean() }
        #expect(model.aliases.contains(alias))
        #expect(await model.removeAlias(alias))
        #expect(try Data(contentsOf: file) == Data(contentsOf: Self.writeCase(name, "expected.md")))
        #expect(!model.aliases.contains(alias))
        #expect(context.store.content.entities.first { $0.id == Self.path }?.aliases == model.aliases)
    }

    @Test func removingThenAddingBackReturnsTheOtherBytes() async throws {
        // Round trip: every byte outside the list is the input's, BOM and CRLF included.
        let (context, model, file) = try await Self.context("alias-add-crlf-bom")
        defer { context.clean() }
        let input = try Data(contentsOf: Self.writeCase("alias-add-crlf-bom", "input.md"))
        #expect(await model.addAlias("Ecoş", name: "Ece Yalın"))
        #expect(await model.removeAlias("Ecoş"))
        #expect(try Data(contentsOf: file) == input)
    }

    @Test func refusedAliasesWriteNothing() async throws {
        let (context, model, file) = try await Self.context("alias-add-inline-keeps-quotes-and-comment")
        defer { context.clean() }
        let input = try Data(contentsOf: file)
        let refused: [(String, EntityAliasRules.Rejection)] = [
            ("", .empty), (" \t\n", .empty), ("Ece|Ecoş", .invalidCharacter), ("[Ece", .invalidCharacter),
            ("Ece]", .invalidCharacter), ("Ece\nYalın", .invalidCharacter), ("Ece\u{0}", .invalidCharacter),
            ("ece yalın", .sameAsName), ("ECE YALIN", .sameAsName), ("ece", .alreadyAlias), ("E. YALIN", .alreadyAlias),
        ]
        for (text, rejection) in refused {
            #expect(await model.addAlias(text, name: "Ece Yalın") == false, "\(text.debugDescription)")
            #expect(model.aliasErrorText == rejection.message, "\(text.debugDescription)")
            #expect(try Data(contentsOf: file) == input)
        }
        model.clearAliasError()
        #expect(model.aliasErrorText == nil)
        #expect(model.errorText == nil)
    }

    @Test func turkishCapitalsDecideWhatIsTheSameName() throws {
        // İ/i and I/ı are two pairs: "IŞIK" is "ışık", never "işik".
        #expect(throws: EntityAliasRules.Rejection.sameAsName) {
            try EntityAliasRules.adding("IŞIK", to: [], name: "Işık")
        }
        #expect(throws: EntityAliasRules.Rejection.sameAsName) {
            try EntityAliasRules.adding("İREM", to: [], name: "irem")
        }
        #expect(throws: EntityAliasRules.Rejection.alreadyAlias) {
            try EntityAliasRules.adding("ırmak", to: ["Irmak"], name: "Irmak Demir")
        }
        #expect(try EntityAliasRules.adding("irmak", to: ["Irmak"], name: "Irmak Demir") == ["Irmak", "irmak"])
        #expect(try EntityAliasRules.adding("  Ecoş ", to: ["Ece"], name: "Ece Yalın") == ["Ece", "Ecoş"])
        #expect(EntityAliasRules.removing("Ece", from: ["Ece", "ece", "Ecoş"]) == ["ece", "Ecoş"])
    }

    @Test func anAliasAnotherRecordUsesIsAddedAndReported() async throws {
        let (context, model, file) = try await Self.context("alias-add-missing-key")
        defer { context.clean() }
        let other = context.root.appendingPathComponent("people/Ece Tunç.md")
        try Data("---\ntype: person\nname: Ece Tunç\naliases: [ECE]\n---\n".utf8).write(to: other)
        await context.store.refreshAndSettle(rebuild: true)
        let entities = context.store.content.entities
        #expect(EntityAliasRules.conflicts(" ece ", path: Self.path, entities: entities).map(\.name) == ["Ece Tunç"])
        #expect(EntityAliasRules.conflicts("Ece Yalın", path: Self.path, entities: entities).isEmpty)
        #expect(EntityAliasRules.conflicts("", path: Self.path, entities: entities).isEmpty)
        // The ambiguity is the recognizer's to ask about; the page does not refuse the alias.
        let otherBytes = try Data(contentsOf: other)
        #expect(await model.addAlias("Ece", name: "Ece Yalın"))
        #expect(try Data(contentsOf: file) == Data(contentsOf: Self.writeCase("alias-add-missing-key", "expected.md")))
        #expect(try Data(contentsOf: other) == otherBytes)
    }

    @Test func aListTheAppCannotReadIsRefused() async throws {
        let (context, model, file) = try await Self.context("alias-add-missing-key")
        defer { context.clean() }
        // The file changes after the page loaded: the write reads it again and refuses the mapping.
        let mapping = Data("---\ntype: person\nname: Ece Yalın\naliases:\n  kısa: Ece\n---\n".utf8)
        try mapping.write(to: file)
        #expect(await model.addAlias("Ecoş", name: "Ece Yalın") == false)
        #expect(model.aliasErrorText == EntityAliasRules.Rejection.notEditable.message)
        #expect(try Data(contentsOf: file) == mapping)
    }

    @Test func theWriteUsesTheListOnDiskNotTheLoadedOne() async throws {
        let (context, model, file) = try await Self.context("alias-add-single-value")
        defer { context.clean() }
        #expect(model.aliases == ["Ece"])
        // Another device adds an alias before this page reloads.
        try Data("---\ntype: person\nname: Ece Yalın\naliases: [Ece, \"E. Yalın\"]\n---\n".utf8).write(to: file)
        #expect(await model.addAlias("Ecoş", name: "Ece Yalın"))
        let expected = "---\ntype: person\nname: Ece Yalın\naliases: [Ece, \"E. Yalın\", Ecoş]\n---\n"
        #expect(try Data(contentsOf: file) == Data(expected.utf8))
    }

    @Test func historyLinesStayAsWrittenAndTheNextEntryIsRecognized() async throws {
        let (context, model, _) = try await Self.context("alias-add-single-value")
        defer { context.clean() }
        let day = context.root.appendingPathComponent("diary/2026-10-01.md")
        try FileManager.default.createDirectory(at: day.deletingLastPathComponent(), withIntermediateDirectories: true)
        let written = Data("---\ntype: diary\ndate: 2026-10-01\n---\n## Events\n- 10:00 Ecoş ile yürüdük.\n".utf8)
        try written.write(to: day)
        await context.store.refreshAndSettle(rebuild: true)
        #expect(await model.addAlias("Ecoş", name: "Ece Yalın"))
        // The earlier line is not rewritten into a link; it becomes an unlinked mention to confirm.
        #expect(try Data(contentsOf: day) == written)
        #expect(context.store.content.entities.first { $0.id == Self.path }?.aliases == ["Ece", "Ecoş"])
    }

    @Test func theFileIsWrittenBeforeTheIndexIsPublished() async throws {
        let (context, model, file) = try await Self.context("alias-add-crlf-bom")
        defer { context.clean() }
        let expected = try Data(contentsOf: Self.writeCase("alias-add-crlf-bom", "expected.md"))
        // `onChange` runs just before the published index content is replaced: the file is already written.
        let seen = SeenBytes()
        withObservationTracking {
            _ = context.store.content
        } onChange: {
            seen.set(try? Data(contentsOf: file))
        }
        #expect(await model.addAlias("Ecoş", name: "Ece Yalın"))
        #expect(seen.value == expected)
        // The index can always be rebuilt from the file alone.
        await context.store.refreshAndSettle(rebuild: true)
        #expect(context.store.content.entities.first { $0.id == Self.path }?.aliases == ["Ece", "Ecoş"])
    }
}

private final class SeenBytes: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: Data?
    var value: Data? { lock.withLock { bytes } }
    func set(_ data: Data?) { lock.withLock { bytes = data } }
}
