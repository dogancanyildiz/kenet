import GoalTracking
import SwiftUI
import VaultFormat

/// The goals and statuses the list last queried, statuses by goal file. Kept across the midnight
/// rebuild of the list, so the rows stay until the new day's answer comes; another vault's answer
/// is not used.
struct GoalListStatuses {
    let vault: URL?
    let goals: [GoalDefinition]
    let statuses: [String: GoalStatus]
}

/// Reloads the list's statuses when its day or the published index changes.
struct GoalListRequest: Hashable {
    let day: CalendarDate
    let updated: Date?
}

struct GoalDefinitionSheetTarget: Identifiable {
    let goal: GoalDefinition
    var id: String { goal.id }
}

struct GoalsView: View {
    let store: IndexStore
    var selection: Binding<String?>? = nil
    @State private var showsCreation = false
    @State private var editingGoal: GoalDefinitionSheetTarget?
    @State private var editingAmount: GoalValueModel?
    @State private var loaded: GoalListStatuses?
    @Environment(\.clockNow) private var clockNow
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            let day = LocalDay.today(at: clockNow())
            GoalListContent(
                store: store, day: day, selection: selection,
                showsCreation: $showsCreation, loaded: $loaded,
                editingGoal: $editingGoal, editingAmount: $editingAmount
            )
            .id(day.description + (store.vaultURL?.path ?? ""))
        }
        .inkRootPageNavigationTitle("Hedefler")
        .sheet(item: $editingGoal) { goal in
            NavigationStack { GoalDefinitionForm(store: store, goal: goal.goal) }
        }
        .sheet(item: $editingAmount) { editor in
            NavigationStack { GoalValueEditor(model: editor) }
                .inkAdaptiveSheetPresentation(fitsContent: true, usesPhoneDetents: false)
        }
        .sheet(isPresented: $showsCreation) {
            NavigationStack { GoalCreationView(store: store) }
        }
    }
}

private struct GoalListContent: View {
    let store: IndexStore
    let selection: Binding<String?>?
    @Binding var showsCreation: Bool
    @Binding var loaded: GoalListStatuses?
    @Binding var editingGoal: GoalDefinitionSheetTarget?
    @Binding var editingAmount: GoalValueModel?
    @State private var deletion = DefinitionDeletionModel()
    @State private var deletingGoal: GoalDefinition?
    @State private var model: GoalDayModel
    @Environment(\.locale) private var locale

    init(
        store: IndexStore, day: CalendarDate, selection: Binding<String?>?,
        showsCreation: Binding<Bool>, loaded: Binding<GoalListStatuses?>,
        editingGoal: Binding<GoalDefinitionSheetTarget?>, editingAmount: Binding<GoalValueModel?>
    ) {
        self.store = store
        self.selection = selection
        _showsCreation = showsCreation
        _loaded = loaded
        _editingGoal = editingGoal
        _editingAmount = editingAmount
        _model = State(initialValue: GoalDayModel(store: store, day: day))
    }

    private var answer: GoalListStatuses? {
        guard let loaded, loaded.vault == store.vaultURL else { return nil }
        return loaded
    }

    private var orderedGoals: [GoalDefinition] {
        guard let answer else { return [] }
        return GoalListPresentation.ordered(answer.goals) { goal in
            model.shownStatus(for: goal, answer: answer.statuses[goal.id])
        }
    }

    /// The summary card's rings: daily and weekly goals (the drawing's Kitap, Su and Spor).
    private var ringGoals: [GoalDefinition] {
        orderedGoals.filter { $0.period != .year && $0.kind != .milestone }
    }

    /// "Bugün 1/3 tamam" under the title: today's goals done out of all ringed goals.
    private var todayLine: String? {
        guard let answer, !ringGoals.isEmpty else { return nil }
        let done = ringGoals.filter {
            model.shownStatus(for: $0, answer: answer.statuses[$0.id]).progress.isComplete
        }.count
        return String(localized: "Bugün \(done)/\(ringGoals.count) tamam", locale: locale)
    }

    private var masthead: InkPageTitleRow<some View> {
        InkPageTitleRow("Hedefler", byline: todayLine) {
            InkHeaderAction("Yeni hedef", systemImage: "plus") {
                showsCreation = true
            }
            .disabled(!store.canAddEvent)
            SearchButton()
        }
    }

