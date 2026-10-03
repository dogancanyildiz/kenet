import SwiftUI
import VaultFormat

struct DayTasksView: View {
    let store: IndexStore
    let date: CalendarDate
    let isToday: Bool
    @State private var model: DayTasksModel

    init(store: IndexStore, date: CalendarDate, isToday: Bool) {
        self.store = store
        self.date = date
        self.isToday = isToday
        _model = State(initialValue: DayTasksModel(store: store, day: date, isToday: isToday))
    }

    var body: some View {
        let groups = model.groups
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Görevler").font(.headline).accessibilityAddTraits(.isHeader)
                if let error = model.errorText { Text(verbatim: error).font(.caption).foregroundStyle(.red) }
                group(groups.overdue, title: "Geciken", overdue: true)
                group(groups.dated, title: isToday ? "Bugünün görevleri" : "Bu günün görevleri")
                group(groups.created, title: "Bu gün oluşturulan tarihsiz görevler")
            }
        }
    }

    @ViewBuilder private func group(_ rows: [TaskRow], title: LocalizedStringKey, overdue: Bool = false) -> some View {
        if !rows.isEmpty {
            Text(title).font(.subheadline).foregroundStyle(.secondary).accessibilityAddTraits(.isHeader)
            ForEach(rows) { row in
                DayTaskView(
                    store: store, row: row, isToday: isToday, isOverdue: overdue,
                    completed: model.completed.contains(row.id), isBusy: model.completing.contains(row.id)
                ) { Task { await model.complete(row) } }
            }
        }
    }
}
