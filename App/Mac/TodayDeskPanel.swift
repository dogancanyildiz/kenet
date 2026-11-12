import GoalTracking
import Summaries
import SwiftUI
import VaultFormat

#if os(macOS)
    /// Sections shared by the Mac Today right panel and the folded-under-grid layout.
    struct TodayDeskPanelSections: View {
        let store: IndexStore
        let plan: TodayDeskPlan
        let day: CalendarDate
        let goals: [GoalDefinition]
        let statuses: [String: GoalStatus]
        let onThisDay: OnThisDay?
        let closeDayLabel: String?
        let onCloseDay: () -> Void
        let onOpenGoal: (GoalDefinition) -> Void
        /// Blocks to draw, in order (``TodayDeskPlan/panelSections(isFolded:)``); each still hides
        /// when it has nothing to show.
        var sections: [TodayDeskPlan.PanelSection] = TodayDeskPlan.PanelSection.allCases
        /// When true, draws the "Bugün" header (right panel only).
        var showsHeader = true

        @Environment(\.locale) private var locale
        @Environment(\.calendar) private var calendar

        var body: some View {
            VStack(alignment: .leading, spacing: InkSpacing.section) {
                if showsHeader { header }
                ForEach(sections, id: \.self) { section in
                    self.section(section)
                }
            }
        }

        @ViewBuilder
        private func section(_ section: TodayDeskPlan.PanelSection) -> some View {
            switch section {
            case .nextEvent:
                if let event = plan.nextEvent {
                    nextEventCard(event)
                }
            case .nextTask:
                if let next = plan.nextTimedTask {
                    nextTaskCard(next.task, time: next.time)
                }
            case .goals:
                if !goals.isEmpty {
                    goalsSection
                }
            case .carriedOver:
                if !plan.carriedPreview.isEmpty {
                    carriedSection
                }
            case .onThisDay:
                if let onThisDay {
                    onThisDayCard(onThisDay)
                }
            case .closeDay:
                if let closeDayLabel {
                    closeDayButton(closeDayLabel)
                }
            }
        }

        private var header: some View {
            HStack(alignment: .firstTextBaseline) {
                Text("Bugün")
                    .font(.ink.dayName.weight(.semibold))
                    .foregroundStyle(Color.ink.text)
                Spacer(minLength: 8)
                Text(verbatim: weekdayCaption)
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
            }
        }

        private var weekdayCaption: String {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = locale
            formatter.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
            return formatter.string(from: LocalDay.instant(for: day))
        }

        private func nextEventCard(_ event: EventRow) -> some View {
            let time = event.time
            return HStack(alignment: .top, spacing: 10) {
                if let time {
                    Text(verbatim: EventTimeFormat.string(for: time, locale: locale))
                        .font(.system(.largeTitle, design: .default, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.ink.text)
                        .frame(minWidth: 72, alignment: .leading)
                }
                Rectangle()
                    .fill(TimelineEventColor.color(for: event, store: store))
                    .frame(width: InkSize.timelineBar)
                    .clipShape(Capsule())
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sıradaki olay")
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                    Text(verbatim: event.text.plainText)
                        .font(.ink.content)
                        .foregroundStyle(Color.ink.text)
                        .lineLimit(3)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: InkCorner.card, style: .continuous)
                    .fill(Color.ink.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: InkCorner.card, style: .continuous)
                            .stroke(Color.ink.rule, lineWidth: 1))
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                Text(
                    verbatim: [
                        PresentationLocalization.string(localized: "Sıradaki olay", locale: locale),
                        time.map { EventTimeFormat.string(for: $0, locale: locale) },
                        event.text.plainText,
                    ].compactMap { $0 }.joined(separator: ", ")))
        }

        private func nextTaskCard(_ task: TaskRow, time: EventTime) -> some View {
            HStack(alignment: .top, spacing: 10) {
                Text(verbatim: EventTimeFormat.string(for: time, locale: locale))
                    .font(.system(.title2, design: .default, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.ink.text)
                    .frame(minWidth: 72, alignment: .leading)
                Rectangle()
                    .fill(ProjectColor.color(for: task.project))
                    .frame(width: InkSize.timelineBar)
                    .clipShape(Capsule())
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sonraki görev")
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                    Text(
                        verbatim: DaySchedulePresentation.strippingLeadingTime(
                            from: task.text.plainText)
                    )
                    .font(.ink.content)
                    .foregroundStyle(Color.ink.text)
                    .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: InkCorner.card, style: .continuous)
                    .fill(Color.ink.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: InkCorner.card, style: .continuous)
                            .stroke(Color.ink.rule, lineWidth: 1))
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                Text(
                    verbatim: [
                        PresentationLocalization.string(localized: "Sonraki görev", locale: locale),
                        EventTimeFormat.string(for: time, locale: locale),
                        DaySchedulePresentation.strippingLeadingTime(from: task.text.plainText),
                    ].joined(separator: ", ")))
        }

        private var goalsSection: some View {
            let done = goals.filter { statuses[$0.id]?.progress.isComplete == true }.count
            return VStack(alignment: .leading, spacing: InkSpacing.row) {
                SectionHeader(
                    title: PresentationLocalization.string(localized: "Hedefler", locale: locale),
                    counter: "\(done)/\(goals.count)")
                InkCard(padded: false) {
                    ForEach(Array(goals.enumerated()), id: \.element.id) { index, goal in
                        if index > 0 { InkCardDivider() }
                        Button {
                            onOpenGoal(goal)
                        } label: {
                            HStack(spacing: 10) {
                                GoalRing(
                                    progress: statuses[goal.id]?.progress.fraction ?? 0,
                                    diameter: 24)
                                Text(verbatim: goal.name)
                                    .font(.ink.content)
                                    .foregroundStyle(Color.ink.text)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                if let status = statuses[goal.id],
                                    let value = GoalRowPresentation.valueText(
                                        goal: goal, status: status, locale: locale)
                                {
                                    Text(verbatim: value)
                                        .font(.ink.meta)
                                        .foregroundStyle(Color.ink.secondaryText)
                                }
                            }
                            .padding(.horizontal, InkSpacing.cardPadding)
                            .padding(.vertical, 10)
                            .frame(minHeight: TapTarget.minimumLength)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }

        private var carriedSection: some View {
            VStack(alignment: .leading, spacing: InkSpacing.row) {
                SectionHeader(
                    title: PresentationLocalization.string(
                        localized: "Devreden görevler", locale: locale),
                    count: plan.carriedPreview.count + plan.hiddenCarriedCount)
                InkCard(padded: false) {
                    ForEach(Array(plan.carriedPreview.enumerated()), id: \.element.id) {
                        index, task in
                        if index > 0 { InkCardDivider() }
                        HStack(alignment: .top, spacing: 10) {
                            TaskBox(
                                state: TaskBoxState(status: .todo, priority: task.priority),
                                isDecorative: true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: task.text.plainText)
                                    .font(.ink.content)
                                    .foregroundStyle(Color.ink.text)
                                    .lineLimit(2)
                                if let due = task.due {
                                    Label {
                                        Text(
                                            verbatim: TodayPresentation.carriedOverDate(
                                                due, today: day, locale: locale, calendar: calendar))
                                    } icon: {
                                        Image(systemName: "arrow.uturn.backward")
                                    }
                                    .font(.ink.meta)
                                    .foregroundStyle(Color.ink.warning)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, InkSpacing.cardPadding)
                        .padding(.vertical, 10)
                    }
                }
                if plan.hiddenCarriedCount > 0 {
                    Text(
                        verbatim: String(
                            localized: "\(plan.hiddenCarriedCount) devreden daha",
                            bundle: PresentationLocalization.bundle(locale), locale: locale)
                    )
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .padding(.horizontal, 4)
                }
            }
        }

        private func onThisDayCard(_ entry: OnThisDay) -> some View {
            let presentation = OnThisDayPresentation(entry: entry, today: day, locale: locale)
            return HStack(alignment: .center, spacing: 12) {
                Text(verbatim: presentation.year)
                    .font(.ink.dayName.weight(.semibold))
                    .foregroundStyle(Color.ink.secondaryText)
                    .frame(width: 48, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bu gün geçmişte")
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                    Text(verbatim: presentation.names)
                        .font(.ink.content)
                        .foregroundStyle(Color.ink.text)
                        .lineLimit(2)
                    Text(verbatim: presentation.caption)
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: InkCorner.card, style: .continuous)
                    .fill(Color.ink.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: InkCorner.card, style: .continuous)
                            .stroke(Color.ink.rule, lineWidth: 1))
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(verbatim: presentation.spoken))
        }

        private func closeDayButton(_ label: String) -> some View {
            Button(action: onCloseDay) {
                Label {
                    Text(verbatim: label)
                } icon: {
                    Image(systemName: "moon.fill")
                }
                .font(.ink.byline.weight(.semibold))
                .foregroundStyle(Color.ink.onAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Capsule().fill(Color.ink.accent))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("button.closeDay")
            .padding(.top, 8)
        }
    }

    /// Mac Today right panel (300 pt).
    struct TodayDeskPanel: View {
        let sections: TodayDeskPanelSections

        var body: some View {
            ScrollView {
                sections
                    .padding(InkSpacing.margin)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: ShellStyle.todayPanelWidth)
            .background(Color.ink.paper)
            .overlay(alignment: .leading) {
                Rectangle().fill(Color.ink.rule).frame(width: 1)
            }
            .accessibilityIdentifier("panel.todayDesk")
        }
    }
#endif
