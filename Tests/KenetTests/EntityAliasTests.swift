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
            ("Ece\u{2028}Yalın", .invalidCharacter), ("Ece\u{2029}Yalın", .invalidCharacter),
            // Characters that draw nothing: zero-width space, byte order mark, direction marks, soft hyphen.
            ("E\u{200B}ce", .invalidCharacter), ("\u{FEFF}Ecoş", .invalidCharacter),
            ("Ecoş\u{200E}", .invalidCharacter),
            ("Ecoş\u{200F}", .invalidCharacter), ("Eco\u{00AD}ş", .invalidCharacter),
            // A joiner with no emoji on both sides joins nothing.
            ("Eco\u{200D}ş", .invalidCharacter), ("Ecoş\u{200D}", .invalidCharacter),
            ("\u{200D}Ecoş", .invalidCharacter),
            ("1\u{200D}2", .invalidCharacter), ("Ecoş\u{E0067}", .invalidCharacter),
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

    @Test func emojiSequencesKeepTheirJoinersAndTags() async throws {
        let (context, model, file) = try await Self.context("alias-add-single-value")
        defer { context.clean() }
        // Family (joiners), rainbow flag (variation selector before the joiner), a skin tone before
        // the joiner, and a flag spelled with tag letters.
        let emoji = [
            "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467} Ailem", "\u{1F3F3}\u{FE0F}\u{200D}\u{1F308}",
            "\u{1F469}\u{1F3FD}\u{200D}\u{1F4BB}",
            "\u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}",
        ]
        for alias in emoji {
            #expect(!EntityAliasRules.hasRefusedCharacter(alias), "\(alias.unicodeScalars.map(\.value))")
            #expect(await model.addAlias(alias, name: "Ece Yalın"))
        }
        #expect(model.aliases == ["Ece"] + emoji)
        // The file reads back the same scalars.
        let written = RawDocument(bytes: try Data(contentsOf: file))
        guard case .parsed(let frontmatter) = written.frontmatter else {
            Issue.record("frontmatter unreadable")
            return
        }
        let items = frontmatter.field(named: "aliases")?.value.listItems?.map { Array($0.text.unicodeScalars) }
        #expect(items == (["Ece"] + emoji).map { Array($0.unicodeScalars) })
    }

    @Test func removingComparesBytesAndTakesOneItem() async throws {
        let composed = "\u{015E}ule"  // Ş as one scalar
        let decomposed = "S\u{0327}ule"  // S + combining cedilla: equal to Swift, other bytes
        #expect(composed == decomposed && !composed.utf8.elementsEqual(decomposed.utf8))
        func bytes(_ list: [String]) -> [[UInt8]] { list.map { Array($0.utf8) } }
        #expect(
            bytes(EntityAliasRules.removing(decomposed, from: [composed, decomposed, "Ece"]))
                == bytes([composed, "Ece"]))
        #expect(
            bytes(EntityAliasRules.removing(composed, from: [decomposed, composed, "Ece"]))
                == bytes([decomposed, "Ece"]))
        // Byte-equal items: only the first goes. A spelling that is not there removes nothing.
        #expect(EntityAliasRules.removing("Ece", from: ["Ece", "Ecoş", "Ece"]) == ["Ecoş", "Ece"])
        #expect(bytes(EntityAliasRules.removing(decomposed, from: [composed])) == bytes([composed]))
        // Each chip has its own identity, so each removes its own item.
        let chips = EntityAliasRules.chips([composed, " ", decomposed, "Ece", "Ece"])
        #expect(chips.count == 4 && Set(chips.map(\.id)).count == 4)
        #expect(bytes(chips.map(\.text)) == bytes([composed, decomposed, "Ece", "Ece"]))

        let (context, model, file) = try await Self.context("alias-add-single-value")
        defer { context.clean() }
        let head = "---\ntype: person\nname: Ece Yalın\naliases: ["
        try Data((head + composed + ", " + decomposed + ", Ece]\n---\n").utf8).write(to: file)
        await context.store.refreshAndSettle(rebuild: true)
        await model.load()
        #expect(bytes(model.aliases) == bytes([composed, decomposed, "Ece"]))
        #expect(await model.removeAlias(decomposed))
        #expect(try Data(contentsOf: file) == Data((head + composed + ", Ece]\n---\n").utf8))
        #expect(bytes(model.aliases) == bytes([composed, "Ece"]))
    }

    @Test func aChangeAskedForDuringAWriteWaitsAndIsWritten() async throws {
        let (context, model, file) = try await Self.context("alias-add-single-value")
        defer { context.clean() }
        // The second and third changes are asked for while the first write holds its turn.
        let later = LaterChanges()
        context.store.testingEditTurnDidArrive = {
            guard later.tasks.isEmpty else { return }
            #expect(model.isWriting)
            later.tasks = [
                Task { await model.addAlias("Ece Hanım", name: "Ece Yalın") },
                Task { await model.removeAlias("Ece") },
            ]
            // Let both reach the model before the first write goes on.
            for _ in 0..<10 { await Task.yield() }
        }
        #expect(await model.addAlias("Ecoş", name: "Ece Yalın"))
        #expect(later.tasks.count == 2)
        for task in later.tasks { #expect(await task.value) }
        context.store.testingEditTurnDidArrive = nil
        #expect(model.aliasErrorText == nil)
        #expect(model.aliases == ["Ecoş", "Ece Hanım"])
        let expected = "---\ntype: person\nname: Ece Yalın\naliases: [Ecoş, Ece Hanım]\n---\n"
        #expect(try Data(contentsOf: file) == Data(expected.utf8))
    }

    @Test func theFieldKeepsWhatWasTypedDuringTheWrite() {
        #expect(EntityAliasSheet.draft("Ecoş", afterAdding: "Ecoş", added: true) == "")
        // The user went on typing the next alias while the first was written.
        #expect(EntityAliasSheet.draft("Ece Hanım", afterAdding: "Ecoş", added: true) == "Ece Hanım")
        #expect(EntityAliasSheet.draft("Ecoş", afterAdding: "Ecoş", added: false) == "Ecoş")
    }

    @Test func aChangeThatCannotStartSaysSo() async throws {
        let (context, _, file) = try await Self.context("alias-add-single-value")
        defer { context.clean() }
        let input = try Data(contentsOf: file)
        // A model that never loaded cannot edit: the refusal is told, not dropped.
        let unloaded = EntityDetailModel(store: context.store, path: Self.path)
        #expect(await unloaded.addAlias("Ecoş", name: "Ece Yalın") == false)
        #expect(unloaded.aliasErrorText != nil)
        #expect(try Data(contentsOf: file) == input)
    }

    @Test func theFileHasTheAliasWhileTheIndexStillHasTheOldList() async throws {
        let (context, model, file) = try await Self.context("alias-add-crlf-bom")
        defer { context.clean() }
        let expected = try Data(contentsOf: Self.writeCase("alias-add-crlf-bom", "expected.md"))
        let store = context.store
        // `onChange` runs just before the published index content is replaced. At that moment the
        // file must already be the new one and the published index still the old one: file first.
        let seen = SeenWrite()
        withObservationTracking {
            _ = store.content
        } onChange: {
            let indexed = MainActor.assumeIsolated { store.content.entities.first { $0.id == Self.path }?.aliases }
            seen.set(file: try? Data(contentsOf: file), indexed: indexed)
        }
        #expect(await model.addAlias("Ecoş", name: "Ece Yalın"))
        #expect(seen.file == expected)
        #expect(seen.indexed == ["Ece"])
        #expect(store.content.entities.first { $0.id == Self.path }?.aliases == ["Ece", "Ecoş"])
        // The index can always be rebuilt from the file alone.
        await store.refreshAndSettle(rebuild: true)
        #expect(store.content.entities.first { $0.id == Self.path }?.aliases == ["Ece", "Ecoş"])
    }
}

@MainActor private final class LaterChanges {
    var tasks: [Task<Bool, Never>] = []
}

private final class SeenWrite: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: Data?
    private var aliases: [String]?
    var file: Data? { lock.withLock { bytes } }
    var indexed: [String]? { lock.withLock { aliases } }
    func set(file: Data?, indexed: [String]?) {
        lock.withLock {
            bytes = file
            aliases = indexed
        }
    }
}
