import VaultFormat

/// Open inventory at the measured end of each rhythm unit, independent of a task's due date.
public struct TaskFlowSeries: Sendable, Equatable {
    public struct Unit: Sendable, Equatable, Identifiable {
        public let id: Int
        public let range: ClosedRange<CalendarDate>
        public let measuredEnd: CalendarDate
        public let open: Int
    }

    public let period: SummaryPeriod
    /// Started units only; a running unit ends at today.
    public let units: [Unit]
    /// Every unit of the whole previous period, as in the rhythm comparison.
    public let previous: [Unit]
    public let unitCount: Int
    /// Inventory at the end of the day before the period starts.
    public let opening: Int
    public var closing: Int { units.last?.open ?? opening }
    /// The first unit with the highest closing inventory.
    public var peak: Unit? {
        guard let highest = units.map(\.open).max() else { return nil }
        return units.first { $0.open == highest }
    }

    /// Like PeriodSummary, a future period or a nil today measures the whole period.
    public static func compute(
        tasks: [SummaryInput.Task], period: SummaryPeriod, containing day: CalendarDate,
        today: CalendarDate? = nil
    ) -> Self {
        let range = period.bounds(containing: day)
        let end = today.map { range.contains($0) ? $0 : range.upperBound } ?? range.upperBound
        func open(on day: CalendarDate) -> Int {
            tasks.filter { $0.isOpen(on: day) }.count
        }
        func units(containing day: CalendarDate, through end: CalendarDate) -> [Unit] {
            period.units(containing: day).enumerated().compactMap { index, range in
                guard range.lowerBound <= end else { return nil }
                let measuredEnd = min(range.upperBound, end)
                return Unit(id: index, range: range, measuredEnd: measuredEnd, open: open(on: measuredEnd))
            }
        }
        return Self(
            period: period, units: units(containing: day, through: end),
            previous: period.previous(containing: day).map {
                units(containing: $0.lowerBound, through: $0.upperBound)
            } ?? [],
            unitCount: period.units(containing: day).count,
            opening: range.lowerBound.addingDays(-1).map { open(on: $0) } ?? 0)
    }
}

extension SummaryInput.Task {
    /// Source day and completion date reconstruct inventory; cancellation history is unavailable.
    func isOpen(on day: CalendarDate) -> Bool {
        guard let created, created <= day, status != .cancelled else { return false }
        return status != .done || done.map { $0 > day } == true
    }
}
