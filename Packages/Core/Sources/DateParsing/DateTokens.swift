import VaultFormat

struct DateToken: Sendable {
    let text: String
    let range: Range<Int>

    func key(_ language: Language) -> String {
        if language == .english { return text.lowercased() }
        return text.map { character in
            switch character {
            case "I": "ı"
            case "İ": "i"
            default: String(character).lowercased()
            }
        }.joined()
    }
}

struct DateTokens: Sendable {
    let bytes: [UInt8]
    let tokens: [DateToken]

    init(_ text: String) {
        bytes = Array(text.utf8)
        let document = RawDocument(bytes: bytes)
        var scanner = RecognitionScanner(document: document)
        var result: [DateToken] = []
        var offset = document.hasByteOrderMark ? 3 : 0
        for line in document.lines {
            let mask = scanner.excludedBytes(line.content)
            let characters = Array(String(decoding: line.content, as: UTF8.self))
            var positions = [0]
            for character in characters { positions.append(positions.last! + character.utf8.count) }
            var index = 0
            var mentionEnd = 0
            var mentionWords = 0
            while index < characters.count {
                guard Self.word(characters[index]) else {
                    index += 1
                    continue
                }
                let start = index
                index += 1
                while index < characters.count {
                    let character = characters[index]
                    let numericSeparator =
                        ".-/".contains(character) && index + 1 < characters.count
                        && characters[index - 1].isNumber && characters[index + 1].isNumber
                    guard Self.word(character) || numericSeparator else { break }
                    index += 1
                }
                let range = positions[start]..<positions[index]
                let explicit = range.lowerBound > 0 && line.content[range.lowerBound - 1] == 64
                let continuation =
                    mentionWords > 0 && mentionWords < 4 && characters[start].isUppercase
                    && mentionEnd < range.lowerBound
                    && line.content[mentionEnd..<range.lowerBound].allSatisfy({ $0 == 32 || $0 == 9 })
                let mention = explicit || continuation
                mentionWords = mention && characters[start].isUppercase ? (explicit ? 1 : mentionWords + 1) : 0
                mentionEnd = range.upperBound
                if !mention, !range.contains(where: { mask[$0] }) {
                    result.append(
                        DateToken(
                            text: String(characters[start..<index]),
                            range: (range.lowerBound + offset)..<(range.upperBound + offset)))
                }
            }
            offset += line.content.count + (line.ending?.bytes.count ?? 0)
        }
        tokens = result
    }

    static func word(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    func phrase(_ words: [String], at start: Int, language: Language) -> Int? {
        guard start + words.count <= tokens.count else { return nil }
        for index in words.indices {
            let position = start + index
            guard tokens[position].key(language) == words[index] else { return nil }
            if index > 0 {
                let gap = tokens[position - 1].range.upperBound..<tokens[position].range.lowerBound
                guard !gap.isEmpty, bytes[gap].allSatisfy({ $0 == 32 || $0 == 9 }) else { return nil }
            }
        }
        return start + words.count
    }
}
