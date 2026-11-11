import SwiftUI
import VaultFormat

struct TimelineDesktopView: View {
    let model: TimelineModel
    let todayRequest: UUID
    /// The period pill's step (hosted chart): scrolls the chart to its first day.
    var periodRequest: TimelinePeriodRequest? = nil
    /// The phone's Çeyrek chart (tab shell): the chart sits in a card at the page margins with
    /// a narrow label column and one-line titles; the bars are not dragged (screens.md
    /// "Telefon": no drag), the date changes from the menu.
    var compact = false
    let select: (TaskRow) -> Void
    let edit: (TaskRow, TimelineDates.Edge) -> Void
    @ScaledMetric(relativeTo: .body) private var compactLabelWidth: CGFloat = 142
    @ScaledMetric(relativeTo: .body) private var compactRowHeight: CGFloat = 52

    private var labelColumnWidth: CGFloat { compact ? compactLabelWidth : TimelineDesktopMetrics.labelColumnWidth }
    private var rowHeight: CGFloat { compact ? compactRowHeight : TimelineDesktopMetrics.rowHeight }
    private var outerMargin: CGFloat { compact ? InkSpacing.margin : 0 }

    var body: some View {
        GeometryReader { geometry in
            let chartWidth = max(
                compact ? 120 : 200, geometry.size.width - outerMargin * 2 - labelColumnWidth)
            let dayWidth = chartWidth / CGFloat(model.scale.daysAcross)
            let groups = model.groups
            // Not while the first answer is on its way: an empty timeline must not show while it loads.
            let isEmpty = groups.isEmpty && model.rows != nil
            let height =
                TimelineDesktopMetrics.axisHeight
                + groups.reduce(CGFloat(0)) { partial, group in
                    let rows = model.collapsed.contains(group.id) ? 0 : group.rows.count
                    return partial + TimelineDesktopMetrics.groupHeaderHeight
                        + CGFloat(rows) * rowHeight
                }
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 0) {
                        labels(groups).frame(width: labelColumnWidth)
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
                            .onChange(of: periodRequest) { _, request in
                                guard let request else { return }
                                proxy.scrollTo(request.start.description, anchor: .leading)
                            }
                            .onChange(of: model.scale) { _, _ in scrollToday(proxy) }
                        }.frame(height: height)
                    }
                    .frame(height: height)
                    .environment(\.timelineRowHeight, rowHeight)
                    .environment(\.timelineDragsBars, !compact)
                    // The phone's empty period sits in the chart's card, under its axis (one card).
                    if isEmpty {
                        if compact {
                            TimelineEmptyPeriod().padding(.vertical, InkSpacing.section)
                        } else {
                            EmptyState("Görev yok.")
                                .padding()
                        }
                    }
                }
                .modifier(TimelineChartCard(isOn: compact))
                .padding(.horizontal, outerMargin)
                if !model.undated.isEmpty {
                    undatedCard
                }
            }
        }
        // The phone's carded chart lies on the page's paper (and glow); the desktop chart keeps
        // its own paper.
        .background(compact ? Color.clear : Color.ink.paper)
    }

    /// The undated tasks: a section header and the rows in one card, under the chart (the
    /// phone, iPad and Mac alike).
    private var undatedCard: some View {
        VStack(alignment: .leading, spacing: InkSpacing.row) {
            SectionHeader(title: String(localized: "Tarihsiz"), counter: TasksCounter.tasks(model.undated.count))
            InkCard(padded: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(model.undated.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { InkCardDivider().padding(.leading, InkSpacing.cardPadding) }
                        TimelineTaskRow(model: model, row: row) {
                            select(row)
                        } edit: {
                            edit(row, $0)
                        }
                        .padding(.horizontal, InkSpacing.cardPadding)
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .padding(.horizontal, compact ? InkSpacing.margin : InkSpacing.cardPadding)
        .padding(.top, InkSpacing.section)
        .padding(.bottom, InkSpacing.section)
    }
    private func labels(_ groups: [TimelineGroup]) -> some View {
        VStack(spacing: 0) {
            Text("Görevler")
                .font(compact ? .ink.meta.weight(.semibold) : .ink.section)
                .foregroundStyle(.ink.text)
                .frame(height: TimelineDesktopMetrics.axisHeight)
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
                        if model.grouping == .project {
                            Circle().fill(ProjectColor.color(for: group.name))
                                .frame(width: 8, height: 8)
                                .accessibilityHidden(true)
                        }
                        TimelineGroupTitle(group: group, grouping: model.grouping)
                            .font(compact ? .ink.meta.weight(.semibold) : .ink.meta)
                            .foregroundStyle(.ink.text)
                            .lineLimit(1)
                        if compact {
                            TasksCountPill(count: group.rows.count)
                            Spacer(minLength: 0)
                        } else {
                            Spacer()
                            Text(group.rows.count.formatted())
                                .font(.ink.value)
                                .foregroundStyle(.ink.secondaryText)
                        }
                    }
                    .padding(.horizontal, 10)
                }
                .buttonStyle(.plain).frame(height: TimelineDesktopMetrics.groupHeaderHeight)
                .accessibilityValue(
                    Text(verbatim: VoiceOverCopy.disclosureValue(isExpanded: isExpanded)))
                if isExpanded {
                    ForEach(group.rows) { row in
                        let presentation = TaskStatusPresentation.make(
                            due: row.due, asOf: model.today, isCompleted: row.isClosed)
                        VStack(alignment: .leading, spacing: 2) {
                            LinkedTextView(
                                text: row.text, store: model.store,
                                isMuted: presentation.usesSecondaryText
                            )
                            .font(compact ? .ink.meta : .ink.content)
                            .lineLimit(compact ? 1 : 2)
                            .foregroundStyle(
                                presentation.usesSecondaryText
                                    ? Color.ink.secondaryText
                                    : Color.ink.text
                            )
                            TimelineTaskFacts(model: model, row: row, presentation: presentation, compact: compact)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .frame(height: rowHeight, alignment: .center)
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

/// ``EmptyState``'s content without its card: the phone chart's card already holds it.
private struct TimelineEmptyPeriod: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.title2)
                .foregroundStyle(Color.ink.secondaryText)
                .frame(width: 44, height: 44)
                .background(Color.ink.well, in: Circle())
                .accessibilityHidden(true)
            Text("Görev yok.")
                .font(.ink.placeholder)
                .foregroundStyle(Color.ink.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("emptyState")
        }
        .padding(.horizontal, InkSpacing.cardPadding)
    }
}

/// Card chrome of the phone's chart (``TimelineDesktopView/compact``).
private struct TimelineChartCard: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        if isOn {
            content
                .clipShape(RoundedRectangle(cornerRadius: InkCorner.card, style: .continuous))
                .modifier(InkCardModifier())
        } else {
            content
        }
    }
}

/// A count in a small capsule: phone chart groups and phone kanban columns. The column's pill
/// is outlined and semibold so it reads on the page's glow, not only on a card (Şafak drawing).
struct TasksCountPill: View {
    let count: Int
    var isOutlined = false

    var body: some View {
        Text(count.formatted())
            .font(isOutlined ? .ink.meta.weight(.semibold) : .ink.meta)
            .monospacedDigit()
            .foregroundStyle(.ink.secondaryText)
            .padding(.horizontal, isOutlined ? 8 : 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.ink.well))
            .overlay {
                if isOutlined { Capsule().strokeBorder(Color.ink.line, lineWidth: InkStroke.rule) }
            }
    }
}

extension EnvironmentValues {
    /// Height of one chart row; the phone chart's rows are shorter (one-line titles).
    @Entry var timelineRowHeight: CGFloat = TimelineDesktopMetrics.rowHeight
    /// Whether a bar's ends are dragged: not on the phone chart.
    @Entry var timelineDragsBars = true
}

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