    var body: some View {
        List {
            InkScrolledMasthead(masthead)
            if let answer {
                if !ringGoals.isEmpty {
                    summaryCard(answer: answer)
                        .inkListRow()
                }
                if !orderedGoals.isEmpty {
                    SectionHeader("Tüm hedefler", count: orderedGoals.count)
                        .padding(.top, 8)
                        .inkListRow()
                }
                ForEach(orderedGoals, id: \.id) { goal in
                    let status = model.shownStatus(for: goal, answer: answer.statuses[goal.id])
                    row(goal: goal, status: status)
                }
            }
            if let error = deletion.errorText {
                InfoBand(kind: .error, verbatim: error)
                    .inkListRow()
            }
            if let error = model.errorText {
                InfoBand(kind: .error, verbatim: error)
                    .inkListRow()
            }
        }
        .listStyle(.plain)
        .inkPage()
        .inkPageScrollColumn()
        .inkPinnedMasthead(masthead)
        .inkGlow()
        .overlay {
            if answer?.goals.isEmpty == true {
                EmptyState(
                    "Henüz hedef yok",
                    actionTitle: store.canAddEvent ? "Yeni hedef" : nil
                ) { showsCreation = true }
            }
        }
        .destructiveConfirmationDialog(
            "Hedefi sil", confirmation: $deletion.confirmation,
            confirmTitle: "Hedefi sil",
            message: "\(deletingGoal?.name ?? "") silinsin mi? Gün kayıtları kalır."
        ) { path in
            Task {
                if await deletion.delete(store: store, path: path, goal: true),
                    selection?.wrappedValue == path
                {
                    selection?.wrappedValue = nil
                }
            }
        }
        .task(id: store.lastUpdated) { await model.load() }
        .task(id: GoalListRequest(day: model.day, updated: store.lastUpdated)) {
            let vault = store.vaultURL
            let revision = model.currentRevision()
            guard let rows = try? await store.computeGoalStatuses(today: model.day), !Task.isCancelled
            else { return }
            let statuses = rows.map { ($0.definition.id, $0.status) }
            loaded = GoalListStatuses(
                vault: vault, goals: rows.map(\.definition),
                statuses: Dictionary(statuses, uniquingKeysWith: { first, _ in first }))
            if vault == store.vaultURL { model.answerShown(askedAt: revision) }
        }
    }

    @ViewBuilder
    private func row(goal: GoalDefinition, status: GoalStatus) -> some View {
        let markedToday = model.isMarkedToday(goal)
        let markReadOnly =
            goal.kind == .milestone
            && status.completionDate != nil
            && status.completionDate != model.day
        GoalListCard(
            goal: goal,
            status: status,
            day: model.day,
            logs: model.logs[goal.key] ?? [],
            canEdit: model.canEdit,
            markedToday: markedToday,
            markReadOnly: markReadOnly,
            locale: locale,
            onOpen: openAction(goal: goal, status: status),
            opensDetail: goal.kind != .milestone && selection == nil,
            detail: { GoalDetailView(store: store, goal: goal, day: model.day) },
            onIncrement: { Task { await incrementOrToggle(goal) } },
            onUnmark: { Task { await model.toggle(goal) } }
        )
        .contextMenu {
            // A read-only mark (yesterday already completed) hides only the mark items;
            // Düzenle and Sil stay available.
            DefinitionMenuButtons(
                items: DefinitionMenu.items(forGoal: goal.kind, markedToday: markedToday)
                    .filter { !markReadOnly || ($0 != .markToday && $0 != .unmark) },
                canEdit: model.canEdit
            ) { item in
                switch item {
                case .markToday, .unmark:
                    Task { await model.toggle(goal) }
                case .enterAmount:
                    editingAmount = GoalValueModel(dayModel: model, goal: goal)
                case .edit:
                    editingGoal = GoalDefinitionSheetTarget(goal: goal)
                case .delete:
                    deletingGoal = goal
                    deletion = DefinitionDeletionModel()
                    deletion.request(path: goal.id)
                case .copyLink: break
                }
            }
        }
        .inkListRow(columnSelected: selection?.wrappedValue == goal.id)
    }

    /// Milestone first (mark), then Mac selection, else nil so the card uses ``NavigationLink``.
    private func openAction(goal: GoalDefinition, status: GoalStatus) -> (() -> Void)? {
        if goal.kind == .milestone {
            let readOnly =
                status.completionDate != nil && status.completionDate != model.day
            return {
                guard !readOnly else { return }
                Task { await model.toggle(goal) }
            }
        }
        if let selection {
            return { selection.wrappedValue = goal.id }
        }
        return nil
    }

