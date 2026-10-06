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

    private var barColor: Color {
        if presentation.showsOverdueCue { return Color.ink.warning }
        if presentation.usesSecondaryText { return Color.ink.secondaryText }
        return Color.ink.accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LinkedTextView(text: row.text, store: model.store)
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
                        date: due, presentation: presentation,
                        format: .dateTime.day().month().year()
                    )
                    .font(.ink.time)
                    .monospacedDigit()
                } else if row.start != nil {
                    Text("Açık uçlu")
                        .font(.ink.meta)
                        .foregroundStyle(.ink.secondaryText)
                }
                if row.isClosed {
                    Image(systemName: "circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.ink.secondaryText)
                        .accessibilityLabel(Text("Tamamlandı"))
                }
                if model.busy.contains(row.id) { ProgressView().controlSize(.small) }
            }
            if let span = model.dates(for: row).span(on: model.today) {
                GeometryReader { geometry in
                    let range = model.visibleRange
                    let count = Double(range.upperBound.ordinal - range.lowerBound.ordinal + 1)
                    if let visible = span.clipped(to: range) {
                        let start = Double(visible.first.ordinal - range.lowerBound.ordinal)
                        let spanDays = Double(visible.last.ordinal - visible.first.ordinal + 1)
                        let x = start / count * geometry.size.width
                        let width = max(8, spanDays / count * geometry.size.width)
                        HStack(spacing: 0) {
                            RoundedRectangle(cornerRadius: span.isMilestone ? 0 : 4)
                                .fill(barColor)
                                .frame(width: span.isMilestone ? 8 : width, height: 8)
                                .rotationEffect(.degrees(span.isMilestone ? 45 : 0))
                            if row.isClosed && !span.isMilestone {
                                Circle()
                                    .fill(Color.ink.secondaryText)
                                    .frame(width: 8, height: 8)
                                    .offset(x: -4)
                            }
                            if presentation.showsOverdueCue {
                                Image(systemName: "arrow.forward.circle")
                                    .font(.caption2)
                                    .foregroundStyle(.ink.warning)
                                    .offset(x: 2)
                            }
                        }
                        .offset(x: x, y: 4)
                    }
                }.frame(height: 16).accessibilityHidden(true)
                if span.isReversed {
                    Label("Geçersiz tarih aralığı", systemImage: "exclamationmark.triangle")
                        .font(.ink.meta)
                        .foregroundStyle(.ink.warning)
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle()).onTapGesture(perform: select)
        .contextMenu { TimelineTaskMenu(edit: edit) }
        .accessibilityAction(named: Text("Ayrıntıları göster"), select)
        .accessibilityAction(named: Text(verbatim: VoiceOverCopy.changeDateActionName())) {
            edit(.due)
        }
    }
}
