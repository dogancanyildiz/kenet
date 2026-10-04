import SwiftUI
import VaultFormat

struct TimelineTaskRow: View {
    let model: TimelineModel
    let row: TaskRow
    let select: () -> Void
    let edit: (TimelineDates.Edge) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LinkedTextView(text: row.text, store: model.store)
            HStack {
                if let start = row.start {
                    Text(LocalDay.instant(for: start), format: .dateTime.day().month().year())
                }
                if row.start != nil && row.due != nil { Image(systemName: "arrow.right") }
                if let due = row.due {
                    Text(LocalDay.instant(for: due), format: .dateTime.day().month().year())
                        .foregroundStyle(due < model.today && !row.isClosed ? Color.red : Color.secondary)
                } else if row.start != nil {
                    Text("Açık uçlu")
                }
                if let priority = row.priority { Text(verbatim: priority.token).accessibilityLabel("Öncelik") }
                if model.busy.contains(row.id) { ProgressView().controlSize(.small) }
            }.font(.caption).foregroundStyle(.secondary)
            if let span = model.dates(for: row).span(on: model.today) {
                GeometryReader { geometry in
                    let range = model.visibleRange
                    let count = Double(range.upperBound.ordinal - range.lowerBound.ordinal + 1)
                    if let visible = span.clipped(to: range) {
                        let x = Double(visible.first.ordinal - range.lowerBound.ordinal) / count * geometry.size.width
                        let width = max(
                            8, Double(visible.last.ordinal - visible.first.ordinal + 1) / count * geometry.size.width)
                        RoundedRectangle(cornerRadius: span.isMilestone ? 0 : 4)
                            .fill(row.isClosed ? Color.secondary : Color.accentColor)
                            .frame(width: span.isMilestone ? 8 : width, height: 8)
                            .rotationEffect(.degrees(span.isMilestone ? 45 : 0)).offset(x: x, y: 4)
                    }
                }.frame(height: 16).accessibilityHidden(true)
                if span.isReversed {
                    Label("Geçersiz tarih aralığı", systemImage: "exclamationmark.triangle").font(.caption)
                }
            }
        }
        .opacity(row.isClosed ? 0.45 : 1).padding(.vertical, 6)
        .contentShape(Rectangle()).onTapGesture(perform: select)
        .contextMenu { TimelineTaskMenu(edit: edit) }
        .accessibilityAction(named: Text("Ayrıntıları göster"), select)
    }
}
