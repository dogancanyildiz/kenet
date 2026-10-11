import DateParsing
import VaultFormat

extension QuickEntryModel {
    struct RecurrenceExpression {
        let recurrence: TaskRecurrence
    }

    /// One recognition the user can undo: an expression and every stretch of `text` it covers.
    struct TaskExpression: Identifiable, Equatable {
        let value: QuickEntryAnalysis.Token.Value
        var byteRanges: [Range<Int>]
        var spelling: String
        var id: Int { byteRanges[0].lowerBound }
    }

    /// Every task expression is read from here, so a suppressed one stays literal everywhere.
    var taskAnalysis: QuickEntryAnalysis? {
        guard mode == .task else { return nil }
        return QuickEntryAnalysis.analyze(
            text, today: today(), language: languages, suppressedRanges: suppressedExpressions)
    }

    var recurrenceExpression: RecurrenceExpression? {
        taskAnalysis?.recurrence.map(RecurrenceExpression.init)
    }
    var dateExpression: (date: CalendarDate, confidence: DateParse.Confidence)? { taskAnalysis?.date }

    var taskExpressions: [TaskExpression] {
        guard let analysis = taskAnalysis else { return [] }
        let bytes = Array(text.utf8)
        var expressions: [TaskExpression] = []
        for token in analysis.tokens {
            let spelling = String(decoding: bytes[token.byteRange], as: UTF8.self)
            // An earlier removal can split a date or a recurrence; its pieces are one recognition.
            if token.kind != .priority, let index = expressions.firstIndex(where: { $0.value == token.value }) {
                expressions[index].byteRanges.append(token.byteRange)
                expressions[index].spelling += " " + spelling
            } else {
                expressions.append(
                    TaskExpression(value: token.value, byteRanges: [token.byteRange], spelling: spelling))
            }
        }
        return expressions
    }

    var dueDate: CalendarDate? { overridesDate ? manualDueDate : dateExpression?.date }
    var dateIsAssumed: Bool { overridesDate ? manualDateIsAssumed : dateExpression?.confidence == .assumed }
    var submissionText: String { taskAnalysis?.remainder ?? text }

    func selectDate(_ date: CalendarDate?) {
        overridesDate = true
        manualDueDate = date
        manualDateIsAssumed = false
    }

    /// Keeps the expression's words in the task text instead of turning them into a field.
    func undoRecognition(_ expression: TaskExpression) {
        suppressedExpressions += expression.byteRanges
    }

    /// Consume the expression before mention recognition so all pinned ranges reconcile normally.
    func prepareTaskText() {
        guard let analysis = taskAnalysis else { return }
        let date = dueDate
        let assumed = dateIsAssumed
        if let recurrence = analysis.recurrence { taskRecurrence = recurrence }
        if let priority = analysis.priority {
            let explicit = RawDocument(bytes: ("- [ ] " + text).utf8).bodyLines.tasks.first?.priority
            taskPriority = explicit ?? priority
        }
        // A mention can still stop this submit; the next one must find the same words suppressed.
        let suppressed = Self.relocating(
            suppressedExpressions, in: text, removing: analysis.tokens.map(\.byteRange), to: analysis.remainder)
        text = analysis.remainder
        suppressedExpressions = suppressed
        selectDate(date)
        manualDateIsAssumed = assumed
    }

    /// Ranges before an edit stay, ranges after it move with the text, ranges it touches are dropped.
    /// Where the same bytes repeat an edit can be read at more than one place ("yarın yarın" losing
    /// one of the two); a range any reading touches is dropped, so the words are recognized again
    /// and show their chip instead of staying literal with nothing on screen saying so.
    static func following(_ ranges: [Range<Int>], from oldText: String, to newText: String) -> [Range<Int>] {
        guard !ranges.isEmpty else { return [] }
        let old = Array(oldText.utf8)
        let new = Array(newText.utf8)
        let shorter = min(old.count, new.count)
        let prefix = zip(old, new).prefix(while: { $0 == $1 }).count
        let suffix = zip(old.reversed(), new.reversed()).prefix(while: { $0 == $1 }).count
        // The earliest and the latest place the edit can sit.
        let untouchedStart = min(prefix, shorter - suffix)
        let untouchedEnd = old.count - min(suffix, shorter - prefix)
        let delta = new.count - old.count
        return ranges.compactMap { range in
            if range.upperBound <= untouchedStart { return range }
            if range.lowerBound >= untouchedEnd { return (range.lowerBound + delta)..<(range.upperBound + delta) }
            return nil
        }
    }

    /// Removing expressions only deletes their bytes and adjusts blanks around them, so a kept
    /// word is found again by counting the non-blank bytes that stay in front of it.
    static func relocating(
        _ ranges: [Range<Int>], in text: String, removing removed: [Range<Int>], to remainder: String
    ) -> [Range<Int>] {
        guard !ranges.isEmpty else { return [] }
        let old = Array(text.utf8)
        let new = Array(remainder.utf8)
        let isBlank: (UInt8) -> Bool = { $0 == 32 || $0 == 9 }
        return ranges.compactMap { range in
            let kept = old.indices.prefix(range.lowerBound).count { index in
                !isBlank(old[index]) && !removed.contains { $0.contains(index) }
            }
            var seen = 0
            guard
                let start = new.indices.first(where: { index in
                    guard !isBlank(new[index]) else { return false }
                    seen += 1
                    return seen > kept
                }), start + range.count <= new.count,
                new[start..<(start + range.count)].elementsEqual(old[range])
            else { return nil }
            return start..<(start + range.count)
        }
    }
}

extension QuickEntryAnalysis {
    fileprivate var recurrence: TaskRecurrence? {
        for case .recurrence(let recurrence) in tokens.map(\.value) { return recurrence }
        return nil
    }

    /// A leading and a trailing mark can both match; the higher one wins.
    fileprivate var priority: TaskPriority? {
        let priorities = tokens.compactMap { token -> TaskPriority? in
            if case .priority(let priority) = token.value { return priority }
            return nil
        }
        return priorities.contains(.high) ? .high : priorities.first
    }

    var date: (date: CalendarDate, confidence: DateParse.Confidence)? {
        for token in tokens {
            if case .date(let date) = token.value { return (date, token.confidence) }
        }
        return nil
    }
}
