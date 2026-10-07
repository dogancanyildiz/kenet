import Summaries
import VaultFormat
import VaultStore

extension IndexStore {
    func periodSummary(_ period: SummaryPeriod, containing day: CalendarDate) async throws -> PeriodSummary {
        let range = period.bounds(containing: day)
        let first = period.previous(containing: day)?.lowerBound ?? range.lowerBound
        return try await computeSummary(period: period, day: day, from: first, to: range.upperBound)
    }
}
