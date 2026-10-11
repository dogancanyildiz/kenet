import Summaries
import VaultFormat
import VaultStore

extension IndexStore {
    /// `today` keeps the goal score of a running period on the days that have already come.
    func periodSummary(
        _ period: SummaryPeriod, containing day: CalendarDate, today: CalendarDate? = nil
    ) async throws -> PeriodSummary {
        let range = period.bounds(containing: day)
        let first = period.previous(containing: day)?.lowerBound ?? range.lowerBound
        return try await computeSummary(period: period, day: day, from: first, to: range.upperBound, today: today)
    }
}
