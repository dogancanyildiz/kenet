import GoalTracking
import SwiftUI
import VaultFormat

struct GoalDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var deletion = DefinitionDeletionModel()
    let store: IndexStore
    private let original: GoalDefinition
    @State private var history: GoalDayModel
    @State private var editing: GoalValueModel?
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.locale) private var locale
    @State private var isEditing = false

    init(store: IndexStore, goal: GoalDefinition, day: CalendarDate = LocalDay.today()) {
        self.store = store
        original = goal
        _history = State(initialValue: GoalDayModel(store: store, day: day))
    }

    /// The goal's newest definition by id, as the history model last loaded it; the one the page
    /// was opened with until then, and once the file is gone.
    private var goal: GoalDefinition { history.goals.first { $0.id == original.id } ?? original }

    private var masthead: InkPageTitle<some View> {
        InkPageTitle(verbatim: goal.name, byline: nil) {
            SearchButton()
        }
    }

    var body: some View {
        let status = history.status(for: goal)
        ScrollView {
            VStack(alignment: .leading, spacing: InkSpacing.section) {
                InkScrolledMasthead(masthead)

                hero(status: status)
                    .padding(.horizontal, InkSpacing.margin)

                if goal.kind != .milestone {
                    actions(status: status)
                        .padding(.horizontal, InkSpacing.margin)
                }

                if goal.kind != .milestone, showsStats(status) {
                    statsStrip(status: status)
                        .padding(.horizontal, InkSpacing.margin)
                }

                if goal.period == .day, let balance = GraceDayPresentation.balance(status: status) {
                    graceDayLine(balance)
                        .padding(.horizontal, InkSpacing.margin)
                }

                if GoalValueChart.isShown(for: goal) {
                    InkCard(padded: true) {
                        SectionHeader(
                            title: GoalValueChart.title(
                                for: goal, isAccessibilitySize: typeSize.isAccessibilitySize))
                        GoalValueChart(
                            goal: goal, logs: history.logs[goal.key] ?? [], today: history.day)
                    }
                    .padding(.horizontal, InkSpacing.margin)
                } else if goal.kind == .boolean {
                    InkCard(padded: true) {
                        SectionHeader(title: String(localized: "Isı haritası"))
                        GoalHeatmap(
                            goal: goal, logs: history.logs[goal.key] ?? [], today: history.day,
                            graceSpentDays: Set(status.graceSpentDays)
                        ) { day in
                            Task { await edit(day) }
                        }
                        .disabled(!history.canEdit)
                    }
                    .padding(.horizontal, InkSpacing.margin)
                }

                if goal.kind == .number {
                    InkCard(padded: true) {
                        SectionHeader(title: String(localized: "Isı haritası"))
                        GoalHeatmap(
                            goal: goal, logs: history.logs[goal.key] ?? [], today: history.day,
                            graceSpentDays: Set(status.graceSpentDays)
                        ) { day in
                            Task { await edit(day) }
                        }
                        .disabled(!history.canEdit)
                    }
                    .padding(.horizontal, InkSpacing.margin)
                }

                recentLogs
                    .padding(.horizontal, InkSpacing.margin)

                footerActions
                    .padding(.horizontal, InkSpacing.margin)

                if let error = history.errorText {
                    InfoBand(kind: .error, verbatim: error)
                        .padding(.horizontal, InkSpacing.margin)
                }
                if let error = deletion.errorText {
                    InfoBand(kind: .error, verbatim: error)
                        .padding(.horizontal, InkSpacing.margin)
                }
                if history.isLoading {
                    InkProgress(kind: .indeterminate(label: "Yükleniyor…"))
                        .padding(.horizontal, InkSpacing.margin)
                }
            }
            .padding(.vertical, 12)
            .inkPageColumn()
        }
        .inkPinnedMasthead(masthead, insets: EdgeInsets(top: 12, leading: 0, bottom: 8, trailing: 0))
        .inkPage()
        .inkPageNavigationTitle(verbatim: goal.name)
        #if os(iOS)
            .toolbar(.hidden, for: .tabBar)
        #endif
        .task(id: store.lastUpdated) { await history.load() }
        .sheet(item: $editing, onDismiss: { Task { await history.load() } }) { model in
            NavigationStack { GoalValueEditor(model: model) }
                .inkAdaptiveSheetPresentation(fitsContent: true, usesPhoneDetents: false)
        }
        .sheet(isPresented: $isEditing) {
            NavigationStack { GoalDefinitionForm(store: store, goal: goal, deletion: deletion) }
        }
        .onChange(of: deletion.isDeleted) { _, deleted in
            if deleted { dismiss() }
        }
        .destructiveConfirmationDialog(
            "Hedefi sil", confirmation: $deletion.confirmation,
            confirmTitle: "Hedefi sil",
            message: "\(goal.name) silinsin mi? Gün kayıtları kalır."
        ) { path in
            Task {
                if await deletion.delete(store: store, path: path, goal: true) {
                    dismiss()
                }
            }
        }
    }

    private func hero(status: GoalStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: goal.name)
                    .font(.ink.display)
                    .foregroundStyle(Color.ink.text)
                    .accessibilityHidden(true)
                TagChip(title: GoalListPresentation.periodChip(goal.period, locale: locale))
            }

            if goal.kind == .milestone {
                GoalProgressLabel(goal: goal, status: status)
            } else {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            LargeNumberText(verbatim: status.progress.done.formatted())
                            Text(verbatim: "/ " + goal.target.formatted())
                                .font(.ink.value)
                                .foregroundStyle(Color.ink.secondaryText)
                            if let unit = goal.unit {
                                Text(verbatim: unit)
                                    .font(.ink.meta)
                                    .foregroundStyle(Color.ink.secondaryText)
                            }
                        }
                        if let remaining = GoalListPresentation.remainingText(
                            goal: goal, status: status, locale: locale)
                        {
                            Text(verbatim: remaining)
                                .font(.ink.meta)
                                .foregroundStyle(Color.ink.secondaryText)
                        }
                    }
                    Spacer(minLength: 0)
                    GoalRing(
                        progress: status.progress.fraction,
                        isBoolean: GoalStripPresentation.isBooleanRing(goal: goal),
                        diameter: 64,
                        centerLabel: status.progress.isComplete
                            ? "✓"
                            : GoalListPresentation.percentLabel(
                                done: status.progress.done, target: goal.target)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func actions(status: GoalStatus) -> some View {
        let isBoolean = goal.kind == .boolean
        let marked = isBoolean && history.isMarkedToday(goal)
        if goal.kind == .number {
            HStack(spacing: 12) {
                Button("Miktar gir") {
                    editing = GoalValueModel(dayModel: history, goal: goal)
                }
                .buttonStyle(InkSecondaryButtonStyle())
                .disabled(!history.canEdit)
                .frame(maxWidth: .infinity)

                Button {
                    Task { await increment() }
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.ink.onAccent)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.ink.accent))
                }
                .buttonStyle(.plain)
                .disabled(!history.canEdit)
                .accessibilityLabel(Text("Artır"))
            }
        } else {
            Button(marked ? "İşareti kaldır" : "Bugünü işaretle") {
                Task { await history.toggle(goal) }
            }
            .buttonStyle(InkSecondaryButtonStyle())
            .disabled(
                !history.canEdit
                    || (status.completionDate != nil && status.completionDate != history.day))
            .frame(maxWidth: .infinity)
        }
    }

    private func showsStats(_ status: GoalStatus) -> Bool {
        goal.period == .day
            || status.score != nil
            || !GoalListPresentation.forgivenDays(
                goal: goal, logs: history.logs[goal.key] ?? [], today: history.day).isEmpty
    }

    private func statsStrip(status: GoalStatus) -> some View {
        let forgiven = GoalListPresentation.forgivenDays(
            goal: goal, logs: history.logs[goal.key] ?? [], today: history.day)
        return InkCard(padded: true) {
            HStack(alignment: .top, spacing: 0) {
                if goal.period == .day {
                    statCell(
                        title: String(
                            localized: "Zincir · en uzun \(status.longestStreak)", locale: locale),
                        value: GoalListPresentation.streakText(status.streak, locale: locale)
                    )
                    Divider().frame(height: 36)
                }
                if let score = status.score {
                    statCell(
                        title: String(localized: "Son 30 gün", locale: locale),
                        value: "%\(score)"
                    )
                    Divider().frame(height: 36)
                }
                if goal.period == .day {
                    forgivenCell(forgiven)
                }
            }
        }
    }

    private func forgivenCell(_ days: [CalendarDate]) -> some View {
        let count = days.count
        let latest = days.last
        let title: String = {
            if let latest {
                let date = LocalDay.instant(for: latest)
                    .formatted(.dateTime.day().month(.abbreviated).locale(locale))
                return String(localized: "Affedildi · \(date)", locale: locale)
            }
            return String(localized: "Affedildi", locale: locale)
        }()
        return HStack(alignment: .center, spacing: 6) {
            HeatmapCell(
                kind: .forgiven, size: 12, accessibilityValue: Text("Affedildi"),
                accessibilityLabel: Text("Affedildi"))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: String(localized: "\(count) gün", locale: locale))
                    .font(.ink.value)
                    .foregroundStyle(Color.ink.text)
                Text(verbatim: title)
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private func statCell(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: value)
                .font(.ink.value)
                .foregroundStyle(Color.ink.text)
            Text(verbatim: title)
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private var recentLogs: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: String(localized: "Son kayıtlar"))
            InkCard(padded: false) {
                let logs = (history.logs[goal.key] ?? []).sorted { $0.day > $1.day }
                if logs.isEmpty {
                    Text("Henüz kayıt yok")
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                        .padding(InkSpacing.cardPadding)
                } else {
                    ForEach(Array(logs.enumerated()), id: \.element.day) { index, log in
                        if index > 0 { InkCardDivider() }
                        Button {
                            Task { await edit(log.day) }
                        } label: {
                            HStack {
                                Text(
                                    LocalDay.instant(for: log.day),
                                    format: .dateTime.day().month().year()
                                )
                                .font(.ink.meta)
                                .foregroundStyle(Color.ink.secondaryText)
                                Spacer()
                                switch log.value {
                                case .boolean(let value):
                                    Text(value ? "Yapıldı" : "İşaretle")
                                        .font(.ink.byline)
                                        .foregroundStyle(Color.ink.text)
                                case .number(let value):
                                    Text(verbatim: value.formatted() + " " + (goal.unit ?? ""))
                                        .font(.ink.value)
                                        .foregroundStyle(Color.ink.text)
                                }
                            }
                            .padding(.horizontal, InkSpacing.cardPadding)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                            .tapTarget()
                        }
                        .buttonStyle(.plain)
                        .disabled(!history.canEdit)
                    }
                }
            }
        }
    }

    private var footerActions: some View {
        VStack(alignment: .leading, spacing: 4) {
            if store.canAddEvent {
                Button("Hedefi düzenle") { isEditing = true }
                    .buttonStyle(InkTextButtonStyle())
                    .accessibilityIdentifier("button.goal.edit")
            }
            Button("Hedefi sil", role: .destructive) {
                deletion.request(path: goal.id)
            }
            .buttonStyle(InkDestructiveButtonStyle())
            .disabled(!store.canAddEvent || deletion.isDeleting || deletion.isDeleted)
            .accessibilityIdentifier("button.goal.delete")
        }
    }

    private func graceDayLine(_ balance: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text(verbatim: GraceDayPresentation.balanceText(balance))
                    .font(.ink.byline)
                    .foregroundStyle(Color.ink.text)
            } icon: {
                Image(systemName: "link")
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
            }
            Text(verbatim: GraceDayPresentation.explanation())
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("goal.graceDays")
    }

    private func increment() async {
        let current: Double =
            if case .number(let number) = history.value(for: goal) { number } else { 0 }
        _ = await history.set(goal, value: .number(current + 1))
    }

    private func edit(_ day: CalendarDate) async {
        let model = GoalDayModel(store: store, day: day)
        await model.load()
        if model.canEdit { editing = GoalValueModel(dayModel: model, goal: goal) }
    }
}

/// The split view's goal page for the selected goal id: its newest definition from the index
/// (``IndexStore/computeGoalDefinitions()``). The column stays blank until the first answer; a goal
/// no longer listed gives the empty prompt.
struct GoalDetailColumn: View {
    let store: IndexStore
    let goalID: String?
    @State private var loaded: (vault: URL?, goals: [GoalDefinition])?

    private var goals: [GoalDefinition]? {
        guard let loaded, loaded.vault == store.vaultURL else { return nil }
        return loaded.goals
    }

    var body: some View {
        ZStack {
            if let goalID, let goals {
                if let goal = goals.first(where: { $0.id == goalID }) {
                    GoalDetailView(store: store, goal: goal).id(goal.id + (store.vaultURL?.path ?? ""))
                } else {
                    MacEmptyDetail("Bir hedef seç")
                }
            } else if goalID == nil {
                MacEmptyDetail("Bir hedef seç")
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: store.lastUpdated) {
            let vault = store.vaultURL
            guard let rows = try? await store.computeGoalDefinitions() else { return }
            loaded = (vault, rows.map(\.definition))
        }
    }
}