    /// The summary card: one large ring per daily and weekly goal, side by side.
    private func summaryCard(answer: GoalListStatuses) -> some View {
        InkCard(padded: true) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(ringGoals, id: \.id) { goal in
                        summaryRing(goal: goal, answer: answer)
                            .frame(maxWidth: .infinity)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(ringGoals, id: \.id) { goal in
                            summaryRing(goal: goal, answer: answer)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func summaryRing(goal: GoalDefinition, answer: GoalListStatuses) -> some View {
        let status = model.shownStatus(for: goal, answer: answer.statuses[goal.id])
        let ring = GoalSummaryRingLabel(goal: goal, status: status, locale: locale)
        if let selection {
            Button {
                selection.wrappedValue = goal.id
            } label: {
                ring
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                GoalDetailView(store: store, goal: goal, day: model.day)
            } label: {
                ring
            }
            .buttonStyle(.plain)
            .navigationLinkIndicatorVisibility(.hidden)
        }
    }

    private func incrementOrToggle(_ goal: GoalDefinition) async {
        if goal.kind == .boolean || goal.kind == .milestone {
            _ = await model.toggle(goal)
        } else {
            let current: Double =
                if case .number(let number) = model.value(for: goal) { number } else { 0 }
            _ = await model.set(goal, value: .number(current + 1))
        }
    }
}

/// One goal in the summary card: a large progress ring with the percent, the name and the value.
private struct GoalSummaryRingLabel: View {
    let goal: GoalDefinition
    let status: GoalStatus
    let locale: Locale
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 64

    var body: some View {
        let progress = GoalRowPresentation.progress(goal: goal, status: status)
        let complete = progress >= 1
        let percent = GoalListPresentation.percentLabel(
            done: status.progress.done, target: goal.target, locale: locale)
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.ink.well, lineWidth: side * 0.11)
                Circle()
                    .trim(from: 0, to: min(1, max(0, progress)))
                    .stroke(
                        Color.ink.accent,
                        style: StrokeStyle(lineWidth: side * 0.11, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text(verbatim: percent)
                    .font(.ink.meta.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.ink.text)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(side * 0.14)
            }
            .frame(width: side, height: side)
            .padding(.bottom, 4)
            Text(verbatim: goal.name)
                .font(.ink.meta.weight(.semibold))
                .foregroundStyle(Color.ink.text)
                .lineLimit(1)
            Text(verbatim: valueLine(complete: complete))
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(minWidth: 72)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: goal.name))
        .accessibilityValue(Text(verbatim: "\(percent), \(valueLine(complete: complete))"))
    }

    private func valueLine(complete: Bool) -> String {
        if goal.period == .week {
            let amount =
                status.progress.done.formatted(.number.locale(locale)) + "/"
                + goal.target.formatted(.number.locale(locale))
            return String(localized: "bu hafta \(amount)", locale: locale)
        }
        let base = GoalRowPresentation.valueText(goal: goal, status: status) ?? ""
        return complete ? "✓ \(base)" : base
    }
}

/// Card row for one goal on the Goals list.
private struct GoalListCard<Detail: View>: View {
    let goal: GoalDefinition
    let status: GoalStatus
    let day: CalendarDate
    let logs: [GoalLog]
    let canEdit: Bool
    /// Today's own mark (boolean / milestone), not period completion.
    let markedToday: Bool
    /// Milestone completed on another day: mark controls stay off.
    let markReadOnly: Bool
    let locale: Locale
    /// Non-nil for milestone mark and Mac selection; nil when ``opensDetail``.
    var onOpen: (() -> Void)?
    /// iPhone: ``NavigationLink`` wraps only the body; "+" stays a sibling.
    var opensDetail: Bool
    @ViewBuilder var detail: () -> Detail
    let onIncrement: () -> Void
    let onUnmark: () -> Void

    @ScaledMetric(relativeTo: .body) private var plusSide: CGFloat = 46

    private var progress: Double { GoalRowPresentation.progress(goal: goal, status: status) }
    private var complete: Bool { progress >= 1 }
    private var isBooleanMark: Bool { goal.kind == .boolean || goal.kind == .milestone }

    var body: some View {
        InkCard(padded: true) {
            HStack(alignment: .center, spacing: 12) {
                openSection
                trailingControl
            }
        }
    }

