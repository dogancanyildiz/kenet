import DateParsing
import VaultFormat

extension QuickEntryModel {
    var recurrenceExpression: RecurrenceParse? {
        guard mode == .task else { return nil }
        return RecurrenceExpressionParser.parse(text, language: languages)
    }
    private var taskExpressionText: String {
        let remainder = recurrenceExpression?.remainder ?? text
        return PriorityExpressionParser.parse(remainder)?.remainder ?? remainder
    }

    var dateExpression: DateParse? {
        guard mode == .task else { return nil }
        return DateExpressionParser.parse(taskExpressionText, today: today(), language: languages)
    }

    var dueDate: CalendarDate? { overridesDate ? manualDueDate : dateExpression?.date }
    var dateIsAssumed: Bool { overridesDate ? manualDateIsAssumed : dateExpression?.confidence == .assumed }
    var submissionText: String { mode == .task ? dateExpression?.remainder ?? taskExpressionText : text }

    func selectDate(_ date: CalendarDate?) {
        overridesDate = true
        manualDueDate = date
        manualDateIsAssumed = false
    }

    /// Consume the expression before mention recognition so all pinned ranges reconcile normally.
    func prepareTaskText() {
        let date = dueDate
        let assumed = dateIsAssumed
        let expression = dateExpression
        if let recurrence = recurrenceExpression { taskRecurrence = recurrence.recurrence }
        if let priority = PriorityExpressionParser.parse(recurrenceExpression?.remainder ?? text) {
            let explicit = RawDocument(bytes: ("- [ ] " + text).utf8).bodyLines.tasks.first?.priority
            taskPriority = explicit ?? priority.priority
        }
        text = expression?.remainder ?? taskExpressionText
        selectDate(date)
        manualDateIsAssumed = assumed
    }
}
