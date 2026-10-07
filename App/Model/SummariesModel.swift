import Foundation
import Observation
import Summaries
import VaultFormat

struct SummaryChange: Equatable {
    let value: Double
    var symbol: String { value > 0 ? "arrow.up" : value < 0 ? "arrow.down" : "minus" }
    var magnitude: Double { abs(value) }
}

@MainActor @Observable
final class SummariesModel {
    let store: IndexStore
    var period = SummaryPeriod.week
    private(set) var day: CalendarDate
    private(set) var summary: PeriodSummary?
    private(set) var isLoading = false
    private(set) var errorText: String?
    private let today: () -> CalendarDate
    @ObservationIgnored private var request = UUID()

    init(store: IndexStore, today: @escaping () -> CalendarDate = { LocalDay.today() }) {
        self.store = store
        self.today = today
        day = today()
    }
    var range: ClosedRange<CalendarDate> { period.bounds(containing: day) }
    var canGoPrevious: Bool { period.previous(containing: day) != nil }
    var canGoNext: Bool { period.next(containing: day) != nil }
    func previous() { if let range = period.previous(containing: day) { day = range.lowerBound } }
    func next() { if let range = period.next(containing: day) { day = range.lowerBound } }
    func current() { day = today() }
    func reset() {
        request = UUID()
        summary = nil
        errorText = nil
        isLoading = false
        day = today()
    }

    func load() async {
        let id = UUID()
        request = id
        let root = store.vaultURL
        let period = period
        let day = day
        isLoading = true
        errorText = nil
        summary = nil
        defer { if request == id { isLoading = false } }
        do {
            let result = try await store.periodSummary(period, containing: day)
            guard request == id, root == store.vaultURL, self.period == period, self.day == day, !Task.isCancelled
            else { return }
            summary = result
        } catch {
            guard request == id, root == store.vaultURL, self.period == period, self.day == day, !Task.isCancelled
            else { return }
            errorText = DayEditError.message(for: error)
        }
    }
}
