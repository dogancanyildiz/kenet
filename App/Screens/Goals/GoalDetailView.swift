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
    @ScaledMetric(relativeTo: .caption) private var forgivenMark: CGFloat = 12

    init(store: IndexStore, goal: GoalDefinition, day: CalendarDate = LocalDay.today()) {
        self.store = store
        original = goal
        _history = State(initialValue: GoalDayModel(store: store, day: day))
    }

    /// The goal's newest definition by id, as the history model last loaded it; the one the page
    /// was opened with until then, and once the file is gone.
    private var goal: GoalDefinition { history.goals.first { $0.id == original.id } ?? original }

    private var masthead: InkPageTitle<some View> {
        InkPageTitle(verbatim: goal.name) {
            periodPill
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

                actions(status: status)
                    .padding(.horizontal, InkSpacing.margin)

                if goal.kind != .milestone, showsStats(status) {
                    statsStrip(status: status)
                        .padding(.horizontal, InkSpacing.margin)
                }

                if goal.period == .day, let balance = GraceDayPresentation.balance(status: status) {
                    graceDayLine(balance)
                        .padding(.horizontal, InkSpacing.margin)
                }

                if GoalValueChart.isShown(for: goal) {
                    chartSection
                } else if goal.kind == .boolean {
                    heatmapSection(status: status)
                }

                if goal.kind == .number {
                    heatmapSection(status: status)
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
            NavigationStack { GoalDefinitionForm(store: store, goal: goal) }
        }
        .onChange(of: deletion.isDeleted) { _, deleted in
            if deleted { dismiss() }
        }
        .destructiveConfirmationDialog(
            "Hedefi sil", confirmation: $deletion.confirmation,
            confirmTitle: "Hedefi sil",
            message: "\(goal.name) silinsin mi? Gün kayıtları kalır."
        ) { path in
            Task { _ = await deletion.delete(store: store, path: path, goal: true) }
        }
    }

    /// "Günlük · 20 sayfa" beside the title (the drawing's period pill).
    private var periodPill: some View {
        let period = GoalListPresentation.periodChip(goal.period, locale: locale)
        var amount: String?
        if goal.kind == .number {
            amount = goal.target.formatted(.number.locale(locale)) + (goal.unit.map { " " + $0 } ?? "")
        }
        return HStack(spacing: 4) {
            Text(verbatim: period)
                .fontWeight(.semibold)
                .foregroundStyle(Color.ink.text)
            if let amount {
                Text(verbatim: "· " + amount)
                    .foregroundStyle(Color.ink.secondaryText)
            }
        }
        .font(.ink.meta)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.ink.surface))
        .overlay(Capsule().strokeBorder(Color.ink.rule, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var chartSection: some View {
        InkCard(padded: true) {
            GoalValueChart(
                goal: goal, logs: history.logs[goal.key] ?? [], today: history.day,
                title: GoalValueChart.title(
                    for: goal, isAccessibilitySize: typeSize.isAccessibilitySize))
        }
        .padding(.horizontal, InkSpacing.margin)
    }

    private func heatmapSection(status: GoalStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: String(localized: "Isı haritası"))
            InkCard(padded: true) {
                GoalHeatmap(
                    goal: goal, logs: history.logs[goal.key] ?? [], today: history.day,
                    graceSpentDays: Set(status.graceSpentDays)
                ) { day in
                    Task { await edit(day) }
                }
                .disabled(!history.canEdit)
            }
        }
        .padding(.horizontal, InkSpacing.margin)
    }

    private func hero(status: GoalStatus) -> some View {
        Group {
            if goal.kind == .milestone {
                GoalProgressLabel(goal: goal, status: status)
            } else {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            LargeNumberText(verbatim: status.progress.done.formatted(), weight: .bold)
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
                                done: status.progress.done, target: goal.target, locale: locale)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func actions(status: GoalStatus) -> some View {
        let marked = history.isMarkedToday(goal)
        let markReadOnly =
            status.completionDate != nil && status.completionDate != history.day
        if goal.kind == .number {
            HStack(spacing: 12) {
                Button {
                    editing = GoalValueModel(dayModel: history, goal: goal)
                } label: {
                    Label("Miktar gir", systemImage: "line.3.horizontal")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(InkSecondaryButtonStyle())
                .disabled(!history.canEdit)

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
        } else if goal.kind == .boolean || goal.kind == .milestone {
            Button {
                Task { await history.toggle(goal) }
            } label: {
                Text(marked ? "İşareti kaldır" : "Bugünü işaretle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(InkSecondaryButtonStyle())
            .disabled(!history.canEdit || markReadOnly)
        }
    }

    private func showsStats(_ status: GoalStatus) -> Bool {
        goal.period == .day
            || status.score != nil
            || !GoalListPresentation.forgivenDays(
                goal: goal, logs: history.logs[goal.key] ?? [], today: history.day
            ).isEmpty
    }

    private func statsStrip(status: GoalStatus) -> some View {
        let forgiven = GoalListPresentation.forgivenDays(
            goal: goal, logs: history.logs[goal.key] ?? [], today: history.day)
        return InkCard(padded: true) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    statsCells(status: status, forgiven: forgiven, axis: .horizontal)
                }
                VStack(alignment: .leading, spacing: 12) {
                    statsCells(status: status, forgiven: forgiven, axis: .vertical)
                }
            }
        }
    }

    @ViewBuilder
    private func statsCells(
        status: GoalStatus, forgiven: [CalendarDate], axis: Axis
    ) -> some View {
        if goal.period == .day {
            statCell(
                title: String(
                    localized: "Zincir · en uzun \(status.longestStreak)", locale: locale),
                value: String(localized: "\(status.streak) gün", locale: locale),
                systemImage: "link"
            )
            statsDivider(axis: axis)
        }
        if let score = status.score {
            statCell(
                title: String(localized: "Son 30 gün", locale: locale),
                value: GoalListPresentation.scorePercentLabel(score, locale: locale)
            )
            if goal.period == .day { statsDivider(axis: axis) }
        }
        if goal.period == .day {
            forgivenCell(forgiven)
        }
    }

    @ViewBuilder private func statsDivider(axis: Axis) -> some View {
        switch axis {
        case .horizontal:
            Divider()
        case .vertical:
            Divider()
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
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 6) {
                HeatmapCell(
                    kind: .forgiven, size: forgivenMark, accessibilityValue: Text("Affedildi"),
                    accessibilityLabel: Text("Affedildi"))
                statValue(String(localized: "\(count) gün", locale: locale))
            }
            statTitle(title)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
    }

    /// A stat: an optional icon and a bold value ("🔗 12 gün"), the label under it on one line.
    private func statCell(title: String, value: String, systemImage: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.ink.meta.weight(.semibold))
                        .foregroundStyle(Color.ink.accent)
                        .accessibilityHidden(true)
                }
                statValue(value)
            }
            statTitle(title)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
    }

    private func statValue(_ value: String) -> some View {
        Text(verbatim: value)
            .font(.ink.value.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(Color.ink.text)
            .lineLimit(1)
    }

    private func statTitle(_ title: String) -> some View {
        Text(verbatim: title)
            .font(.ink.meta)
            .foregroundStyle(Color.ink.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private var recentLogs: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: String(localized: "Son kayıtlar"))
                if history.canEdit, !(history.logs[goal.key] ?? []).isEmpty {
                    Text("Dokun, düzelt")
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                        .fixedSize()
                        .accessibilityHidden(true)
                }
            }
            InkCard(padded: false) {
                let logs = (history.logs[goal.key] ?? []).sorted { $0.day > $1.day }
                if logs.isEmpty {
                    Text("Henüz kayıt yok")
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                        .padding(InkSpacing.cardPadding)
                } else {
                    // One stack without the card's row gap: rows sit flush between hairlines.
                    VStack(spacing: 0) {
                        ForEach(Array(logs.enumerated()), id: \.element.day) { index, log in
                            if index > 0 { InkCardDivider().padding(.leading, InkSpacing.cardPadding) }
                            Button {
                                Task { await edit(log.day) }
                            } label: {
                                logRow(log)
                            }
                            .buttonStyle(.plain)
                            .disabled(!history.canEdit)
                        }
                    }
                }
            }
        }
    }

    /// "19 Eyl Cumartesi … ✓ 25 sayfa ›": the check when the day met the target.
    private func logRow(_ log: GoalLog) -> some View {
        let date = LocalDay.instant(for: log.day)
        let met: Bool =
            switch log.value {
            case .boolean(let value): value
            case .number(let value): value >= goal.target
            }
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(date.formatted(.dateTime.day().month(.abbreviated).locale(locale)))
                .font(.ink.content)
                .foregroundStyle(Color.ink.text)
            Text(date.formatted(.dateTime.weekday(.wide).locale(locale)))
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
            Spacer(minLength: 8)
            if met {
                Image(systemName: "checkmark")
                    .font(.ink.meta.weight(.semibold))
                    .foregroundStyle(Color.ink.secondaryText)
                    .accessibilityHidden(true)
            }
            switch log.value {
            case .boolean(let value):
                Text(value ? "Yapıldı" : "İşaretle")
                    .font(.ink.content.weight(.semibold))
                    .foregroundStyle(Color.ink.text)
            case .number(let value):
                Text(verbatim: value.formatted(.number.locale(locale)) + (goal.unit.map { " " + $0 } ?? ""))
                    .font(.ink.content.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.ink.text)
            }
            if history.canEdit {
                Image(systemName: "chevron.right")
                    .font(.ink.meta.weight(.semibold))
                    .foregroundStyle(Color.ink.tertiaryText)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, InkSpacing.cardPadding)
        .padding(.vertical, 10)
        .frame(minHeight: TapTarget.minimumLength)
        .contentShape(Rectangle())
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
