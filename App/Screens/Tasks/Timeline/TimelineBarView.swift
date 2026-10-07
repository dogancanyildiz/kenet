#if os(macOS)
    import SwiftUI
    import VaultFormat

    struct TimelineBarView: View {
        let model: TimelineModel
        let row: TaskRow
        let dayWidth: CGFloat
        let select: () -> Void
        let edit: (TimelineDates.Edge) -> Void
        @State private var drag: TimelineDrag?
        private var width: CGFloat { CGFloat(model.days.count) * dayWidth }
        private var dates: TimelineDates { model.dates(for: row) }

        var body: some View {
            ZStack(alignment: .leading) {
                Color.clear
                if let span = dates.span(on: model.today)?.clipped(to: model.bounds) {
                    let offset = CGFloat(span.first.ordinal - model.bounds.lowerBound.ordinal) * dayWidth
                    let length = CGFloat(span.last.ordinal - span.first.ordinal + 1) * dayWidth
                    HStack(spacing: 0) {
                        if !span.isMilestone && dates.start.map(model.bounds.contains) == true { handle(.start) }
                        Spacer(minLength: 0)
                        if presentation.showsOverdueCue {
                            Image(systemName: "arrow.forward.circle")
                                .font(.ink.meta)
                                .foregroundStyle(.ink.warning)
                                .padding(.trailing, 4)
                        }
                        if span.isOpenEnded {
                            Image(systemName: "arrow.right")
                                .font(.ink.meta)
                                .foregroundStyle(.ink.secondaryText)
                                .padding(.trailing, 4)
                        }
                        if row.isClosed && !span.isMilestone {
                            Circle()
                                .fill(Color.ink.secondaryText)
                                .frame(width: 7, height: 7)
                                .padding(.trailing, 4)
                                .accessibilityHidden(true)
                        }
                        if !span.isMilestone && dates.due.map(model.bounds.contains) == true { handle(.due) }
                    }
                    .frame(
                        width: max(span.isMilestone ? 12 : 8, span.isMilestone ? 12 : length - 4),
                        height: span.isMilestone ? 12 : 22
                    )
                    .background { barChrome(isMilestone: span.isMilestone) }
                    .rotationEffect(.degrees(span.isMilestone ? 45 : 0))
                    .contentShape(Rectangle()).onTapGesture(perform: select)
                    .gesture(gesture(edge: nil))
                    .offset(x: offset + (span.isMilestone ? max(0, (dayWidth - 12) / 2) : 2))
                    .contextMenu { TimelineTaskMenu(edit: edit) }
                    .help(dates.isValid ? Text(verbatim: row.text.plainText) : Text("Geçersiz tarih aralığı"))
                    .accessibilityLabel(
                        Text(
                            verbatim: VoiceOverCopy.timelineBarLabel(
                                text: row.text.plainText, start: dates.start, due: dates.due,
                                isOverdue: presentation.showsOverdueCue))
                    )
                    .accessibilityAction(named: Text("Ayrıntıları göster"), select)
                    .accessibilityAction(named: Text(verbatim: VoiceOverCopy.changeDateActionName())) {
                        edit(.due)
                    }
                }
            }.frame(width: width, height: 52).clipped()
                .onDisappear { if !model.busy.contains(row.id) { model.preview(nil, for: row) } }
        }
        private var presentation: TaskStatusPresentation {
            .make(due: dates.due, asOf: model.today, isCompleted: row.isClosed)
        }
        private var barColor: Color {
            if !dates.isValid { return Color.ink.warning }
            if presentation.usesSecondaryText { return Color.ink.secondaryText }
            return presentation.showsOverdueCue ? Color.ink.warning : Color.ink.accent
        }

        @ViewBuilder private func barChrome(isMilestone: Bool) -> some View {
            let shape = RoundedRectangle(cornerRadius: isMilestone ? 0 : 5)
            if row.isClosed && !isMilestone {
                // Completed: outline bar + filled end cap (not color alone).
                shape.strokeBorder(Color.ink.secondaryText, lineWidth: InkStroke.control)
            } else {
                shape.fill(barColor)
            }
        }

        private func handle(_ edge: TimelineDates.Edge) -> some View {
            Capsule()
                .fill(Color.ink.surface)
                .frame(width: 3, height: 12)
                .padding(.horizontal, 5)
                .contentShape(Rectangle()).highPriorityGesture(gesture(edge: edge))
                .accessibilityLabel(edge == .start ? Text("Başlangıç tarihi") : Text("Bitiş tarihi"))
        }
        private func gesture(edge: TimelineDates.Edge?) -> some Gesture {
            DragGesture(minimumDistance: 3, coordinateSpace: .named("timeline-axis"))
                .onChanged { value in
                    guard model.store.canAddEvent, !model.busy.contains(row.id) else { return }
                    if drag == nil { drag = model.beginDrag(row) }
                    if let drag {
                        model.preview(proposed(drag, edge: edge, points: value.translation.width), for: drag.row)
                    }
                }
                .onEnded { value in
                    guard let original = drag else { return }
                    drag = nil
                    guard let dates = proposed(original, edge: edge, points: value.translation.width) else {
                        model.preview(nil, for: original.row)
                        model.rejectRange()
                        return
                    }
                    Task { await model.save(original.row, dates: dates, root: original.root) }
                }
        }
        private func proposed(_ drag: TimelineDrag, edge: TimelineDates.Edge?, points: CGFloat) -> TimelineDates? {
            guard let days = TimelineModel.snappedDays(points: points, dayWidth: dayWidth) else { return nil }
            let original = TimelineDates(drag.row)
            guard let edge else { return original.shifted(by: days) }
            guard let date = (edge == .start ? original.start : original.due)?.addingDays(days) else { return nil }
            return original.setting(edge, to: date)
        }
    }
#endif
