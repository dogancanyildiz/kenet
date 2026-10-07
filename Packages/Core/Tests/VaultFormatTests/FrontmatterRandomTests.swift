import Testing
import VaultFormat

/// Arbitrary input must be read without crashing, and whatever an edit accepts must come out intact.
///
/// The generators are seeded with a constant, so every run checks exactly the same inputs.
struct FrontmatterRandomTests {
    static let seed: UInt64 = 0x6672_6F6E_746D_6174

    /// Pieces that matter to the frontmatter reader, so that short lines hit its edge cases often.
    static let pieces = [
        "---", "key", "key", "a", "ş", ":", ": ", ": ", ": ", " ", "- ", "- ", "-", "#", " #", "\"", "'", "[", "]",
        ",", ", ", "{", "}", "|", ">", "&", "*", "!", "\t", "\\", "true", "25", "~", "2026-10-02", "\u{FEFF}", "🛫",
        "?", "...", "<<", "!!str ", "&a ", "*a", "1e5", "0x1F", "no", "null", "|-", ">2", "\u{2028}", "\u{1}", ".5",
    ]
    static let indents = ["", "", "", "  ", "  ", "    ", "\t"]
    /// Whole lines of the supported subset, mixed in so that random text also builds on valid structure.
    static let validLines = [
        "key:", "a:", "  a: 25", "  ş: \"x\"", "  - a", "- 'ş'", "h: [a, 'b']", "i: true", "b: &a x", "c: *a",
        "  - a: 1", "    b: 2", "    - c", "d: |", "  metin", "e: {a: 1, b: [c]}", "f: !!str 5", "  b:", "g: uzun",
        "  devam", "# yorum", "  # yorum", "", "  ", "j: 1e5", "k: no", "l: .5", "m: 2026-1-2", "n: >-", "o: ~",
        "p: \"x\\ty\"", "r: 'it''s'", "s: 012", "t: +5", "u: -0.50", "v: True", "y: 14:30", "z: [1, 2.0, x y]",
    ]

    static let lineEndings = ["\n", "\n", "\n", "\r\n", "\r"]

