import GoalTracking
import VaultFormat

extension VaultStore {
    /// Edits one day's goal entry. Nil removes the entry and never writes false.
    @discardableResult
    public func settingGoalValue(on day: CalendarDate, key: String, value: GoalValue?) async throws -> RawDocument {
        guard key.contains(where: { !$0.isWhitespace }), value?.isValid != false else { throw EditError.invalidValue }
        return try await perform {
            try self.edit(self.dayFilePath(for: day), date: day, createDay: value != nil) { document in
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
}

/// Expand Swift's shortest round-tripping decimal when it uses an exponent: YAML's numeric subset has none.
private func goalNumberSpelling(_ value: Double) -> String {
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
