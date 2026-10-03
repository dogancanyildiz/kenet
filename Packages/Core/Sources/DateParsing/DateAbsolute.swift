import VaultFormat

extension DateTokens {
    func absolute(at start: Int, today: CalendarDate, language: Language) -> [DateMatch] {
        let token = tokens[start].key(language)
        var matches: [DateMatch] = []
        if let date = CalendarDate(token) { matches.append(DateMatch(end: start + 1, date: date, confidence: .exact)) }
        for separator: Character in [".", "/"] {
            let parts = token.split(separator: separator, omittingEmptySubsequences: false).map(String.init)
            if (2...3).contains(parts.count), let first = DateWords.number(parts[0]),
                let second = DateWords.number(parts[1]),
                parts.count == 2 || parts[2].count == 4 && DateWords.number(parts[2]) != nil
            {
                let year = parts.count == 3 ? DateWords.number(parts[2]) : nil
                let monthFirst = separator == "/" && language == .english
                let month = monthFirst ? first : second
                let day = monthFirst ? second : first
                if let date = DateCalendar.annual(month: month, day: day, year: year, today: today) {
                    let ambiguous = separator == "/" && first <= 12 && second <= 12 && first != second
                    matches.append(
                        DateMatch(end: start + 1, date: date, confidence: year == nil || ambiguous ? .assumed : .exact))
                }
            }
        }
        guard start + 1 < tokens.count else { return matches }
        for (index, names) in DateWords.months[language]!.enumerated() {
            for name in names {
                let second = tokens[start + 1].key(language)
                let day =
                    token == name ? DateWords.day(second, language: language) : DateWords.day(token, language: language)
                guard let day, token == name || second == name,
                    phrase([token, second], at: start, language: language) != nil
                else { continue }
                var end = start + 2
                var year: Int?
                if end < tokens.count, let supplied = DateWords.number(tokens[end].text),
                    phrase([token, second, tokens[end].text], at: start, language: language) != nil
                {
                    year = supplied
                    end += 1
                    guard tokens[end - 1].text.count == 4 else { continue }
                }
                if let date = DateCalendar.annual(month: index + 1, day: day, year: year, today: today) {
                    matches.append(DateMatch(end: end, date: date, confidence: year == nil ? .assumed : .exact))
                }
            }
        }
        return matches
    }
}
