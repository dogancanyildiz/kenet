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
    var onExpandTasks: () -> Void = {}
    var onExpandCompleted: () -> Void
    /// Mac Today desk: the hour grid owns today's timed tasks, so this list leaves them out.
    var deskPlan: TodayDeskPlan? = nil
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @State private var moveReport: TaskMoveReport?
    @State private var isMovingCarriedOver = false

    var body: some View {
        let rows = deskPlan?.dayListTaskRows(presentation.rows) ?? presentation.rows
        let carriedIDs = Set(presentation.carriedOverTasks.map(\.id))
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: InkSpacing.row) {
                SectionHeader(
                    title: String(
                        localized: "Görevler",
                        bundle: PresentationLocalization.bundle(locale), locale: locale),
                    // "6 kaldı": the open tasks, worded (the drawing); the Mac desk keeps its own.
                    counter: deskPlan?.dayListTaskCounter(presentation)
                        ?? String(
                            localized: "\(presentation.remainingTaskCount) kaldı",
                            bundle: PresentationLocalization.bundle(locale), locale: locale)
                )
                .modifier(carriedOverCommands)
                InkCard(padded: true) {
                    if let error = model.errorText {
                        InfoBand(kind: .error, verbatim: error)
                    }
                    if let report = moveReport, let text = report.text(locale: locale) {
                        InfoBand(kind: report.isPartial ? .warning : .info, verbatim: text)
                    }
                    if let failure = moveReport?.failureText {
                        InfoBand(kind: .error, verbatim: failure)
                    }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { InkCardDivider() }
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
                                    .frame(
                                        maxWidth: .infinity, minHeight: TapTarget.minimumLength,
                                        alignment: .leading
                                    )
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(text)
                            .modifier(carriedOverCommands)
                        case .moreTasksDisclosure(let text):
                            Button(action: onExpandTasks) {
                                // Only carried-over tasks behind the fold: same words and tint as
                                // the iPad and Mac carried-over line.
                                Text(verbatim: text)
                                    .font(.ink.meta)
                                    .foregroundStyle(
                                        presentation.hiddenOpenTasksAreCarriedOver
                                            ? Color.ink.warning : Color.ink.secondaryText
                                    )
                                    .frame(
                                        maxWidth: .infinity, minHeight: TapTarget.minimumLength,
                                        alignment: .leading
                                    )
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(text)
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
            // The result belongs to the day it was produced on.
            .onChange(of: date) { moveReport = nil }
        }
    }

    /// Full carried-over list, including tasks folded behind the disclosure.
    private var carriedOverCommands: MoveCarriedOverCommands {
        MoveCarriedOverCommands(
            enabled: isToday && !model.groups.overdue.isEmpty, isBusy: isMovingCarriedOver,
            move: moveCarriedOver)
    }

    private func moveCarriedOver() {
        guard isToday, !isMovingCarriedOver, store.canAddEvent else { return }
        let rows = model.groups.overdue
        guard !rows.isEmpty else { return }
        isMovingCarriedOver = true
        moveReport = nil
        Task {
            moveReport = await TaskMove.apply(rows, to: date, in: store)
            isMovingCarriedOver = false
        }
    }

    private func carriedOverText(for row: TaskRow) -> String? {
        guard let due = row.due else { return nil }
        return TodayPresentation.carriedOverPhrase(
            due, today: date, locale: presentation.locale, calendar: calendar)
    }
}

/// Context menu and VoiceOver action for moving every carried-over task to today.
private struct MoveCarriedOverCommands: ViewModifier {
    let enabled: Bool
    let isBusy: Bool
    let move: () -> Void

    @ViewBuilder func body(content: Content) -> some View {
        if enabled {
            content
                .contextMenu {
                    Button("Hepsini bugüne", action: move)
                        .disabled(isBusy)
                }
                .accessibilityAction(named: Text("Hepsini bugüne")) {
                    if !isBusy { move() }
                }
        } else {
            content
        }
    }
}
