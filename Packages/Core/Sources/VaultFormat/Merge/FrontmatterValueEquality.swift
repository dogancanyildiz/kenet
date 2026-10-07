/// The "same value" relation of the writing rules, applied to two values read from files:
/// values that differ in spelling only are the same.
enum FrontmatterValueEquality {
    static func same(_ first: FrontmatterScalar, _ second: FrontmatterScalar) -> Bool {
        switch (first.kind, second.kind) {
        case (.text, .text):
            return Syntax.exactlyEqual(first.text, second.text)
        case (.number, .number):
            return PlainScalar.numbersAreEqual(Array(first.raw.utf8), Array(second.raw.utf8))
        case (.boolean(let a), .boolean(let b)):
            return a == b
        case (.date(let a), .date(let b)):
            return a == b
        case (.empty, .empty):
            return true
        default:
            return false
        }
    }

    static func same(_ first: FrontmatterValue, _ second: FrontmatterValue) -> Bool {
        switch (first, second) {
        case (.raw(let a), .raw(let b)):
            return Syntax.exactlyEqual(a, b)
        case (.mapping(let a), .mapping(let b)):
            return a.count == b.count
                && a.allSatisfy { entry in
                    b.first { Syntax.exactlyEqual($0.key, entry.key) }.map { same(entry.value, $0.value) } == true
                }
        case (.raw, _), (_, .raw), (.mapping, _), (_, .mapping):
            return false
        default:
            guard let a = first.listItems, let b = second.listItems, a.count == b.count else { return false }
            return zip(a, b).allSatisfy { same($0, $1) }
        }
    }

    /// Which of two values of a goal entry is further along: the larger number or `true`.
    /// `nil` when the values are of different kinds or of a kind that has no progress.
    static func progressed(newer: FrontmatterScalar, older: FrontmatterScalar) -> MergeSide? {
        switch (newer.kind, older.kind) {
        case (.number, .number):
            guard let a = newer.doubleValue, let b = older.doubleValue else { return nil }
            return b > a ? .older : .newer
        case (.boolean(let a), .boolean(let b)):
            return b && !a ? .older : .newer
        default:
            return nil
        }
    }
}
