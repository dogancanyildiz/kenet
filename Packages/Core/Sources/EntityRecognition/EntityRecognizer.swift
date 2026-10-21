import VaultFormat

/// Recognizes supplied entity names without filesystem, database or framework dependencies.
public enum EntityRecognizer {
    /// Finds known mentions in source order; ambiguous candidates remain unbound.
    public static func recognize(
        _ text: String, entities: [KnownEntity], usage: [EntityUsage] = [], context: RecognitionContext = .init()
    ) -> [Mention] {
        let mentions = scan(text, entities: entities, context: context).known
        return ranked(mentions, usage: usage, context: context)
    }

    /// Finds explicit uppercase spellings that matched no known name.
    public static func unknownMentions(
        _ text: String, entities: [KnownEntity], context: RecognitionContext = .init()
    ) -> [UnknownMention] {
        scan(text, entities: entities, context: context).unknown
    }

    /// Whether a spelling is recognized only after an at sign: one made of decimal digits alone, such as
    /// `12` or `2026`. Callers that write a picked name into text keep its at sign when this holds.
    public static func needsExplicitMention(_ spelling: String) -> Bool {
        !spelling.isEmpty && spelling.allSatisfy(RecognitionLine.digit)
    }

    static func scan(
        _ text: String, entities: [KnownEntity], context: RecognitionContext
    ) -> (known: [Mention], unknown: [UnknownMention]) {
        var patterns: [String: [NamePattern]] = [:]
        for entity in entities {
            for (index, spelling) in ([entity.name] + entity.aliases).enumerated() {
                if let pattern = NamePattern(entity: entity, spelling: spelling, isAlias: index > 0),
                    let first = pattern.tokens.first
                {
                    patterns[first, default: []].append(pattern)
                }
            }
        }
        var known: [Mention] = []
        var unknown: [UnknownMention] = []
        let document = RawDocument(bytes: text.utf8)
        var scanner = RecognitionScanner(document: document)
        // A task's marker, checkbox, fields and identifier and an event's clock are never the user's words.
        let regions = LineTextRegion.regions(in: document)
        for (number, raw) in document.lines.enumerated() {
            var excluded = scanner.excludedBytes(raw.content, insideFence: context.insideFence)
            regions[number]?.exclude(from: &excluded)
            let line = RecognitionLine(raw.content, excluded: excluded)
            var start = 0
            while start < line.characters.count {
                let explicit = line.isExplicit(at: start)
                guard line.available(start), !line.word(start - 1), !line.suffixStart(start), line.safeStart(start),
                    !explicit || line.safeStart(start - 1)
                else {
                    start += 1
                    continue
                }
                let options = patterns[nameComparisonFold(String(line.characters[start]))] ?? []
                let matches = options.compactMap { pattern -> (NamePattern, Int)? in
                    // A digit-only spelling is a number wherever it is written plainly; only `@` makes it a name.
                    guard explicit || !pattern.isDigitOnly, let end = pattern.end(in: line, from: start) else {
                        return nil
                    }
                    return (pattern, end)
                }
                if !matches.isEmpty {
                    for end in Set(matches.map { $0.1 }) {
                        let longest = matches.filter { $0.1 == end }
                        var seen: Set<String> = []
                        let candidates = longest.sorted { !$0.0.isAlias && $1.0.isAlias }
                            .map { $0.0.entity }.filter { seen.insert($0.file).inserted }
                        known.append(
                            Mention(
                                position: line.position(line: number, range: start..<end),
                                spelling: line.spelling(start..<end), candidates: candidates,
                                isCaseMismatch: longest.allSatisfy { $0.0.caseMismatch(in: line, range: start..<end) },
                                isExplicit: explicit,
                                isAlias: longest.allSatisfy { $0.0.isAlias }))
                    }
                    start += 1
                } else if explicit, let end = unknownEnd(in: line, from: start) {
                    unknown.append(
                        UnknownMention(
                            position: line.position(line: number, range: start..<end),
                            spelling: line.spelling(start..<end)))
                    start = end
                } else {
                    start += 1
                }
            }
        }
        let longestFirst = known.sorted {
            if $0.spelling.count != $1.spelling.count { return $0.spelling.count > $1.spelling.count }
            if $0.isAlias != $1.isAlias { return !$0.isAlias }
            if $0.position.line != $1.position.line { return $0.position.line < $1.position.line }
            return $0.position.byteRange.lowerBound < $1.position.byteRange.lowerBound
        }
        var occupied: [Int: Set<Int>] = [:]
        known = longestFirst.filter { mention in
            let line = mention.position.line
            let range = mention.position.byteRange
            guard !range.contains(where: { occupied[line]?.contains($0) == true }) else { return false }
            occupied[line, default: []].formUnion(range)
            return true
        }.sorted {
            ($0.position.line, $0.position.byteRange.lowerBound) < ($1.position.line, $1.position.byteRange.lowerBound)
        }
        unknown = unknown.filter { mention in
            !mention.position.byteRange.contains { occupied[mention.position.line]?.contains($0) == true }
        }
        return (known, unknown)
    }

    private static func unknownEnd(in line: RecognitionLine, from start: Int) -> Int? {
        var cursor = start
        var end = start
        for _ in 0..<4 {
            guard cursor < line.characters.count, line.available(cursor), line.characters[cursor].isUppercase else {
                break
            }
            while cursor < line.characters.count, line.available(cursor), line.word(cursor) {
                cursor += 1
            }
            end = cursor
            while cursor < line.characters.count, RecognitionLine.separator(line.characters[cursor]) { cursor += 1 }
            guard cursor > end else { break }
        }
        return end > start && line.safeEnd(end) ? end : nil
    }
}
