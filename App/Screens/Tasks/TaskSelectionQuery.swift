import Foundation

/// Request for the selected task's current row: another task or a write (a new `updated`) asks
/// the index again.
struct TaskSelectionRequest: Hashable {
    let id: String?
    let updated: Date?
}

/// The selected task as the index last answered for it. A detail shows the task as it is now,
/// wherever it is in the vault, not only while a list or board still lists it.
struct TaskSelectionAnswer {
    private var id: String?
    private var row: TaskRow?

    init() {}

    /// The answer for `id`; until the index has answered for it, `listed` (the row that was tapped
    /// or is listed with that id). Nil once the task is gone.
    func row(for id: String?, listed: TaskRow?) -> TaskRow? {
        guard let id else { return nil }
        if self.id == id { return row }
        return listed?.id == id ? listed : nil
    }

    /// Asks the index for `request`'s task. A query cancelled or outlived by its vault answers
    /// nothing, so the previous answer stays.
    static func load(_ request: TaskSelectionRequest, store: IndexStore) async -> Self? {
        guard let id = request.id else { return nil }
        do {
            var answer = Self()
            answer.row = try await store.computeTask(id: id)
            answer.id = id
            return answer
        } catch {
            return nil
        }
    }
}
