import VaultFormat

/// The bytes a set of line replacements must produce, written out independently of the model under test.
///
/// The reference works on bytes and never builds a document: it joins the untouched bytes
/// around the new lines. What the resulting document looks like is then left to the reader,
/// which has its own reference model.
enum ReferenceEdit {
    struct Replacement {
        var range: Range<Int>
        var contents: [[UInt8]]
    }

    static func bytes(_ input: [UInt8], replacing range: Range<Int>, with contents: [[UInt8]]) -> [UInt8] {
        bytes(input, applying: [Replacement(range: range, contents: contents)])
    }

    /// The replacements must not overlap. All of them refer to the lines of the input.
    static func bytes(_ input: [UInt8], applying replacements: [Replacement]) -> [UInt8] {
        let shapes = ReferenceModel.lines(input)
        let endingForNewLines = shapes.compactMap(\.ending).first ?? .lf

        // Every line is either kept or replaced; additions are attached to the position they go before.
        var pieces: [LineShape] = []
        for position in 0...shapes.count {
            // Additions at a position go before a line rewritten at that position.
            let starting = replacements.filter { $0.range.lowerBound == position }
            for replacement in starting.filter(\.range.isEmpty) + starting.filter({ !$0.range.isEmpty }) {
                for (offset, content) in replacement.contents.enumerated() {
                    // A rewritten line keeps the ending found at its position; an added line gets the default.
                    let isRewrite = offset < replacement.range.count
                    pieces.append(LineShape(content, isRewrite ? shapes[position + offset].ending : endingForNewLines))
                }
            }
            if position < shapes.count, !replacements.contains(where: { $0.range.contains(position) }) {
                pieces.append(shapes[position])
            }
        }

        var output: [UInt8] = ReferenceModel.hasByteOrderMark(input) ? ReferenceModel.byteOrderMark : []
        for (index, piece) in pieces.enumerated() {
            output += piece.content
            if let ending = piece.ending {
                output += ending.bytes
            } else if index < pieces.count - 1 || piece.content.isEmpty {
                // Only the last line may lack an ending, and only when it has content.
                output += endingForNewLines.bytes
            }
        }
        return output
    }
}
