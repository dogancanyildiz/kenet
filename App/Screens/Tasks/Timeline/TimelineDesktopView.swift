import SwiftUI
import VaultFormat

#if os(macOS)

    struct TimelineDesktopView: View {
        let model: TimelineModel
        let todayRequest: UUID
        let select: (TaskRow) -> Void
        let edit: (TaskRow, TimelineDates.Edge) -> Void

        var body: some View {
            GeometryReader { geometry in
                let chartWidth = max(200, geometry.size.width - 230)
                let dayWidth = chartWidth / CGFloat(model.scale.daysAcross)
                let groups = model.groups
                let height = CGFloat(
                    44 + groups.reduce(0) { $0 + 32 + (model.collapsed.contains($1.id) ? 0 : $1.rows.count * 52) })
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 0) {
                        labels(groups).frame(width: 230)
                        ScrollViewReader { proxy in
                            ScrollView(.horizontal) {
                                VStack(spacing: 0) {
                                    axis(dayWidth: dayWidth)
                                    ForEach(groups) { group in
                                        Color.clear.frame(height: 32)
                                        if !model.collapsed.contains(group.id) {
                                            ForEach(group.rows) { row in
                                                TimelineBarView(model: model, row: row, dayWidth: dayWidth) {
                                                    select(row)
                                                } edit: {
                                                    edit(row, $0)
                                                }
                                            }
                                        }
                                    }
                                }.frame(width: CGFloat(model.days.count) * dayWidth)
                                    .background {
                                        TimelineGrid(days: model.days, today: model.today, dayWidth: dayWidth)
                                    }
                                    .coordinateSpace(name: "timeline-axis")
                            }
                            .onScrollGeometryChange(for: ClosedRange<Int>.self) { value in
                                let first = min(
                                    model.days.count - 1, max(0, Int(floor(value.contentOffset.x / dayWidth))))
                                let last = min(
                                    model.days.count - 1,
                                    max(
                                        first,
                                        Int(ceil((value.contentOffset.x + value.containerSize.width) / dayWidth)) - 1))
                                return first...last
                            } action: { _, indices in
                                let days = model.days
                                model.setVisibleRange(days[indices.lowerBound]...days[indices.upperBound])
                            }
                            .task {
                                await Task.yield()
                                scrollToday(proxy)
                            }
                            .onChange(of: todayRequest) { _, _ in scrollToday(proxy) }
                            .onChange(of: model.scale) { _, _ in scrollToday(proxy) }
                        }.frame(height: height)
                    }.frame(height: height)
                    if groups.isEmpty { Text("Görev yok.").foregroundStyle(.secondary).padding() }
                    if !model.undated.isEmpty {
                        VStack(alignment: .leading) {
                            Text("Tarihsiz").font(.headline)
                            ForEach(model.undated) { row in
                                TimelineTaskRow(model: model, row: row) {
                                    select(row)
                                } edit: {
                                    edit(row, $0)
                                }
                            }
                        }.padding()
                    }
                }
            }
        }
        private func labels(_ groups: [TimelineGroup]) -> some View {
            VStack(spacing: 0) {
                Text("Görevler").font(.headline).frame(height: 44)
                ForEach(groups) { group in
                    Button {
                        if model.collapsed.contains(group.id) {
                            model.collapsed.remove(group.id)
                        } else {
                            model.collapsed.insert(group.id)
                        }
                    } label: {
                        HStack {
                            Image(systemName: model.collapsed.contains(group.id) ? "chevron.right" : "chevron.down")
                            TimelineGroupTitle(group: group, grouping: model.grouping).lineLimit(1)
                            Spacer()
                            Text(group.rows.count.formatted()).foregroundStyle(.secondary)
                        }.font(.caption).padding(.horizontal, 10)
                    }.buttonStyle(.plain).frame(height: 32)
                    if !model.collapsed.contains(group.id) {
                        ForEach(group.rows) { row in
                            let presentation = TaskStatusPresentation.make(
                                due: row.due, asOf: model.today, isCompleted: row.isClosed)
                            Group {
                                if presentation.usesSecondaryText {
                                    LinkedTextView(text: row.text, store: model.store).lineLimit(2)
                                        .foregroundStyle(.secondary)
                                } else {
                                    LinkedTextView(text: row.text, store: model.store).lineLimit(2)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).frame(
                                height: 52
                            )
                            .opacity(presentation.opacity).contentShape(Rectangle()).onTapGesture { select(row) }
                            .contextMenu { TimelineTaskMenu { edit(row, $0) } }
                        }
                    }
                }
            }
        }
        private func axis(dayWidth: CGFloat) -> some View {
            HStack(spacing: 0) {
                ForEach(model.days, id: \.self) { day in
                    ZStack {
                        if day.weekday >= 5 { Color.secondary.opacity(0.08) }
                        if day == model.today { Color.primary.opacity(0.08) }
                        if model.scale == .week || (model.scale == .month && day.weekday == 0) || day.day == 1 {
                            Text(LocalDay.instant(for: day), format: .dateTime.day().month(.abbreviated))
                                .font(.caption2).fixedSize().zIndex(1)
                        }
                    }.frame(width: dayWidth, height: 44).id(day.description)
                }
            }
        }
        private func scrollToday(_ proxy: ScrollViewProxy) {
            let date = model.today.addingDays(-min(28, model.scale.daysAcross / 4)) ?? model.today
            proxy.scrollTo(date.description, anchor: .leading)
        }
    }
#endif

struct TimelineGroupTitle: View {
    let group: TimelineGroup
    let grouping: TimelineModel.Grouping
    var body: some View {
        if let name = group.name {
            Text(verbatim: name)
        } else if grouping == .project {
            Text("Projesiz")
        } else if grouping == .person {
            Text("Kişisiz")
        } else {
            Text("Görevler")
        }
    }
}
