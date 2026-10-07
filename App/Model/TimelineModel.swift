import Foundation
import Observation
import VaultFormat
import VaultIndex
import VaultStore

struct TimelineGroup: Identifiable {
    let id: String
    let name: String?
    let rows: [TaskRow]
}

struct TimelineDrag {
    let row: TaskRow
    let root: URL?
}

@MainActor @Observable
final class TimelineModel {
    enum Grouping: String, CaseIterable { case project, person, none }
    enum Scale: String, CaseIterable {
        case week, month, quarter
        var daysAcross: Int {
            switch self {
            case .week: 7
            case .month: 30
            case .quarter: 113
            }
        }
    }
    let tasks: TasksModel
    var grouping = Grouping.project
    var scale = Scale.quarter
    var collapsed: Set<String> = []
    private(set) var visibleRange: ClosedRange<CalendarDate>
    private(set) var previews: [String: TimelineDates] = [:]
    private(set) var busy: Set<String> = []
    private(set) var errorText: String?
    var store: IndexStore { tasks.store }
    var today: CalendarDate { tasks.day }
    var bounds: ClosedRange<CalendarDate> { (today.addingDays(-365) ?? today)...(today.addingDays(365) ?? today) }
    @ObservationIgnored private var cachedDays: (CalendarDate, [CalendarDate])?
    var days: [CalendarDate] {
        if let cachedDays, cachedDays.0 == today { return cachedDays.1 }
        let values = (0...(bounds.upperBound.ordinal - bounds.lowerBound.ordinal)).compactMap {
            bounds.lowerBound.addingDays($0)
        }
        cachedDays = (today, values)
        return values
    }

    init(tasks: TasksModel) {
        self.tasks = tasks
        visibleRange = (tasks.day.addingDays(-28) ?? tasks.day)...(tasks.day.addingDays(84) ?? tasks.day)
    }

    var undated: [TaskRow] {
        tasks.filtered.filter { $0.rawStatus != "-" && $0.start == nil && $0.due == nil }.sorted(by: KanbanModel.order)
    }
    private var dated: [TaskRow] {
        tasks.filtered.filter {
            $0.rawStatus != "-" && TimelineDates($0).span(on: today)?.clipped(to: visibleRange) != nil
        }.sorted { lhs, rhs in
            let left = lhs.start ?? lhs.due!
            let right = rhs.start ?? rhs.due!
            return left == right ? KanbanModel.order(lhs, rhs) : left < right
        }
    }
    var groups: [TimelineGroup] {
        let rows = dated
        switch grouping {
        case .none: return rows.isEmpty ? [] : [TimelineGroup(id: "all", name: nil, rows: rows)]
        case .project:
            return store.content.projects.compactMap { name in
                let group = rows.filter { $0.project.map(VaultIndex.projectKey) == VaultIndex.projectKey(name) }
                return group.isEmpty
                    ? nil : TimelineGroup(id: "project:" + VaultIndex.projectKey(name), name: name, rows: group)
            } + unassigned(rows.filter { $0.project == nil }, id: "project:")
        case .person:
            let people = store.content.entities.filter { $0.kind == "person" }
            let paths = Set(people.map(\.id))
            return people.compactMap { person in
                let group = rows.filter { $0.linkedFiles.contains(person.id) }
                return group.isEmpty
                    ? nil
                    : TimelineGroup(
                        id: "person:" + person.id,
                        name: person.name + (person.qualifier.map { " (" + $0 + ")" } ?? ""), rows: group)
            } + unassigned(rows.filter { $0.linkedFiles.isDisjoint(with: paths) }, id: "person:")
        }
    }
    var mobileGroups: [TimelineGroup] {
        let buckets = Dictionary(grouping: dated) { row in
            let date = row.start ?? row.due!
            return scale == .week ? date.startOfWeek ?? date : date.startOfMonth
        }
        return buckets.keys.sorted().map { TimelineGroup(id: $0.description, name: nil, rows: buckets[$0]!) }
    }
    private func unassigned(_ rows: [TaskRow], id: String) -> [TimelineGroup] {
        rows.isEmpty ? [] : [TimelineGroup(id: id, name: nil, rows: rows)]
    }

    nonisolated static func snappedDays(points: Double, dayWidth: Double) -> Int? {
        guard points.isFinite, dayWidth.isFinite, dayWidth > 0 else { return nil }
        let value = (points / dayWidth).rounded()
        guard value.isFinite, abs(value) <= 3_652_425 else { return nil }
        return Int(value)
    }
    func shiftWindow(by days: Int) {
        guard (-3_652_425...3_652_425).contains(days) else { return }
        let length = visibleRange.upperBound.ordinal - visibleRange.lowerBound.ordinal
        let maximum = bounds.upperBound.ordinal - bounds.lowerBound.ordinal - length
        let offset = min(maximum, max(0, visibleRange.lowerBound.ordinal - bounds.lowerBound.ordinal + days))
        guard let first = bounds.lowerBound.addingDays(offset), let last = first.addingDays(length) else { return }
        visibleRange = first...last
    }

    func setVisibleRange(_ range: ClosedRange<CalendarDate>) {
        let first = min(max(range.lowerBound, bounds.lowerBound), bounds.upperBound)
        let last = max(first, min(range.upperBound, bounds.upperBound))
        visibleRange = first...last
    }
    func showToday() {
        visibleRange = (today.addingDays(-28) ?? today)...(today.addingDays(84) ?? today)
    }
    func dates(for row: TaskRow) -> TimelineDates { previews[row.id] ?? TimelineDates(row) }
    func beginDrag(_ row: TaskRow) -> TimelineDrag { TimelineDrag(row: row, root: store.vaultURL) }
    func preview(_ dates: TimelineDates?, for row: TaskRow) {
        if let dates, dates.isValid { previews[row.id] = dates } else { previews.removeValue(forKey: row.id) }
    }
    func rejectRange() { errorText = String(localized: "Bitiş tarihi başlangıçtan önce olamaz.") }

    @discardableResult
    func save(_ row: TaskRow, dates: TimelineDates, root: URL?) async -> Bool {
        guard dates.isValid else {
            rejectRange()
            previews.removeValue(forKey: row.id)
            return false
        }
        guard root == store.vaultURL, store.canAddEvent, !busy.contains(row.id) else {
            previews.removeValue(forKey: row.id)
            return false
        }
        guard dates != TimelineDates(row) else {
            previews.removeValue(forKey: row.id)
            return true
        }
        busy.insert(row.id)
        previews[row.id] = dates
        errorText = nil
        defer {
            busy.remove(row.id)
            previews.removeValue(forKey: row.id)
        }
        do {
            try await store.setTimelineDates(row, to: dates)
            return true
        } catch TimelineWriteError.partiallySaved {
            if root == store.vaultURL {
                errorText = String(localized: "Tarihler kısmen kaydedildi. Güncel tarihleri kontrol edin.")
            }
            return false
        } catch VaultStoreError.indexUpdateFailed {
            if root == store.vaultURL { errorText = EntryWriteError.savedWithoutIndex }
            return true
        } catch {
            if root == store.vaultURL { errorText = DayEditError.message(for: error) }
            return false
        }
    }
    func clearInteraction() {
        previews.removeAll()
        collapsed.removeAll()
        tasks.clearFilters()
        showToday()
    }
}
