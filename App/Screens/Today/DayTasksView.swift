import SwiftUI
import VaultFormat

struct DayTasksView: View {
    let store: IndexStore
    let date: CalendarDate
    let isToday: Bool
    @Bindable var model: DayTasksModel
    let presentation: TodayPresentation
    var entityIndex: [String: EntitySummary] = [:]
    var onExpandCarriedOver: () -> Void
    var onExpandCompleted: () -> Void
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    var body: some View {
        let rows = presentation.rows
        let carriedIDs = Set(presentation.carriedOverTasks.map(\.id))
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: InkSpacing.row) {
                SectionHeader(
                    title: String(
                        localized: "Görevler",
                        bundle: PresentationLocalization.bundle(locale), locale: locale),
                    counter: presentation.counter(for: .tasks))
                if let error = model.errorText {
                    InfoBand(kind: .error, verbatim: error)
                }
                ForEach(rows) { entry in
                    switch entry {
                    case .task(let row):
                        let isCarried = carriedIDs.contains(row.id)
                        DayTaskView(
                            store: store, row: row, isToday: isToday, isOverdue: isCarried,
                            completed: model.completed.contains(row.id) || row.isClosed,
                            isBusy: model.completing.contains(row.id), day: date,
                            carriedOverLabel: isCarried ? carriedOverText(for: row) : nil,
                            entityIndex: entityIndex
                        ) { Task { await model.complete(row) } }
                    case .carriedOverDisclosure(let text):
                        Button(action: onExpandCarriedOver) {
                            Text(verbatim: text)
                                .font(.ink.meta)
                                .foregroundStyle(Color.ink.warning)
                                // Vertically center in the 44 pt floor; outer rhythm is
                                // ``InkSpacing.row`` from the parent stack.
                                .frame(
                                    maxWidth: .infinity, minHeight: TapTarget.minimumLength,
                                    alignment: .leading
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    case .completedDisclosure(let text):
                        Button(action: onExpandCompleted) {
                            Text(verbatim: text)
                                .font(.ink.meta)
                                .foregroundStyle(Color.ink.secondaryText)
                                .frame(
                                    maxWidth: .infinity, minHeight: TapTarget.minimumLength,
                                    alignment: .leading
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
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
