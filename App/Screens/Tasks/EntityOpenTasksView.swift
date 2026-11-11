import SwiftUI

/// Open tasks linking to an entity. The page queries the rows with its timeline
/// (`IndexStore.computeTaskGroups(today:scope:)`, linked to the entity), since a section that
/// draws nothing is never mounted to query them itself.
struct EntityOpenTasksView: View {
    let store: IndexStore
    let rows: [TaskRow]
    @State private var model: TasksModel

    init(store: IndexStore, rows: [TaskRow]) {
        self.store = store
        self.rows = rows
        _model = State(initialValue: TasksModel(store: store))
    }

    @Environment(\.locale) private var locale

    var body: some View {
        if !rows.isEmpty || model.errorText != nil {
            Section {
                SectionHeader(
                    title: PresentationLocalization.string(localized: "Açık işler", locale: locale),
                    count: rows.count
                )
                .inkListRow()
                // One card with dividers, like the page's other sections (Şafak drawing, fark3 Y6).
                InkCard(padded: true) {
                    if let error = model.errorText {
                        InfoBand(kind: .error, verbatim: error)
                    }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { InkCardDivider() }
                        DayTaskView(
                            store: store, row: row, isToday: true,
                            isOverdue: row.due.map { $0 < model.day } ?? false,
                            completed: false, isBusy: model.busy.contains(row.id)
                        ) { Task { await model.toggle(row) } }
                    }
                }
                .inkListRow()
            }
        }
    }
}
