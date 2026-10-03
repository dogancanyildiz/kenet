import Foundation
import Observation
import VaultFormat
import VaultStore

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

    init(store: IndexStore, day: CalendarDate, isToday: Bool) {
        self.store = store
        self.day = day
        self.isToday = isToday
    }

    var groups: TaskGroups {
        var rows = store.content.tasks
        if retainedRoot == store.vaultURL {
            let ids = Set(rows.map(\.id))
            rows += retained.filter { !ids.contains($0.id) }
            // Closed source rows need the open pre-write row for the brief fade on Today.
            for row in retained {
                if let index = rows.firstIndex(where: { $0.id == row.id }) { rows[index] = row }
            }
        }
        return TaskGroups(rows: rows, on: day, isToday: isToday)
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
