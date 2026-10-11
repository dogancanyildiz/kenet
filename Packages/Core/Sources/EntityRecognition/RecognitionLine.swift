/// A grapheme-based view that retains physical UTF-8 positions.
struct RecognitionLine {
    let characters: [Character]
    let offsets: [Int]
    let bytes: [UInt8]
    var excluded: [Bool]

    init(_ bytes: [UInt8], excluded: [Bool]) {
        self.bytes = bytes
        characters = Array(String(decoding: bytes, as: UTF8.self))
        var positions = [0]
        for character in characters { positions.append(positions.last! + character.utf8.count) }
        offsets = positions
        self.excluded = excluded
        var start = 0
        while start < characters.count {
            if characters[start].isWhitespace {
                start += 1
                continue
            }
            var end = start + 1
            while end < characters.count, !characters[end].isWhitespace { end += 1 }
            let token = String(characters[start..<end])
            let containsAddress = token.contains("@") && !Self.explicitToken(Array(characters[start..<end]))
            let dottedLetters = (start..<end).contains { index in
                index > start && index + 1 < end && characters[index] == "."
                    && characters[index - 1].isLetter && characters[index + 1].isLetter
            }
            if token.contains("://") || containsAddress || dottedLetters || token.hasPrefix("#") || token.hasPrefix("^")
            {
                for byte in offsets[start]..<offsets[end] { self.excluded[byte] = true }
            }
            start = end
        }
    }

    private static func explicitToken(_ token: [Character]) -> Bool {
        // Opening punctuation may precede a word-start at sign, as in (@Deniz).
        guard let at = token.firstIndex(of: "@"), !token[..<at].contains(where: { $0.isLetter || $0.isNumber }),
            !token.dropFirst(at + 1).contains("@")
        else { return false }
        return true
    }

    func isExplicit(at index: Int) -> Bool {
        index > 0 && characters[index - 1] == "@" && !word(index - 2) && available(index - 1)
    }

    func safeStart(_ index: Int) -> Bool {
        index == 0 || !"[!\\#^|".contains(characters[index - 1])
    }

    func safeEnd(_ index: Int) -> Bool {
        index == characters.count || characters[index] != "]"
    }

    static func separator(_ character: Character) -> Bool {
        character.isWhitespace && character != "\u{2028}" && character != "\u{0085}"
    }

    func available(_ index: Int) -> Bool {
        !excluded[offsets[index]..<offsets[index + 1]].contains(true)
    }

    func spelling(_ range: Range<Int>) -> String {
        String(decoding: bytes[offsets[range.lowerBound]..<offsets[range.upperBound]], as: UTF8.self)
    }

    func position(line: Int, range: Range<Int>) -> MentionPosition {
        MentionPosition(line: line, byteRange: offsets[range.lowerBound]..<offsets[range.upperBound])
    }

    func suffixStart(_ index: Int) -> Bool {
        guard index > 1, characters[index - 1] == "'" || characters[index - 1] == "’" else { return false }
        if word(index - 2) { return true }
        // A generated or existing wikilink leaves the same apostrophe suffix outside its brackets.
        return index > 2 && characters[index - 2] == "]" && characters[index - 3] == "]" && !available(index - 2)
    }

    func word(_ index: Int) -> Bool {
        characters.indices.contains(index) && (characters[index].isLetter || characters[index].isNumber)
    }

    /// Punctuation that joins digits into one time, date, decimal or range, with its full-width and Arabic forms.
    static let numericSeparators: Set<Character> = [
        ":", ".", ",", "-", "/", "'", "’", "–", "：", "．", "，", "－", "／", "＇", "٫", "٬",
    ]

    /// A decimal digit of any script; fractions, superscripts, Roman numerals and keycaps are not.
    static func digit(_ character: Character) -> Bool {
        let scalars = character.unicodeScalars
        return scalars.count == 1 && scalars.first?.properties.generalCategory == .decimalNumber
    }

    /// Whether a separator joins the range to a digit on its other side, with nothing in between.
    func joinsNumber(_ range: Range<Int>) -> Bool {
        let after = range.upperBound
        if characters.indices.contains(after + 1), Self.numericSeparators.contains(characters[after]),
            Self.digit(characters[after + 1])
        {
            return true
        }
        let before = range.lowerBound - 1
        guard before > 0, Self.numericSeparators.contains(characters[before]) else { return false }
        if Self.digit(characters[before - 1]) { return true }
        // A part that is already linked keeps its place in the expression: `[[12]]:30`.
        return before > 2 && characters[before - 1] == "]" && characters[before - 2] == "]"
            && Self.digit(characters[before - 3]) && !available(before - 1)
    }
}

/// Whitespace is flexible while Unicode canonical equality preserves the comparison rule.
struct NamePattern {
    let entity: KnownEntity
    let isAlias: Bool
    let tokens: [String]
    let initialLetter: Character?
    /// Whether the spelling is nothing but decimal digits, such as `12` or `2026`.
    let isDigitOnly: Bool

    init?(entity: KnownEntity, spelling: String, isAlias: Bool) {
        guard !spelling.isEmpty, !spelling.contains("\n"), !spelling.contains("\r"), !spelling.contains("\u{2028}"),
            !spelling.contains("\u{0085}")
        else { return nil }
        let tokens = Array(spelling).reduce(into: [String]()) { tokens, character in
            if RecognitionLine.separator(character) {
                if tokens.last != " " { tokens.append(" ") }
            } else {
                tokens.append(String(character).lowercased())
            }
        }
        guard tokens.first != " ", tokens.last != " " else { return nil }
        self.entity = entity
        self.isAlias = isAlias
        self.tokens = tokens
        initialLetter = spelling.first(where: { $0.isLetter })
        isDigitOnly = spelling.allSatisfy(RecognitionLine.digit)
    }

    func caseMismatch(in line: RecognitionLine, range: Range<Int>) -> Bool {
        guard let initialLetter, let source = line.characters[range].first(where: { $0.isLetter }) else { return false }
        return source.isUppercase != initialLetter.isUppercase || source.isLowercase != initialLetter.isLowercase
    }

    func end(in line: RecognitionLine, from start: Int) -> Int? {
        var cursor = start
        for token in tokens {
            guard cursor < line.characters.count, line.available(cursor) else { return nil }
            if token == " " {
                guard RecognitionLine.separator(line.characters[cursor]) else { return nil }
                repeat {
                    cursor += 1
                } while cursor < line.characters.count && RecognitionLine.separator(line.characters[cursor])
            } else {
                // String equality performs canonical Unicode comparison without Foundation.
                guard String(line.characters[cursor]).lowercased() == token else { return nil }
                cursor += 1
            }
        }
        guard !line.word(cursor), line.safeEnd(cursor) else { return nil }
        return cursor
    }
}
