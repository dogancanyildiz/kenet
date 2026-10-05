import Foundation
import GoalTracking
import VaultFormat

extension VaultStore {
    /// Edits one day's goal entry. Nil removes the entry and never writes false.
    @discardableResult
    public func settingGoalValue(on day: CalendarDate, key: String, value: GoalValue?) async throws -> RawDocument {
        guard key.contains(where: { !$0.isWhitespace }), value?.isValid != false else { throw EditError.invalidValue }
        return try await perform {
            try self.validateMilestoneWrite(on: day, key: key, value: value)
            return try self.edit(self.dayFilePath(for: day), date: day, createDay: value != nil) { document in
                if document.isReadOnly { throw EditError.readOnlyDocument }
                if case .parsed(let frontmatter) = document.frontmatter,
                    let field = frontmatter.field(named: "goals")
                {
                    switch field.value {
                    case .mapping: break
                    case .scalar(let scalar) where scalar.raw.isEmpty: break
                    default: throw EditError.notAMapping(key: "goals")
                    }
                }
                guard let value else { return try document.removingFrontmatterEntry(forKey: key, inMapping: "goals") }
                let literal: FrontmatterLiteral
                switch value {
                case .boolean(let done): literal = .boolean(done)
                case .number(let amount): literal = .number(goalNumberSpelling(amount))
                }
                return try document.settingFrontmatterEntry(literal, forKey: key, inMapping: "goals")
            }
        }
    }
    /// Check current disk bytes inside the write queue, including edits not yet indexed.
    private nonisolated func validateMilestoneWrite(on day: CalendarDate, key: String, value: GoalValue?) throws {
        guard let value else { return }
        guard try isMilestoneGoal(key: key) else { return }
        guard value == .boolean(true) else { throw EditError.invalidValue }
        for path in try markdownPaths(under: "journal") {
            guard path.hasSuffix(".md"),
                let other = CalendarDate(String(path.dropFirst("journal/".count).dropLast(3))),
                other.year == day.year, other != day
            else { continue }
            let document = RawDocument(bytes: try readFile(checkedURL(path)))
            guard case .parsed(let fields) = document.frontmatter,
                case .mapping(let entries) = fields.field(named: "goals")?.value
            else { continue }
            if entries.contains(where: { $0.key == key && $0.value.kind == .boolean(true) }) {
                throw EditError.invalidValue
            }
        }
    }

    /// Goal definitions only: indexed `kind=goal` files plus anything currently under `goals/`.
    private nonisolated func isMilestoneGoal(key: String) throws -> Bool {
        var paths = Set(try index.goalFiles())
        paths.formUnion(try markdownPaths(under: "goals"))
        for path in paths.sorted(by: {
            $0.unicodeScalars.lexicographicallyPrecedes($1.unicodeScalars) { $0.value < $1.value }
        }) {
            let document: RawDocument
            do {
                document = RawDocument(bytes: try readFile(checkedURL(path)))
            } catch CocoaError.fileReadNoSuchFile {
                continue
            }
            guard case .parsed(let fields) = document.frontmatter,
                case .scalar(let type) = fields.field(named: "type")?.value, type.text == "goal",
                case .scalar(let goalKey) = fields.field(named: "key")?.value, goalKey.text == key,
                case .scalar(let kind) = fields.field(named: "kind")?.value, kind.text == "milestone"
            else { continue }
            return true
        }
        return false
    }
}

/// Expand Swift's shortest round-tripping decimal when it uses an exponent: YAML's numeric subset has none.
func goalNumberSpelling(_ value: Double) -> String {
    if value == 0 { return "0" }
    let text = String(value)
    let parts = text.split(separator: "e")
    guard parts.count == 2, let exponent = Int(parts[1]) else {
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }
    let mantissa = parts[0].split(separator: ".")
    let digits = mantissa.joined()
    let position = mantissa[0].count + exponent
    if position <= 0 { return "0." + String(repeating: "0", count: -position) + digits }
    if position >= digits.count { return digits + String(repeating: "0", count: position - digits.count) }
    let split = digits.index(digits.startIndex, offsetBy: position)
    return String(digits[..<split]) + "." + String(digits[split...])
}
