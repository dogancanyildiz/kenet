import GoalTracking
import SwiftUI
import VaultFormat

/// The short evening pass over what is still open today: tasks, then daily goals, then one sentence.
///
/// Nothing here is a draft to save, and each step writes on its own (a marked goal at once,
/// tasks on "Uygula"), so the bar holds "Kapat" alone: "Vazgeç" would promise to take those
/// writes back. Closing without a choice writes nothing; the flow leaves no mark of its own.
/// The flow closes the day it was opened on, also when midnight passes while it is open.
/// Use inside the sheet's `NavigationStack`.
struct CloseDayView: View {
    @State private var model: CloseDayModel
    @State private var editing: GoalValueModel?
    @FocusState private var sentenceFocused: Bool
    @Environment(GeofenceService.self) private var geofences: GeofenceService?
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss

    /// - Parameter tasks: the day's rows as Today drew them (``DayTasksModel/rows``).
    init(store: IndexStore, today: CalendarDate, tasks: [TaskRow], step: CloseDayStep = .tasks) {
        _model = State(initialValue: CloseDayModel(store: store, today: today, tasks: tasks, step: step))
    }

    private var bundle: Bundle { PresentationLocalization.bundle(locale) }

    private var stepText: String {
        String(
            localized: "Adım \(model.stepNumber)/\(model.stepCount)", bundle: bundle, locale: locale)
    }

    var body: some View {
        InkSheetScaffold(
            "Günü kapat", byline: stepText, closeIdentifier: "button.closeDay.close",
            // The report of a write in flight is still to come: the sheet stays until it shows.
            onClose: { if model.canClose { dismiss() } }
        ) {
            VStack(alignment: .leading, spacing: InkSpacing.row) {
                switch model.step {
                case .tasks: tasksStep
                case .goals: goalsStep
                case .journal: journalStep
                }
            }
        }
        .disabled(!model.canClose)
        .interactiveDismissDisabled(!model.canClose)
        .preference(key: GoalsStripReadyKey.self, value: model.goals.hasLoaded && !model.goals.isLoading)
        .task(id: model.store.lastUpdated) { await model.goals.load() }
        .task(id: model.store.lastUpdated) { await model.loadTasks() }
        .sheet(item: $editing) { editor in
            NavigationStack { GoalValueEditor(model: editor) }
                .onChange(of: editor.isSaved) { _, saved in
                    if saved { geofences?.clearLockedMarkNotice() }
                }
        }
        // The page changes under the same title: VoiceOver starts over and reads the new step.
        .onChange(of: model.step) { AccessibilityNotification.ScreenChanged().post() }
        // "Yaz" keeps the focus and the field empties: the outcome is read out.
        .onChange(of: model.journalNotice ?? model.journalError) { _, text in
            if let text { AccessibilityNotification.Announcement(text).post() }
        }
        .accessibilityIdentifier("screen.closeDay")
    }

    // MARK: - Tasks