    @ViewBuilder private var openSection: some View {
        let body =
            cardBody
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        // Accessibility sits on the control itself so hosted presses activate mark / open.
        if opensDetail {
            NavigationLink {
                detail()
            } label: {
                body
            }
            .buttonStyle(.plain)
            // The drawing's row has no "›": the "+" is the only trailing mark.
            .navigationLinkIndicatorVisibility(.hidden)
            .accessibilityLabel(Text(verbatim: accessibilityLabelText))
            .accessibilityHint(Text(openHint))
        } else if let onOpen {
            Button(action: onOpen) { body }
                .buttonStyle(.plain)
                .disabled(goal.kind == .milestone && (!canEdit || markReadOnly))
                .accessibilityLabel(Text(verbatim: accessibilityLabelText))
                .accessibilityHint(Text(openHint))
        } else {
            body
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: accessibilityLabelText))
        }
    }

    private var openHint: LocalizedStringKey {
        if goal.kind == .milestone {
            return markedToday ? "İşareti kaldır" : "Bugünü işaretle"
        }
        return "Ayrıntıları göster"
    }

    /// One element: "ad, değer" (or meta for milestones), matching list query tests.
    private var accessibilityLabelText: String {
        let detail =
            GoalRowPresentation.valueText(goal: goal, status: status)
            ?? GoalRowPresentation.meta(goal: goal, status: status, locale: locale)
        let badge = GoalRowPresentation.graceBadge(goal: goal, status: status, locale: locale)?.label
        return [goal.name, detail, badge].compactMap { $0 }.filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if complete {
                    Image(systemName: "checkmark")
                        .font(.ink.meta.weight(.semibold))
                        .foregroundStyle(Color.ink.secondaryText)
                        .accessibilityHidden(true)
                }
                Text(verbatim: goal.name)
                    .font(.ink.content.weight(.semibold))
                    .foregroundStyle(complete ? Color.ink.secondaryText : Color.ink.text)
                TagChip(title: GoalListPresentation.periodChip(goal.period, locale: locale))
            }
            if goal.kind == .milestone {
                Text(verbatim: GoalRowPresentation.meta(goal: goal, status: status) ?? "")
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
            } else {
                Text(valueLine)
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .monospacedDigit()
            }
            meter
            if goal.kind != .milestone, goal.period == .day {
                streakLine
            }
        }
    }

    /// "**30/20** sayfa · Son 30 gün %87" (daily) or "**17/24** kitap · 7 kitap kaldı".
    private var valueLine: AttributedString {
        var amount = AttributedString(
            status.progress.done.formatted(.number.locale(locale)) + "/"
                + goal.target.formatted(.number.locale(locale)))
        amount.inlinePresentationIntent = .stronglyEmphasized
        amount.foregroundColor = complete ? Color.ink.secondaryText : Color.ink.text
        var line = amount
        if let unit = goal.unit, !unit.isEmpty { line += AttributedString(" " + unit) }
        let tail: String? =
            goal.period == .day
            ? status.score.map { GoalScoreCopy.sentence($0, locale: locale) }
            : GoalListPresentation.remainingText(goal: goal, status: status, locale: locale)
                ?? (goal.period == .week
                    ? String(localized: "Bu hafta", locale: locale) : nil)
        if let tail { line += AttributedString(" · " + tail) }
        return line
    }

    @ViewBuilder private var meter: some View {
        if goal.period == .day, goal.kind != .milestone {
            GoalTallyStrip(
                days: GoalListPresentation.tallyDays(
                    goal: goal, logs: logs, today: day, graceSpent: Set(status.graceSpentDays)))
        } else if goal.period == .year, goal.kind != .milestone {
            GoalYearMiniBars(
                bars: GoalListPresentation.yearMonthBars(goal: goal, logs: logs, today: day))
        }
    }

    private var streakLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Label {
                Text(verbatim: GoalListPresentation.streakText(status.streak, locale: locale))
            } icon: {
                Image(systemName: "link")
                    .foregroundStyle(Color.ink.accent)
            }
            .labelStyle(GoalStreakLabelStyle())
            .font(.ink.meta)
            .foregroundStyle(Color.ink.secondaryText)
            if let badge = GoalRowPresentation.graceBadge(
                goal: goal, status: status, locale: locale)
            {
                badge
            }
        }
    }

    @ViewBuilder private var trailingControl: some View {
        if isBooleanMark {
            if markedToday {
                Button(action: onUnmark) {
                    Image(systemName: "checkmark")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.ink.secondaryText)
                        .frame(width: plusSide, height: plusSide)
                        .background(Circle().fill(Color.ink.well))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .disabled(!canEdit || markReadOnly)
                .accessibilityLabel(Text("İşareti kaldır"))
            } else {
                Button(action: onIncrement) {
                    plusGlyph
                }
                .buttonStyle(.plain)
                .disabled(!canEdit || markReadOnly)
                .accessibilityLabel(Text(goal.kind == .milestone ? "Bugünü işaretle" : "Artır"))
            }
        } else {
            Button(action: onIncrement) {
                plusGlyph
            }
            .buttonStyle(.plain)
            .disabled(!canEdit)
            .accessibilityLabel(Text("Artır"))
        }
    }

    private var plusGlyph: some View {
        Image(systemName: "plus")
            .font(.title3.weight(.medium))
            .foregroundStyle(Color.ink.accent)
            .frame(width: plusSide, height: plusSide)
            .background {
                Circle().fill(Color.ink.well)
                Circle().strokeBorder(Color.ink.rule, lineWidth: 1)
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .opacity(canEdit && !markReadOnly ? 1 : InkGoalRowTrailing.busyPlusOpacity)
    }
}

/// Icon and title close together on one baseline ("🔗 Zincir 12 gün").
private struct GoalStreakLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            configuration.icon.accessibilityHidden(true)
            configuration.title
        }
    }
}
