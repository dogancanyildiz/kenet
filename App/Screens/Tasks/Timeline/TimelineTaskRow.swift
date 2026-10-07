import SwiftUI
import VaultFormat

struct TimelineTaskRow: View {
    let model: TimelineModel
    let row: TaskRow
    let select: () -> Void
    let edit: (TimelineDates.Edge) -> Void

    private var presentation: TaskStatusPresentation {
        .make(due: row.due, asOf: model.today, isCompleted: row.isClosed)
    }

    private var spokenValue: String {
        var parts: [String] = []
        if let priority = row.priority {
            parts.append(VoiceOverCopy.priorityValue(priority))
        }
        if presentation.showsOverdueCue {
            parts.append(String(localized: "Devreden"))
        }
        if row.isClosed {
            parts.append(VoiceOverCopy.taskCompletionValue(isCompleted: true))
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LinkedTextView(
                text: row.text, store: model.store, isMuted: presentation.usesSecondaryText
            )
            .font(.ink.content)
            .foregroundStyle(
                presentation.usesSecondaryText ? Color.ink.secondaryText : Color.ink.text)
            HStack(spacing: 6) {
                if let start = row.start {
                    Text(LocalDay.instant(for: start), format: .dateTime.day().month().year())
                        .font(.ink.time)
                        .foregroundStyle(.ink.secondaryText)
                        .monospacedDigit()
                }
                if row.start != nil && row.due != nil {
                    Image(systemName: "arrow.right")
                        .font(.ink.meta)
                        .foregroundStyle(.ink.secondaryText)
                }
                if let due = row.due {
                    TaskDueDateLabel(
                        date: due, presentation: presentation, asOf: model.today,
                        format: .dateTime.day().month().year(),
                        font: .ink.time
                    )
                    .monospacedDigit()
                } else if row.start != nil {
                    Text("Açık uçlu")
                        .font(.ink.meta)
                        .foregroundStyle(.ink.secondaryText)
                }
                if let priority = row.priority {
                    TaskPriorityMark(priority: priority)
                }
                if row.isClosed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.ink.meta)
                        .foregroundStyle(.ink.secondaryText)
                        .accessibilityHidden(true)
                }
                if model.busy.contains(row.id) { ProgressView().controlSize(.small) }
            }
            if let span = model.dates(for: row).span(on: model.today), span.isReversed {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                    Text("Geçersiz tarih aralığı")
                }
                .font(.ink.meta)
                .foregroundStyle(.ink.warning)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle()).onTapGesture(perform: select)
        .contextMenu { TimelineTaskMenu(edit: edit) }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(verbatim: spokenValue))
        .accessibilityAction(named: Text("Ayrıntıları göster"), select)
        .accessibilityAction(named: Text(verbatim: VoiceOverCopy.changeDateActionName())) {
            edit(.due)
        }
    }
}
