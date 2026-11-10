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

    private var title: some View {
        LinkedTextView(
            text: row.text, store: model.store, isMuted: presentation.usesSecondaryText
        )
        .font(.ink.content)
        .foregroundStyle(
            presentation.usesSecondaryText ? Color.ink.secondaryText : Color.ink.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if row.start == nil && row.due == nil {
                // An undated row has no date line: its marks (priority, done) sit beside the text.
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    title
                    Spacer(minLength: 0)
                    TimelineTaskFacts(model: model, row: row, presentation: presentation)
                }
            } else {
                title
                TimelineTaskFacts(model: model, row: row, presentation: presentation)
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

/// Tabular start/due line shared by the phone row and the Mac label column: dates, the
/// priority mark and the closed check. Digits stay tabular (``.ink.time``).
struct TimelineTaskFacts: View {
    let model: TimelineModel
    let row: TaskRow
    let presentation: TaskStatusPresentation
    /// The phone chart's narrow label column: day and short month, no year ("1 Eki → 30 Kas").
    var compact = false

    private var format: Date.FormatStyle {
        compact ? .dateTime.day().month(.abbreviated) : .dateTime.day().month().year()
    }

    private var font: Font { compact ? .ink.meta.monospacedDigit() : .ink.time }

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            if let start = row.start {
                Text(LocalDay.instant(for: start), format: format)
                    .font(font)
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
                    format: format,
                    font: font
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
    }
}
