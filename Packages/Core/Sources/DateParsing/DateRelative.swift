import VaultFormat

extension DateTokens {
    func relative(at start: Int, today: CalendarDate, language: Language, monday: Bool) -> [DateMatch] {
        let offsets: [(String, Int)] =
            language == .turkish
            ? [("bugün", 0), ("yarın", 1), ("öbür gün", 2), ("dün", -1)]
            : [("today", 0), ("tomorrow", 1), ("day after tomorrow", 2), ("yesterday", -1)]
        var matches: [DateMatch] = []
        for (expression, days) in offsets {
            if let end = phrase(expression.split(separator: " ").map(String.init), at: start, language: language),
                let date = DateCalendar.adding(days, to: today)
            {
                matches.append(DateMatch(end: end, date: date, confidence: .exact))
            }
        }
        let weekDay = DateCalendar.weekday(today)
        let weekStart = monday ? 0 : 6
        let nextWeek = DateCalendar.adding(7 - (weekDay - weekStart + 7) % 7, to: today)
        let weekend = DateCalendar.adding((5 - weekDay + 7) % 7, to: today)
        let month = today.month == 12 ? 1 : today.month + 1
        let year = today.year + (today.month == 12 ? 1 : 0)
        let nextMonth = CalendarDate(year: year, month: month, day: 1)
        let monthEnd = CalendarDate(
            year: today.year, month: today.month, day: DateCalendar.monthLength(year: today.year, month: today.month))
        let expressions: [(String, CalendarDate?, DateParse.Confidence)] =
            language == .turkish
            ? [
                ("haftaya", nextWeek, .exact), ("gelecek hafta", nextWeek, .exact), ("bu hafta sonu", weekend, .exact),
                ("hafta sonu", weekend, .assumed), ("gelecek ay", nextMonth, .exact), ("ay sonu", monthEnd, .exact),
            ]
            : [
                ("next week", nextWeek, .exact), ("this weekend", weekend, .exact), ("weekend", weekend, .assumed),
                ("next month", nextMonth, .exact), ("end of month", monthEnd, .exact),
            ]
        for (expression, date, confidence) in expressions {
            if let date,
                let end = phrase(expression.split(separator: " ").map(String.init), at: start, language: language)
            {
                matches.append(DateMatch(end: end, date: date, confidence: confidence))
                let weekPrefixes = language == .turkish ? ["haftaya", "gelecek hafta"] : ["next week"]
                if weekPrefixes.contains(expression) {
                    for (day, names) in DateWords.weekdays[language]!.enumerated() {
                        for name in names {
                            var words = expression.split(separator: " ").map(String.init) + [name]
                            if language == .turkish, phrase(words + ["günü"], at: start, language: language) != nil {
                                words.append("günü")
                            }
                            if let end = phrase(words, at: start, language: language),
                                let weekday = DateCalendar.adding((day - weekStart + 7) % 7, to: date)
                            {
                                matches.append(DateMatch(end: end, date: weekday, confidence: .exact))
                            }
                        }
                    }
                }
            }
        }
        let numberIndex = language == .turkish ? start : start + 1
        if numberIndex < tokens.count, let days = DateWords.number(tokens[numberIndex].text) {
            let words =
                language == .turkish
                ? [[tokens[numberIndex].text, "gün", "sonra"], [tokens[numberIndex].text, "gün", "içinde"]]
                : (days == 1
                    ? [["in", tokens[numberIndex].text, "day"], ["in", tokens[numberIndex].text, "days"]]
                    : [["in", tokens[numberIndex].text, "days"]])
            for words in words {
                if let end = phrase(words, at: start, language: language),
                    let date = DateCalendar.adding(days, to: today)
                {
                    matches.append(DateMatch(end: end, date: date, confidence: .exact))
                }
            }
        }
        return matches
    }

    func weekday(at start: Int, today: CalendarDate, language: Language) -> [DateMatch] {
        var matches: [DateMatch] = []
        for (day, names) in DateWords.weekdays[language]!.enumerated() {
            for name in names {
                let prefixes = language == .turkish ? ["", "gelecek", "bu"] : ["", "next", "this", "on"]
                for prefix in prefixes {
                    var words = prefix.isEmpty ? [name] : [prefix, name]
                    if language == .turkish, phrase(words + ["günü"], at: start, language: language) != nil {
                        words.append("günü")
                    }
                    guard let end = phrase(words, at: start, language: language) else { continue }
                    var days = (day - DateCalendar.weekday(today) + 7) % 7
                    let thisWeek = prefix == "bu" || prefix == "this"
                    if days == 0 && !thisWeek { days = 7 }
                    if prefix == "gelecek" || prefix == "next" { days += 7 }
                    if let date = DateCalendar.adding(days, to: today) {
                        matches.append(
                            DateMatch(
                                end: end, date: date, confidence: prefix.isEmpty || prefix == "on" ? .assumed : .exact))
                    }
                }
            }
        }
        return matches
    }
}
