import Foundation
import Observation
import VaultFormat
import VaultStore

/// Request for a day page's task rows: a new model (another day) or a write asks again.
struct DayTasksRequest: Hashable {
    let model: ObjectIdentifier
    let updated: Date?
}

@MainActor @Observable
final class DayTasksModel {
    let store: IndexStore
    let day: CalendarDate
    let isToday: Bool
    private(set) var completing: Set<String> = []
    private(set) var completed: Set<String> = []
    private(set) var errorText: String?
    private var retained: [TaskRow] = []
    private var retainedRoot: URL?
    /// The day's candidate rows (``IndexStore/computeDayTasks(on:)``), nil until the first answer;
    /// a reload keeps the previous rows until then.
    private(set) var rows: [TaskRow]?
    /// The publish (``IndexStore/lastUpdated``) `rows` were asked for.
    private var rowsUpdated: Date?

    var isLoaded: Bool { rows != nil }

    /// Whether `rows` answer the store's latest publish. An answer asked for before the vault was
    /// published (no index open yet: no rows) is loaded but not current.
    var isCurrent: Bool { rows != nil && rowsUpdated == store.lastUpdated }

    init(store: IndexStore, day: CalendarDate, isToday: Bool) {
        self.store = store
        self.day = day
        self.isToday = isToday
    }

    /// Asks the index for the day's rows again; a reload cancelled or outlived by its vault leaves
    /// the rows as they were.
    func load() async {
        let updated = store.lastUpdated
        if let loaded = try? await store.computeDayTasks(on: day) {
            rows = loaded
            rowsUpdated = updated
        }
    }

    var groups: TaskGroups {
        TaskGroups(rows: mergedRows, on: day, isToday: isToday)
    }

    /// Closed rows for ``TodayPresentation`` (Today's groups drop them; past days keep them).
    var completedTasksForPresentation: [TaskRow] {
        mergedRows.filter {
            completed.contains($0.id) || $0.rawStatus == "x" || $0.rawStatus == "X" || $0.rawStatus == "-"
        }
    }

    private var mergedRows: [TaskRow] {
        var rows = self.rows ?? []
        if retainedRoot == store.vaultURL {
            let ids = Set(rows.map(\.id))
            rows += retained.filter { !ids.contains($0.id) }
            // Closed source rows need the open pre-write row for the brief fade on Today.
            for row in retained {
                if let index = rows.firstIndex(where: { $0.id == row.id }) { rows[index] = row }
            }
        }
        return rows
    }

    @discardableResult
    func complete(_ row: TaskRow, today: CalendarDate = LocalDay.today()) async -> Bool {
        guard !row.isClosed, !completing.contains(row.id), !completed.contains(row.id), store.canAddEvent else {
            return false
        }
        let root = store.vaultURL
        errorText = nil
        completing.insert(row.id)
        retainedRoot = root
        retained.append(row)
        defer {
            completing.remove(row.id)
            retained.removeAll { $0.id == row.id }
            completed.remove(row.id)
        }
        var saved = false
        do {
            try await store.completeTask(row, on: today)
            saved = true
        } catch VaultStoreError.indexUpdateFailed {
            saved = true
            errorText = String(localized: "Değişiklik kaydedildi, indeks güncellenemedi.")
        } catch {
            errorText = DayEditError.message(for: error)
        }
        if saved && root == store.vaultURL {
            completed.insert(row.id)
            try? await Task.sleep(for: .milliseconds(700))
        }
        return saved
    }
}
