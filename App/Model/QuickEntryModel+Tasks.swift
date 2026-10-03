import DateParsing
import VaultFormat

extension QuickEntryModel {
    var dateExpression: DateParse? {
        guard mode == .task else { return nil }
        return DateExpressionParser.parse(text, today: today(), language: languages)
    }

    var dueDate: CalendarDate? { overridesDate ? manualDueDate : dateExpression?.date }
    var dateIsAssumed: Bool { overridesDate ? manualDateIsAssumed : dateExpression?.confidence == .assumed }
    var submissionText: String { mode == .task ? dateExpression?.remainder ?? text : text }

    func selectDate(_ date: CalendarDate?) {
        overridesDate = true
        manualDueDate = date
        manualDateIsAssumed = false
    }

    /// Consume the expression before mention recognition so all pinned ranges reconcile normally.
    func prepareTaskText() {
        let date = dueDate
        let assumed = dateIsAssumed
        if let expression = dateExpression { text = expression.remainder }
        selectDate(date)
        manualDateIsAssumed = assumed
    }
}
