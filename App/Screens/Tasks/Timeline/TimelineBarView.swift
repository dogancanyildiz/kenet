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
                let barWidth = max(span.isMilestone ? 12 : 8, span.isMilestone ? 12 : length - 4)
                HStack(spacing: 0) {
                    if !span.isMilestone && dates.start.map(model.bounds.contains) == true {
                        handle(.start, barWidth: barWidth)
                    }
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
                    if !span.isMilestone && dates.due.map(model.bounds.contains) == true {
                        handle(.due, barWidth: barWidth)
                    }
                }
                .frame(width: barWidth, height: span.isMilestone ? 12 : 22)
                .background { barChrome(isMilestone: span.isMilestone) }
                .rotationEffect(.degrees(span.isMilestone ? 45 : 0))
                // The bar's shape bounds its ends' touch areas too: it reaches as far as they do.
                // A short bar draws its grips past its own frame (quarter scale).
                .contentShape(Rectangle().inset(by: -TimelineBarTouch.handleOutset)).onTapGesture(perform: select)
                .gesture(gesture(edge: nil), including: TimelineBarTouch.dragsBody ? .all : .subviews)
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
        }.frame(width: width, height: TimelineDesktopMetrics.rowHeight).clipped()
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

    private func handle(_ edge: TimelineDates.Edge, barWidth: CGFloat) -> some View {
        let reach = TimelineBarTouch.handleReach(edge, barWidth: barWidth)
        return Capsule()
            .fill(Color.ink.surface)
            .frame(width: 3, height: TimelineBarTouch.gripHeight)
            .padding(.horizontal, (TimelineBarTouch.gripWidth - 3) / 2)
            .padding(reach)
            .contentShape(Rectangle())
            .padding(
                EdgeInsets(top: -reach.top, leading: -reach.leading, bottom: -reach.bottom, trailing: -reach.trailing)
            )
            .highPriorityGesture(gesture(edge: edge))
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
        TimelineModel.proposedDates(
            from: TimelineDates(drag.row), edge: edge, points: Double(points), dayWidth: Double(dayWidth))
    }
}

extension TimelineModel {
    /// The dates a drag proposes (unit-tested): `points` along the axis snap to whole days
    /// (``snappedDays(points:dayWidth:)``); the body (`edge == nil`) moves both dates, an end
    /// moves its own date. `nil` when the drag snaps to nothing or the range would be invalid.
    nonisolated static func proposedDates(
        from original: TimelineDates, edge: TimelineDates.Edge?, points: Double, dayWidth: Double
    ) -> TimelineDates? {
        guard let days = snappedDays(points: points, dayWidth: dayWidth) else { return nil }
        guard let edge else { return original.shifted(by: days) }
        guard let date = (edge == .start ? original.start : original.due)?.addingDays(days) else { return nil }
        return original.setting(edge, to: date)
    }
}

/// How a bar answers touch (iPad, the iPhone Duo inner screen). A finger that lands on the
/// bar's body scrolls the chart, as a swipe anywhere else does; only an end is dragged, and the
/// end's touch area reaches past the drawn grip. The pointer (Mac) also drags the whole bar.
enum TimelineBarTouch {
    #if os(macOS)
        static let dragsBody = true
        static let handleOutset: CGFloat = 0
    #else
        static let dragsBody = false
        /// Grows the 13 × 12 pt grip to a 37 × 36 pt touch area on a bar long enough for both.
        static let handleOutset: CGFloat = 12
    #endif
    /// The drawn grip: a 3 pt capsule with room on both sides.
    static let gripWidth: CGFloat = 13
    static let gripHeight: CGFloat = 12

    /// Where an end answers touch, in its grip's coordinates (unit-tested). The area reaches
    /// `outset` past the grip on every side but the inner one: toward the other end it stops at
    /// the bar's middle. On a short bar (quarter scale, a few days) the two areas would cover each
    /// other and the due end would take every touch; this way each end keeps its own half.
    static func handleArea(
        _ edge: TimelineDates.Edge, barWidth: CGFloat, outset: CGFloat = handleOutset
    ) -> CGRect {
        let inward = min(outset, max(0, barWidth / 2 - gripWidth))
        return CGRect(
            x: edge == .start ? -outset : -inward, y: -outset,
            width: gripWidth + outset + inward, height: gripHeight + outset * 2)
    }

    /// ``handleArea(_:barWidth:outset:)`` as the room the grip's touch area takes on each side
    /// (padding around the grip, given back to the layout after the content shape).
    static func handleReach(_ edge: TimelineDates.Edge, barWidth: CGFloat) -> EdgeInsets {
        let area = handleArea(edge, barWidth: barWidth)
        return EdgeInsets(
            top: -area.minY, leading: -area.minX, bottom: area.maxY - gripHeight, trailing: area.maxX - gripWidth)
    }
}
