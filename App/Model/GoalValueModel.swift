import Foundation
import GoalTracking
import Observation

extension Character {
    fileprivate var isASCIIDigit: Bool { isASCII && isNumber }
}

@MainActor @Observable
final class GoalValueModel: Identifiable {
    let id = UUID()
    let dayModel: GoalDayModel
    let goal: GoalDefinition
    var amount: String
    var done: Bool
    private(set) var isSaved = false
    var value: Double? { Self.number(amount) }
    var canSave: Bool { !isSaved && dayModel.canEdit && (goal.kind != .number || value != nil) }

    init(dayModel: GoalDayModel, goal: GoalDefinition) {
        self.dayModel = dayModel
        self.goal = goal
        if case .number(let value) = dayModel.value(for: goal) { amount = String(value) } else { amount = "0" }
        done = dayModel.value(for: goal) == .boolean(true)
    }

    /// A plain decimal: digits with at most one "." or "," as the decimal mark; negative, hex,
    /// exponent, `nan` and `inf` are refused. Goal forms and ``amount`` read targets with it.
    static func number(_ text: String) -> Double? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let separators = clean.filter { $0 == "." || $0 == "," }.count
        guard separators <= 1, clean.contains(where: \.isASCIIDigit),
            clean.allSatisfy({ $0.isASCIIDigit || $0 == "." || $0 == "," })
        else { return nil }
        return finite(Double(clean.replacingOccurrences(of: ",", with: ".")))
    }

    /// A typed amount read the way `locale` writes numbers: its decimal mark, and its grouping
    /// in whole groups of three ("7.500" in Turkish is 7500, "1.234,5" is 1234.5). The other mark,
    /// once and not in groups of three, is still read as decimal ("2.5" in Turkish is 2.5).
    /// Negative, hex, exponent and spaces inside are refused.
    static func number(_ text: String, locale: Locale) -> Double? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.contains(where: \.isASCIIDigit),
            clean.allSatisfy({ $0.isASCIIDigit || $0 == "." || $0 == "," })
        else { return nil }
        let decimal: Character = locale.decimalSeparator == "," ? "," : "."
        let marks = Set(clean.filter { $0 == "." || $0 == "," })
        let integer: String
        var fraction = ""
        if marks.count == 2 {
            // Both marks: the last one is the decimal mark, the other groups the whole part.
            guard let last = clean.lastIndex(where: { $0 == "." || $0 == "," }) else { return nil }
            let group: Character = clean[last] == "." ? "," : "."
            fraction = String(clean[clean.index(after: last)...])
            guard let whole = grouped(String(clean[..<last]), by: group), !fraction.contains(clean[last])
            else { return nil }
            integer = whole
        } else if let mark = marks.first {
            let parts = clean.split(separator: mark, omittingEmptySubsequences: false).map(String.init)
            if parts.count > 2 || (mark != decimal && parts.count == 2 && grouped(clean, by: mark) != nil) {
                guard let whole = grouped(clean, by: mark) else { return nil }
                integer = whole
            } else {
                integer = parts[0]
                fraction = parts.count > 1 ? parts[1] : ""
            }
        } else {
            integer = clean
        }
        return finite(Double((integer.isEmpty ? "0" : integer) + (fraction.isEmpty ? "" : "." + fraction)))
    }

    /// `text` as whole groups of three after a first group of one to three digits that does not
    /// start with 0 ("7.500", "1.234.567"); the digits alone, or nil when it is not grouped.
    private static func grouped(_ text: String, by mark: Character) -> String? {
        let parts = text.split(separator: mark, omittingEmptySubsequences: false)
        guard parts.count >= 2, let first = parts.first, (1...3).contains(first.count),
            first.first != "0", parts.dropFirst().allSatisfy({ $0.count == 3 })
        else { return parts.count == 1 && !text.isEmpty ? text : nil }
        return parts.joined()
    }

    private static func finite(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value == 0 ? 0 : value
    }

    func step(_ delta: Double) { amount = String(max(0, (value ?? 0) + delta)) }
    func save(remove: Bool = false) async -> Bool {
        guard !isSaved, dayModel.canEdit, remove || canSave else { return false }
        let value: GoalValue? = remove ? nil : (goal.kind != .number ? (done ? .boolean(true) : nil) : .number(value!))
        isSaved = await dayModel.set(goal, value: value)
        return isSaved
    }
}
