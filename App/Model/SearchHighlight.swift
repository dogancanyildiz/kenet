import Foundation

/// Literal, accent-preserving highlighting; no Markdown from the vault is interpreted.
enum SearchHighlight {
    static func text(_ text: String, query: String) -> AttributedString {
        var result = AttributedString(text)
        for term in query.split(whereSeparator: \.isWhitespace) {
            var start = text.startIndex
            while start < text.endIndex,
                let range = text.range(
                    of: String(term), options: .caseInsensitive, range: start..<text.endIndex,
                    locale: Locale(identifier: "en_US_POSIX"))
            {
                if let lower = AttributedString.Index(range.lowerBound, within: result),
                    let upper = AttributedString.Index(range.upperBound, within: result)
                {
                    result[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
                }
                start = range.upperBound
            }
        }
        return result
    }
}
