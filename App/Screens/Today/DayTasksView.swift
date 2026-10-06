import SwiftUI
import VaultFormat

struct DayTasksView: View {
    let store: IndexStore
    let date: CalendarDate
    let isToday: Bool
    @Bindable var model: DayTasksModel
    let presentation: TodayPresentation
    var onExpandCarriedOver: () -> Void
    var onExpandCompleted: () -> Void
    @Environment(\.calendar) private var calendar

    var body: some View {
        let rows = presentation.taskRows
        let carriedIDs = Set(presentation.carriedOverTasks.map(\.id))
        if !rows.isEmpty || presentation.carriedOverDisclosure != nil
            || presentation.completedDisclosure != nil
        {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(
                    title: String(localized: "Görevler"),
                    counter: presentation.counter(for: .tasks))
                if let error = model.errorText {
                    InfoBand(kind: .error, verbatim: error)
                }
                ForEach(rows) { row in
                    let isCarried = carriedIDs.contains(row.id)
                    DayTaskView(
                        store: store, row: row, isToday: isToday, isOverdue: isCarried,
                        completed: model.completed.contains(row.id) || row.isClosed,
                        isBusy: model.completing.contains(row.id),
                        carriedOverLabel: isCarried ? carriedOverText(for: row) : nil
                    ) { Task { await model.complete(row) } }
                }
                if let disclosure = presentation.carriedOverDisclosure {
                    Button(action: onExpandCarriedOver) {
                        Text(verbatim: disclosure)
                            .font(.ink.meta)
                            .foregroundStyle(Color.ink.warning)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .tapTarget()
                    }
                    .buttonStyle(.plain)
                }
                if let disclosure = presentation.completedDisclosure {
                    Button(action: onExpandCompleted) {
                        Text(verbatim: disclosure)
                            .font(.ink.meta)
                            .foregroundStyle(Color.ink.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .tapTarget()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func carriedOverText(for row: TaskRow) -> String? {
        guard let due = row.due else { return nil }
        return TodayPresentation.carriedOverDate(
            due, today: date, locale: presentation.locale, calendar: calendar)
    }
}
