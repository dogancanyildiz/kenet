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

    /// Everything the user turned back into plain words, task expressions and names alike: edits,
    /// submit preparation and a failed write move both kinds by the same rules.
    struct Suppressions: Equatable {
        var expressions: [Range<Int>] = []
        var names: [Range<Int>] = []

        func following(from oldText: String, to newText: String) -> Suppressions {
            Suppressions(
                expressions: QuickEntryModel.following(expressions, from: oldText, to: newText),
                names: QuickEntryModel.following(names, from: oldText, to: newText))
        }

        func relocating(in text: String, removing removed: [Range<Int>], to remainder: String) -> Suppressions {
            Suppressions(
                expressions: QuickEntryModel.relocating(expressions, in: text, removing: removed, to: remainder),
                names: QuickEntryModel.relocating(names, in: text, removing: removed, to: remainder))
        }
    }

    var suppressions: Suppressions {
        get { Suppressions(expressions: suppressedExpressions, names: suppressedNames) }
        set {
            suppressedExpressions = newValue.expressions
            suppressedNames = newValue.names
        }
    }

    /// Every task expression is read from here, so a suppressed one stays literal everywhere.
    var taskAnalysis: QuickEntryAnalysis? {
        guard mode == .task else { return nil }
        return analysis(of: text, suppressing: suppressedExpressions)
    }

    /// The text before an edit is read the same way, or the two readings differ without the date changing.
    func analysis(of text: String, suppressing suppressed: [Range<Int>]) -> QuickEntryAnalysis {
        // One draw of the row reads the analysis several times; the same bytes need not be read again.
        let key = AnalysisKey(
            bytes: Array(text.utf8), suppressed: suppressed, today: today(), languages: languages,
            weekStartsOnMonday: WeekStart.isMonday(in: calendar))
        if let cached = analysisCache, cached.key == key { return cached.analysis }
        let analysis = WeekStart.analysis(
            text, today: key.today, language: languages, suppressedRanges: suppressed, calendar: calendar)
        analysisCache = (key, analysis)
        return analysis
    }

    /// Everything the analysis reads; equal keys give equal analyses.
    struct AnalysisKey: Equatable {
        let bytes: [UInt8]
        let suppressed: [Range<Int>]
        let today: CalendarDate
        let languages: [DateParsing.Language]
        let weekStartsOnMonday: Bool
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
        let removed = analysis.tokens.map(\.byteRange)
        let suppressed = suppressions.relocating(in: text, removing: removed, to: analysis.remainder)
        let undoneNames = Self.relocating(
            composer.effectiveSuppressions, in: text, removing: removed, to: analysis.remainder)
        text = analysis.remainder
        suppressions = suppressed
        composer.suppressNames(covering: undoneNames)
        selectDate(date)
        manualDateIsAssumed = assumed
    }

    /// Ranges before an edit stay, ranges after it move with the text, ranges it touches are dropped.
    /// Where the same bytes repeat an edit can be read at more than one place ("yarın yarın" losing
    /// one of the two); a range any reading touches is dropped, so the words are recognized again
    /// and show their chip instead of staying literal with nothing on screen saying so.
    nonisolated static func following(
        _ ranges: [Range<Int>], from oldText: String, to newText: String
    ) -> [Range<Int>] {
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
    nonisolated static func relocating(
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
