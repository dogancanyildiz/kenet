import VaultFormat

struct TimelineDates: Equatable, Sendable {
    enum Edge: Sendable { case start, due }
    let start: CalendarDate?
    let due: CalendarDate?
    var isValid: Bool { start == nil || due == nil || start! <= due! }
    var isUndated: Bool { start == nil && due == nil }

    init(start: CalendarDate?, due: CalendarDate?) {
        self.start = start
        self.due = due
    }
    init(_ row: TaskRow) { self.init(start: row.start, due: row.due) }

    func shifted(by days: Int) -> Self? {
        let first = start?.addingDays(days)
        let last = due?.addingDays(days)
        guard start == nil || first != nil, due == nil || last != nil, isValid else { return nil }
        return Self(start: first, due: last)
    }

    func setting(_ edge: Edge, to date: CalendarDate?) -> Self? {
        let result = Self(start: edge == .start ? date : start, due: edge == .due ? date : due)
        return result.isValid ? result : nil
    }

    func span(on today: CalendarDate) -> TimelineSpan? {
        guard let first = start ?? due else { return nil }
        let last = due ?? max(first, today)
        return TimelineSpan(
            first: min(first, last), last: max(first, last), isMilestone: start == nil,
            isOpenEnded: due == nil, isReversed: !isValid)
    }
}

struct TimelineSpan: Equatable, Sendable {
    let first: CalendarDate
    let last: CalendarDate
    let isMilestone: Bool
    let isOpenEnded: Bool
    let isReversed: Bool

    func clipped(to range: ClosedRange<CalendarDate>) -> Self? {
        guard first <= range.upperBound, last >= range.lowerBound else { return nil }
        return Self(
            first: max(first, range.lowerBound), last: min(last, range.upperBound),
            isMilestone: isMilestone, isOpenEnded: isOpenEnded, isReversed: isReversed)
    }
}