    @ViewBuilder private var tasksStep: some View {
        let tasks = model.tasks
        SectionHeader(title: String(localized: "Görevler", bundle: bundle, locale: locale), count: tasks.count)
        if let report = model.report, let text = report.text(locale: locale) {
            InfoBand(kind: report.isPartial ? .warning : .info, verbatim: text)
        }
        if let failure = model.report?.failureText {
            InfoBand(kind: .error, verbatim: failure)
        }
        if tasks.isEmpty {
            EmptyState("Bugün için açık görev yok.")
        } else {
            hint("Seçim yapmadığın görev olduğu gibi kalır.")
            ForEach(tasks) { row in
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: row.text.plainText)
                        .font(.ink.content)
                        .foregroundStyle(Color.ink.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityHidden(true)
                    InkLabeledMenu(
                        "Karar",
                        selection: Binding(
                            get: { model.choice(for: row) }, set: { model.choose($0, for: row) }),
                        options: [
                            InkMenuOption("Kalsın", value: CloseDayChoice.keep),
                            InkMenuOption("Bitti", value: CloseDayChoice.done),
                            InkMenuOption("Yarına", value: CloseDayChoice.tomorrow),
                            InkMenuOption("Haftaya", value: CloseDayChoice.nextWeek),
                        ]
                    )
                    // One element per task: its text is the menu's name, the choice its value.
                    // The shared label ("Karar") alone would read the same on every row.
                    .accessibilityLabel(Text(verbatim: row.text.plainText))
                }
            }
        }
        HStack(spacing: InkSpacing.section) {
            if !tasks.isEmpty {
                // The action lives in the page, not in the bar: it is not a save.
                Button("Uygula") { Task { await model.apply() } }
                    .buttonStyle(InkPrimaryButtonStyle())
                    .disabled(!model.canApply)
                    .accessibilityIdentifier("button.closeDay.apply")
            }
            Button(tasks.isEmpty || model.report != nil ? "İleri" : "Atla") { model.advance() }
                .buttonStyle(InkTextButtonStyle())
                .accessibilityIdentifier("button.closeDay.next")
        }
    }

    // MARK: - Goals

    @ViewBuilder private var goalsStep: some View {
        let pending = model.pendingGoals
        SectionHeader(
            title: String(localized: "Hedefler", bundle: bundle, locale: locale),
            counter: "\(pending.filter { model.goals.isComplete(for: $0) }.count)/\(pending.count)",
            isLoading: model.goals.isLoading)
        if pending.isEmpty {
            EmptyState("Bugün için işaretlenmemiş hedef yok.")
        } else {
            hint("İşaretlediğin hedef hemen kaydedilir.")
            ForEach(pending, id: \.id) { goal in
                goalRow(goal)
            }
        }
        if let error = model.goals.errorText {
            InfoBand(kind: .error, verbatim: error)
        }
        stepButtons
    }

    // MARK: - Journal

    @ViewBuilder private var journalStep: some View {
        @Bindable var model = model
        SectionHeader(title: String(localized: "Günlük", bundle: bundle, locale: locale))
        hint("Bugünden tek bir cümle yeter.")
        TextField(
            "Bugünden bir cümle", text: $model.sentence,
            prompt: Text("Bugünden bir cümle").font(.ink.placeholder), axis: .vertical
        )
        .textFieldStyle(.plain)
        .font(.ink.content)
        .foregroundStyle(Color.ink.text)
        .lineLimit(1...6)
        .focused($sentenceFocused)
        .accessibilityIdentifier("field.closeDay.sentence")
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Color.ink.well,
            in: RoundedRectangle(cornerRadius: InkSize.kanbanCorner, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: InkSize.kanbanCorner, style: .continuous)
                .strokeBorder(
                    InkButtonChrome.color(
                        for: InkFilterFieldChrome.borderToken(isFocused: sentenceFocused)),
                    lineWidth: InkStroke.control)
        )
        if let notice = model.journalNotice {
            InfoBand(kind: .info, verbatim: notice)
        }
        if let error = model.journalError {
            InfoBand(kind: .error, verbatim: error)
        }
        HStack(spacing: InkSpacing.section) {
            if model.canGoBack { backButton }
            Button("Yaz") { Task { await model.writeSentence() } }
                .buttonStyle(InkPrimaryButtonStyle())
                .disabled(!model.canWriteSentence)
                .accessibilityIdentifier("button.closeDay.write")
        }
    }

    @ViewBuilder private var stepButtons: some View {
        HStack(spacing: InkSpacing.section) {
            if model.canGoBack { backButton }
            if model.canAdvance {
                Button("İleri") { model.advance() }
                    .buttonStyle(InkTextButtonStyle())
                    .accessibilityIdentifier("button.closeDay.next")
            }
        }
    }

    private var backButton: some View {
        Button("Geri") { model.back() }
            .buttonStyle(InkTextButtonStyle())
            .accessibilityIdentifier("button.closeDay.back")
    }

    /// The Today strip's row with the same actions and the same write path (``GoalDayModel``).
    @ViewBuilder private func goalRow(_ goal: GoalDefinition) -> some View {
        let goals = model.goals
        let marked = goals.isComplete(for: goal)
        let isBooleanMark = goal.kind == .boolean || goal.kind == .milestone
        InkGoalRow(
            name: goal.name,
            progress: GoalStripPresentation.progressValue(status: goals.status(for: goal)),
            isBoolean: GoalStripPresentation.isBooleanRing(goal: goal),
            valueText: valueText(for: goal),
            onIncrement: goals.canEdit && !(isBooleanMark && marked)
                ? {
                    Task {
                        if isBooleanMark { await toggle(goal) } else { await increment(goal) }
                    }
                } : nil,
            onValueTap: goals.canEdit && goal.kind == .number
                ? { editing = GoalValueModel(dayModel: goals, goal: goal) } : nil,
            onMarkTap: goals.canEdit && isBooleanMark && marked
                ? { Task { await toggle(goal) } } : nil,
            showsPlus: !(isBooleanMark && marked),
            incrementLabel: LocalizedStringKey(isBooleanMark && marked ? "İşareti kaldır" : "Artır")
        )
        .disabled(!goals.canEdit)
    }

    private func valueText(for goal: GoalDefinition) -> String? {
        guard goal.kind == .number else { return nil }
        let amount: Double = if case .number(let number) = model.goals.value(for: goal) { number } else { 0 }
        let unit = goal.unit.map { " \($0)" } ?? ""
        return "\(amount.formatted(.number.locale(locale))) / \(goal.target.formatted(.number.locale(locale)))\(unit)"
    }

    // As on Today: a mark made by hand answers the geofence notice about a locked mark.
    private func toggle(_ goal: GoalDefinition) async {
        if await model.goals.toggle(goal) { geofences?.clearLockedMarkNotice() }
    }

    private func increment(_ goal: GoalDefinition) async {
        let current: Double = if case .number(let number) = model.goals.value(for: goal) { number } else { 0 }
        if await model.goals.set(goal, value: .number(current + 1)) { geofences?.clearLockedMarkNotice() }
    }

    private func hint(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.ink.meta)
            .foregroundStyle(Color.ink.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, InkSpacing.row)
    }
}
