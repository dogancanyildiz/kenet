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
            GoalRowDefinitionEditor(store: store, goal: goal.goal, selection: selection)
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

    private var dailyGoals: [GoalDefinition] {
        orderedGoals.filter { $0.period == .day && $0.kind != .milestone }
    }

    private var masthead: InkPageTitleRow<some View> {
        InkPageTitleRow("Hedefler") {
            InkHeaderAction("Yeni hedef", systemImage: "plus", role: .primary) {
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
                if !dailyGoals.isEmpty {
                    dailyRingsRow(answer: answer)
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
        let card = { (onOpen: (() -> Void)?) in
            GoalListCard(
                goal: goal, status: status, day: model.day, logs: model.logs[goal.key] ?? [],
                canEdit: model.canEdit, locale: locale,
                onOpen: onOpen,
                onIncrement: { Task { await incrementOrToggle(goal) } },
                onUnmark: { Task { await model.toggle(goal) } }
            )
            .contextMenu {
                DefinitionMenuButtons(
                    items: DefinitionMenu.items(
                        forGoal: goal.kind, markedToday: model.isMarkedToday(goal)),
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

        if let selection {
            card { selection.wrappedValue = goal.id }
        } else if goal.kind == .milestone {
            card {
                Task { await model.toggle(goal) }
            }
        } else {
            NavigationLink {
                GoalDetailView(store: store, goal: goal, day: model.day)
            } label: {
                card(nil)
            }
            .buttonStyle(.plain)
        }
    }

    private func dailyRingsRow(answer: GoalListStatuses) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: InkSpacing.row) {
                ForEach(dailyGoals, id: \.id) { goal in
                    let status = model.shownStatus(for: goal, answer: answer.statuses[goal.id])
                    let ring = GoalDailyRingLabel(goal: goal, status: status)
                    if let selection {
                        Button { selection.wrappedValue = goal.id } label: { ring }
                            .buttonStyle(.plain)
                    } else {
                        NavigationLink {
                            GoalDetailView(store: store, goal: goal, day: model.day)
                        } label: {
                            ring
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 4)
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

/// One daily goal in the horizontal rings row under the masthead.
private struct GoalDailyRingLabel: View {
    let goal: GoalDefinition
    let status: GoalStatus

    var body: some View {
        let progress = GoalRowPresentation.progress(goal: goal, status: status)
        let complete = progress >= 1
        let center =
            complete
            ? "✓"
            : GoalListPresentation.percentLabel(done: status.progress.done, target: goal.target)
        VStack(spacing: 6) {
            GoalRing(
                progress: progress,
                isBoolean: GoalStripPresentation.isBooleanRing(goal: goal),
                diameter: InkSize.dayRing,
                centerLabel: center
            )
            Text(verbatim: goal.name)
                .font(.ink.content)
                .foregroundStyle(complete ? Color.ink.secondaryText : Color.ink.text)
                .lineLimit(1)
            Text(verbatim: valueLine(complete: complete))
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
                .lineLimit(1)
        }
        .frame(minWidth: 72)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: goal.name))
        .accessibilityValue(
            Text(
                verbatim: GoalListPresentation.percentLabel(
                    done: status.progress.done, target: goal.target)))
    }

    private func valueLine(complete: Bool) -> String {
        let base = GoalRowPresentation.valueText(goal: goal, status: status) ?? ""
        return complete ? "✓ \(base)" : base
    }
}

/// Card row for one goal on the Goals list.
private struct GoalListCard: View {
    let goal: GoalDefinition
    let status: GoalStatus
    let day: CalendarDate
    let logs: [GoalLog]
    let canEdit: Bool
    let locale: Locale
    /// Nil when a parent ``NavigationLink`` owns the open gesture.
    var onOpen: (() -> Void)?
    let onIncrement: () -> Void
    let onUnmark: () -> Void

    private var progress: Double { GoalRowPresentation.progress(goal: goal, status: status) }
    private var complete: Bool { progress >= 1 }
    private var isBooleanMark: Bool { goal.kind == .boolean || goal.kind == .milestone }
    private var marked: Bool { isBooleanMark && complete }

    var body: some View {
        InkCard(padded: true) {
            HStack(alignment: .top, spacing: 12) {
                Group {
                    if let onOpen {
                        Button(action: onOpen) {
                            cardBody
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        cardBody
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .accessibilityLabel(Text(verbatim: goal.name))
                .accessibilityValue(Text(verbatim: accessibilityValue))
                .accessibilityHint(Text("Ayrıntıları göster"))

                trailingControl
            }
        }
        .opacity(complete ? 0.72 : 1)
    }

    private var cardBody: some View {
        HStack(alignment: .top, spacing: 12) {
            GoalRing(
                progress: progress,
                isBoolean: GoalStripPresentation.isBooleanRing(goal: goal),
                centerLabel: complete ? "✓" : nil
            )
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: goal.name)
                        .font(.ink.content)
                        .foregroundStyle(complete ? Color.ink.secondaryText : Color.ink.text)
                    TagChip(title: GoalListPresentation.periodChip(goal.period, locale: locale))
                }
                if let value = GoalRowPresentation.valueText(goal: goal, status: status) {
                    Text(verbatim: value)
                        .font(.ink.value)
                        .foregroundStyle(Color.ink.secondaryText)
                } else if goal.kind == .milestone {
                    Text(verbatim: GoalRowPresentation.meta(goal: goal, status: status) ?? "")
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                }
                meter
                if goal.kind != .milestone, goal.period == .day {
                    streakLine
                } else if goal.period == .week, goal.kind != .milestone {
                    Text(verbatim: weekProgress)
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                }
            }
        }
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
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: GoalListPresentation.streakText(status.streak, locale: locale))
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                if let badge = GoalRowPresentation.graceBadge(
                    goal: goal, status: status, locale: locale)
                {
                    badge
                }
            }
            if let score = status.score {
                Text(verbatim: GoalScoreCopy.sentence(score, locale: locale))
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
            }
        }
    }

    private var weekProgress: String {
        let amount =
            status.progress.done.formatted(.number.locale(locale)) + "/"
            + goal.target.formatted(.number.locale(locale))
        return String(localized: "bu hafta \(amount)", locale: locale)
    }

    private var accessibilityValue: String {
        [
            GoalRowPresentation.valueText(goal: goal, status: status),
            GoalListPresentation.streakText(status.streak, locale: locale),
        ]
        .compactMap { $0 }.joined(separator: ", ")
    }

    @ViewBuilder private var trailingControl: some View {
        if goal.kind == .milestone {
            Color.clear.frame(width: InkSize.plus, height: InkSize.plus)
        } else if marked {
            Button(action: onUnmark) {
                GoalRing(progress: 1, isBoolean: true, centerLabel: "✓")
                    .frame(width: InkSize.plus, height: InkSize.plus)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .disabled(!canEdit)
            .accessibilityLabel(Text("İşareti kaldır"))
        } else {
            Button(action: onIncrement) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.ink.accent)
                    .frame(width: InkSize.plus, height: InkSize.plus)
                    .background {
                        ZStack {
                            Circle().fill(Color.ink.control)
                            Circle().inset(by: InkStroke.control).fill(Color.ink.paper)
                        }
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .opacity(canEdit ? 1 : InkGoalRowTrailing.busyPlusOpacity)
            }
            .buttonStyle(.plain)
            .disabled(!canEdit)
            .accessibilityLabel(Text("Artır"))
        }
    }
}

/// Clears the split column's selection after a successful delete from the definition sheet.
private struct GoalRowDefinitionEditor: View {
    let store: IndexStore
    let goal: GoalDefinition
    let selection: Binding<String?>?
    @State private var deletion = DefinitionDeletionModel()

    var body: some View {
        NavigationStack { GoalDefinitionForm(store: store, goal: goal, deletion: deletion) }
            .onChange(of: deletion.isDeleted) { _, deleted in
                if deleted, selection?.wrappedValue == goal.id { selection?.wrappedValue = nil }
            }
    }
}