    @Test func uniformRandomBytesAreReadWithoutCrashing() {
        var generator = SeededGenerator(seed: Self.seed)

        for iteration in 0..<3000 {
            let count = Int.random(in: 0...96, using: &generator)
            var input = (0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
            if iteration % 2 == 0 { input = Array("---\n".utf8) + input + Array("\n---\n".utf8) }

            let violations = frontmatterStructureViolations(of: RawDocument(bytes: input))
            #expect(violations == [], "iteration \(iteration)")
            if !violations.isEmpty { break }
        }
    }

    @Test func syntaxHeavyRandomTextIsReadWithoutCrashing() throws {
        var generator = SeededGenerator(seed: Self.seed ^ 0xFFFF_FFFF)
        var sawParsed = false
        var sawUnreadable = false
        var sawAbsent = false
        var sawRaw = false
        var sawList = false
        var sawMapping = false
        let samples = try SampleWriter()

        for iteration in 0..<40000 {
            var text = iteration % 8 == 0 ? "" : "---\n"
            for _ in 0..<Int.random(in: 0...6, using: &generator) {
                if Int.random(in: 0..<8, using: &generator) > 0 {
                    text += try #require(Self.validLines.randomElement(using: &generator))
                } else {
                    text += try #require(Self.indents.randomElement(using: &generator))
                    for _ in 0..<Int.random(in: 0...5, using: &generator) {
                        text += try #require(Self.pieces.randomElement(using: &generator))
                    }
                }
                text += try #require(Self.lineEndings.randomElement(using: &generator))
            }
            if iteration % 3 != 0 { text += "---\n" }
            var input = Array(text.utf8)
            if iteration % 16 == 0 { input.append(0xFF) }
            let document = RawDocument(bytes: input)

            let violations = frontmatterStructureViolations(of: document)
            #expect(violations == [], "iteration \(iteration)")
            if !violations.isEmpty { break }
            try samples.add(document)

            switch document.frontmatter {
            case .absent: sawAbsent = true
            case .unreadable: sawUnreadable = true
            case .parsed(let frontmatter):
                sawParsed = true
                for field in frontmatter.fields {
                    switch field.value {
                    case .raw: sawRaw = true
                    case .list: sawList = true
                    case .mapping: sawMapping = true
                    case .scalar: break
                    }
                }
            }
        }

        // The generator must actually reach the cases this test exists for.
        #expect(sawParsed && sawUnreadable && sawAbsent)
        #expect(sawRaw && sawList && sawMapping)
    }

    /// Every fixture cut at every byte position: frontmatter that stops anywhere must still be read safely.
    @Test(arguments: try Fixtures.markdownPaths())
    func truncatedFixtureIsReadWithoutCrashing(path: String) throws {
        let original = try Fixtures.bytes(at: path)

        for length in RoundTripTests.truncationLengths(for: original.count) {
            let violations = frontmatterStructureViolations(of: RawDocument(bytes: Array(original.prefix(length))))
            #expect(violations == [], "truncated to \(length) of \(original.count) bytes")
            if !violations.isEmpty { break }
        }
    }

    // MARK: Random edits

    static let blockLines = [
        "type: person", "name: Deniz Arıkan", "name: \"Deniz\"  # yorum", "aliases: [Deniz, 'D.']", "aliases:",
        "  - Deniz", "  - \"Deniz abi\" # yorum", "- sıfır girinti", "goals:", "goals: # bugün", "  spor: true",
        "  kitap: 25", "    derin: 1", "# yorum", "  # girintili yorum", "", "not: |", "  metin", "kopya: *a",
        "key: [a, [b]]", "bozuk satır", "aliases: Deniz", "tags: []", "\"tırnaklı anahtar\": 1", "boş:",
        "x: {a: 1}", "tags:", "- a", "konum: 20.0290", "çapa: &a değer", "uzun: ilk", "  devam",
        "adres: https://example.com/a?b", "adres: [a, b] # yorum", "", "",
    ]
    /// Whole fields, so that most blocks are readable and hold lists and mappings to edit.
    static let blockFields: [[String]] = [
        ["type: person"], ["name: \"Deniz\"  # yorum"], ["aliases: [Deniz, 'D.']"],
        ["aliases:", "  - Deniz", "  - D."],
        ["aliases:", "  - Deniz", "  # ara yorum", "  - \"Deniz abi\" # yorum", "", "  - D."], ["tags:", "- a", "- b"],
        ["goals:", "  spor: true", "  kitap: 25"], ["goals: # bugün", "    spor: false", "", "    su: 8 # bardak"],
        ["boş:"], ["konum: 20.0290"], ["not: |", "  metin", "", "  devam"], ["x: {a: 1}"], ["key: [a, [b]]"],
        ["uzun: ilk", "  devam"], ["adres: https://example.com/a?b"], [""], [""], ["# yorum"], ["  # girintili yorum"],
    ]
    static let bodyLines = ["Gövde.", "", "---", "## Events", "- [ ] iş", "key: değer"]
    static let keys = [
        "type", "name", "aliases", "goals", "tags", "not", "kopya", "key", "boş", "x", "konum", "yeni",
        "tırnaklı anahtar", "a: b", "çapa", "uzun", "adres",
    ]
    static let entryKeys = ["spor", "kitap", "su", "derin", "# not"]
    static let literals: [FrontmatterLiteral] = [
        .text("Deniz"), .text("Deniz abi"), .text("D."), .text("Selin Korkmaz"), .text(""), .text("true"),
        .text("a: b"), .text("[[Liman Ofis]]"), .text("- madde"), .text("a, b"), .text(" boşluk "),
        .text("satır\nsonu"), .text("25"), .boolean(true), .boolean(false), .integer(25), .integer(-3),
        .number("20.029"), .number("1.5"), .text("#etiket"), .text("'tek'"), .text("https://example.com/a?b"),
    ]
    static let lineEndingChoices = ["\n", "\r\n", "\r"]
    static let mixedLineEndings = ["\r", "\r", "\r", "\n", "\r\n"]

    /// A document that usually starts with a frontmatter block built from whole fields, mixed
    /// with single lines of the subset, of raw fields and of broken input. One document in
    /// three mixes its line endings.
    static func randomDocument(using generator: inout SeededGenerator) -> RawDocument {
        var lines: [String] = []
        if Int.random(in: 0..<12, using: &generator) > 0 {
            lines.append("---")
            for _ in 0..<Int.random(in: 0...6, using: &generator) {
                if Int.random(in: 0..<4, using: &generator) > 0 {
                    lines += blockFields.randomElement(using: &generator) ?? []
                } else {
                    lines.append(blockLines.randomElement(using: &generator) ?? "")
                }
            }
            if Int.random(in: 0..<12, using: &generator) > 0 { lines.append("---") }
        }
        for _ in 0..<Int.random(in: 0...3, using: &generator) {
            lines.append(bodyLines.randomElement(using: &generator) ?? "")
        }

        let mixesEndings = Int.random(in: 0..<3, using: &generator) == 0
        let ending = lineEndingChoices.randomElement(using: &generator) ?? "\n"
        var text = Int.random(in: 0..<8, using: &generator) == 0 ? "\u{FEFF}" : ""
        for (index, line) in lines.enumerated() {
            text += line
            let isLast = index == lines.count - 1
            if isLast, Int.random(in: 0..<4, using: &generator) == 0 { break }
            if !mixesEndings {
                text += ending
            } else if line.isEmpty {
                // An empty LF line after a CR line is where joined endings can swallow a byte.
                text += "\n"
            } else {
                text += mixedLineEndings.randomElement(using: &generator) ?? "\r"
            }
        }
        return RawDocument(bytes: Array(text.utf8))
    }

    static func randomOperation(using generator: inout SeededGenerator) -> FrontmatterOperation {
        let key = keys.randomElement(using: &generator) ?? "type"
        let entry = entryKeys.randomElement(using: &generator) ?? "spor"
        let value = literals.randomElement(using: &generator) ?? .boolean(true)
        switch Int.random(in: 0..<8, using: &generator) {
        case 0, 1: return .setValue(key: key, value: value)
        case 2, 3:
            let items = (0..<Int.random(in: 0...4, using: &generator)).map { _ in
                literals.randomElement(using: &generator) ?? .boolean(true)
            }
            return .setList(key: key, items: items)
        case 4, 5: return .setEntry(key: key, entry: entry, value: value)
        case 6: return .removeEntry(key: key, entry: entry)
        default: return .removeField(key: key)
        }
    }

    @Test func randomEditsChangeOnlyTheirTargetOrAreRefusedForAReason() throws {
        var generator = SeededGenerator(seed: Self.seed ^ 0xABCD)
        var successes: [String: Int] = [:]
        var refusals: [String: Int] = [:]
        var mixedSuccesses = 0
        let samples = try SampleWriter()

        for iteration in 0..<30000 {
            let before = Self.randomDocument(using: &generator)
            let operation = Self.randomOperation(using: &generator)
            let context: Comment = "iteration \(iteration):\n\(visible(before.serialized()))"
            let name = String(operation.description.prefix { $0 != " " })
            try samples.add(before)

            do {
                let after = try operation.apply(to: before)
                let violations = frontmatterEditViolations(before: before, after: after, operation: operation)
                #expect(violations == [], context)
                if !violations.isEmpty { break }
                successes[name, default: 0] += 1
                if Set(before.lines.compactMap(\.ending)).count > 1, after != before { mixedSuccesses += 1 }
                try samples.add(after)
            } catch let error as EditError {
                let reason = Self.reasonIsJustified(error, before: before, operation: operation)
                #expect(reason, "\(error) \(operation)\n\(context)")
                if !reason { break }
                refusals[error.fixtureName, default: 0] += 1
            }
        }

        // The generator must actually reach every operation and every refusal a valid file can cause.
        for name in ["set-value", "set-list", "set-entry", "remove-entry", "remove-field"] {
            #expect(successes[name, default: 0] > 500, "\(name): \(successes)")
        }
        for name in ["unreadable-frontmatter", "raw-field", "not-a-mapping"] {
            #expect(refusals[name, default: 0] > 20, "\(name): \(refusals)")
        }
        #expect(mixedSuccesses > 500, "edits of files with mixed line endings: \(mixedSuccesses)")
    }

    /// Whether the file really is in the state the error claims. Errors that only a faulty edit
    /// could cause (a bad line range, a line break in a written line) are never justified.
    static func reasonIsJustified(_ error: EditError, before: RawDocument, operation: FrontmatterOperation) -> Bool {
        var field: FrontmatterField?
        if case .parsed(let frontmatter) = before.frontmatter {
            field = frontmatter.field(named: operation.key)
        }
        switch error {
        case .unreadableFrontmatter:
            return before.frontmatter == .unreadable
        case .rawField:
            if case .raw = field?.value { return true }
            return false
        case .notAMapping:
            guard case .setEntry = operation else { return false }
            switch field?.value {
            case .scalar(let scalar): return !scalar.raw.isEmpty
            case .list: return true
            case .mapping, .raw, nil: return false
            }
        case .readOnlyDocument, .invalidKey, .invalidValue, .invalidLineRange, .lineBreakInContent, .emptySectionAppend,
            .sectionNotWritable, .targetNotFound, .emptyText, .contentNotRepresentable, .identifierExhausted:
            return false
        }
    }
}
