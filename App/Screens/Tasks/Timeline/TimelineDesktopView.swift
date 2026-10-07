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
                                TimelineDesktopContent(
                                    model: model,
                                    days: model.days,
                                    dayWidth: dayWidth,
                                    select: select,
                                    edit: edit
                                )
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
                    if groups.isEmpty {
                        EmptyState("Görev yok.")
                            .padding()
                    }
                    if !model.undated.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: String(localized: "Tarihsiz"), count: model.undated.count)
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
            .background(Color.ink.paper)
        }
        private func labels(_ groups: [TimelineGroup]) -> some View {
            VStack(spacing: 0) {
                Text("Görevler")
                    .font(.ink.section)
                    .foregroundStyle(.ink.text)
                    .frame(height: 44)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                ForEach(groups) { group in
                    let isExpanded = !model.collapsed.contains(group.id)
                    Button {
                        if model.collapsed.contains(group.id) {
                            model.collapsed.remove(group.id)
                        } else {
                            model.collapsed.insert(group.id)
                        }
                    } label: {
                        HStack {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .foregroundStyle(.ink.secondaryText)
                            TimelineGroupTitle(group: group, grouping: model.grouping)
                                .font(.ink.meta)
                                .foregroundStyle(.ink.text)
                                .lineLimit(1)
                            Spacer()
                            Text(group.rows.count.formatted())
                                .font(.ink.value)
                                .foregroundStyle(.ink.secondaryText)
                        }
                        .padding(.horizontal, 10)
                    }
                    .buttonStyle(.plain).frame(height: 32)
                    .accessibilityValue(
                        Text(verbatim: VoiceOverCopy.disclosureValue(isExpanded: isExpanded)))
                    if isExpanded {
                        ForEach(group.rows) { row in
                            let presentation = TaskStatusPresentation.make(
                                due: row.due, asOf: model.today, isCompleted: row.isClosed)
                            LinkedTextView(
                                text: row.text, store: model.store,
                                isMuted: presentation.usesSecondaryText
                            )
                            .font(.ink.content)
                            .lineLimit(2)
                            .foregroundStyle(
                                presentation.usesSecondaryText
                                    ? Color.ink.secondaryText
                                    : Color.ink.text
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .frame(height: 52)
                            .contentShape(Rectangle()).onTapGesture { select(row) }
                            .contextMenu { TimelineTaskMenu { edit(row, $0) } }
                        }
                    }
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
