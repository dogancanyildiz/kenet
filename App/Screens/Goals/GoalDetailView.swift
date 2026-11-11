import GoalTracking
import SwiftUI
import VaultFormat

struct GoalDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var deletion = DefinitionDeletionModel()
    let store: IndexStore
    private let original: GoalDefinition
    @State private var history: GoalDayModel
    /// A past day picked from the heatmap or the log list: the amount panel and the mark button
    /// edit it until "Bugüne dön". Nil edits the page's own day.
    @State private var pickedDay: GoalDayModel?
    /// Each change focuses the amount field (a card's pencil, a picked day).
    @State private var focusToken: Int
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.locale) private var locale
    @State private var isEditing = false
    /// "Son kayıtlar" lists the newest ``recentLimit`` rows until the reader asks for all of them.
    @State private var showsAllLogs = false
    private static let recentLimit = 3
    @ScaledMetric(relativeTo: .caption) private var forgivenMark: CGFloat = 12

    /// - Parameter focusesAmount: a number goal's page opens with the amount field focused (the
    ///   card's pencil, "Miktar gir").
    init(
        store: IndexStore, goal: GoalDefinition, day: CalendarDate = LocalDay.today(),
        focusesAmount: Bool = false, amountDay: CalendarDate? = nil
    ) {
        self.store = store
        original = goal
        _history = State(initialValue: GoalDayModel(store: store, day: day))
        let pastDay = amountDay == day ? nil : amountDay
        // A past day focuses once it is picked and loaded (``edit(_:focuses:)``), not today's field.
        _focusToken = State(initialValue: focusesAmount && goal.kind == .number && pastDay == nil ? 1 : 0)
        initialAmountDay = pastDay
        focusesInitialDay = focusesAmount
    }

    /// A past day's strip opened the page: that day is picked once the page appears.
    private let initialAmountDay: CalendarDate?
    private let focusesInitialDay: Bool
    /// Mac: a click on the page's empty room takes the amount field's focus, which writes it.
    @State private var blurToken = 0
    /// The goal is being deleted: the amount panel drops what was typed, so its exit write does not
    /// bring the deleted goal's line back into a day file.
    @State private var discardToken = 0
    private let notice = GoalAmountNotice.shared
    @State private var pickedInitialDay = false

    /// The day the amount panel and the mark button edit.
    private var editedDay: GoalDayModel { pickedDay ?? history }

    /// The goal's newest definition by id, as the history model last loaded it; the one the page
    /// was opened with until then, and once the file is gone.
    private var goal: GoalDefinition { history.goals.first { $0.id == original.id } ?? original }

    private var masthead: InkPageTitle<some View> {
        // Drawing: the period pill sits on the title's row, search alone on the navigation row.
        InkPageTitle(verbatim: goal.name) {
            SearchButton()
        }
        .titleAccessory(periodPill)
    }

    var body: some View {
        let status = history.status(for: goal)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: InkSpacing.section) {
                    InkScrolledMasthead(masthead)

                    if goal.kind != .milestone {
                        editedDayLine(editedDay.day)
                            .padding(.horizontal, InkSpacing.margin)
                    }
                    if let error = pickedDay?.errorText {
                        InfoBand(kind: .error, verbatim: error)
                            .padding(.horizontal, InkSpacing.margin)
                    }

                    hero(status: status)
                        .padding(.horizontal, InkSpacing.margin)
                        .id(Self.heroID)

                    actions(status: status)
                        .padding(.horizontal, InkSpacing.margin)

                    if goal.kind != .milestone, showsStats(status) {
                        statsStrip(status: status)
                            .padding(.horizontal, InkSpacing.margin)
                    }

                    if let forgiven = latestForgivenDay {
                        forgivenLine(forgiven)
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
                    if let message = notice.message {
                        InfoBand(kind: .error, verbatim: message, onDismiss: { notice.message = nil })
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
                #if os(macOS)
                    // A click on the page's empty room ends the amount entry (and writes it):
                    // AppKit keeps a text field's focus otherwise.
                    .background {
                        Color.clear.contentShape(Rectangle()).onTapGesture { blurToken += 1 }
                    }
                #endif
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: pickedDay?.day) { _, _ in
                withAnimation { proxy.scrollTo(Self.heroID, anchor: .top) }
            }
        }
        .inkPinnedMasthead(masthead, insets: EdgeInsets(top: 12, leading: 0, bottom: 8, trailing: 0))
        .inkPage()
        .inkPageNavigationTitle(verbatim: goal.name)
        #if os(iOS)
            .toolbar(.hidden, for: .tabBar)
        #endif
        .task(id: store.lastUpdated) {
            await history.load()
            // A picked past day follows outside changes too, or a quick step adds to a stale value.
            await pickedDay?.load()
        }
        .task {
            guard let day = initialAmountDay, !pickedInitialDay else { return }
            pickedInitialDay = true
            await edit(day, focuses: focusesInitialDay)
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
            discardToken += 1
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

    private static let heroID = "goal.hero"

    private func hero(status: GoalStatus) -> some View {
        Group {
            if goal.kind == .number {
                GoalAmountPanel(
                    model: editedDay, goal: goal, focusToken: focusToken, blurToken: blurToken,
                    discardToken: discardToken, onWrite: { if pickedDay != nil { await history.load() } }
                )
                // A new panel per day model: the old one writes what was typed for its own day as
                // it goes (``GoalAmountPanel``).
                .id(ObjectIdentifier(editedDay))
            } else if goal.kind == .milestone {
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
        let day = editedDay
        let marked = day.isMarkedToday(goal)
        let markReadOnly =
            status.completionDate != nil && status.completionDate != day.day
        // A number goal's amount is the panel at the top (``GoalAmountPanel``).
        if goal.kind == .boolean || goal.kind == .milestone {
            Button {
                Task {
                    if await day.toggle(goal), pickedDay != nil { await history.load() }
                }
            } label: {
                Group {
                    if marked {
                        Text("İşareti kaldır")
                    } else if pickedDay != nil {
                        Text("Bu günü işaretle")
                    } else {
                        Text("Bugünü işaretle")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(InkSecondaryButtonStyle())
            .disabled(!day.canEdit || markReadOnly)
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
                    let shown = showsAllLogs ? logs : Array(logs.prefix(Self.recentLimit))
                    // One stack without the card's row gap: rows sit flush between hairlines.
                    VStack(spacing: 0) {
                        ForEach(Array(shown.enumerated()), id: \.element.day) { index, log in
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
            let count = (history.logs[goal.key] ?? []).count
            if count > Self.recentLimit {
                Button {
                    showsAllLogs.toggle()
                } label: {
                    Group {
                        if showsAllLogs { Text("Daha az göster") } else { Text("Tüm kayıtlar (\(count))") }
                    }
                    .font(.ink.meta.weight(.semibold))
                }
                .buttonStyle(InkTextButtonStyle())
                .accessibilityIdentifier("button.goal.allLogs")
            }
        }
    }

    /// The newest forgiven miss in the last 90 days: the page explains why it did not break the chain.
    private var latestForgivenDay: CalendarDate? {
        GoalListPresentation.forgivenDays(
            goal: goal, logs: history.logs[goal.key] ?? [], today: history.day
        ).last
    }

    /// "⬚ 14 Eyl affedildi: önceki iki gün ve ertesi gün yapıldı." under the stats card. A miss is
    /// forgiven only when the two days before it and the day after it were done (``GoalProgress``).
    private func forgivenLine(_ day: CalendarDate) -> some View {
        let date = LocalDay.instant(for: day).formatted(.dateTime.day().month(.abbreviated).locale(locale))
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            HeatmapCell(
                kind: .forgiven, size: forgivenMark, accessibilityValue: Text("Affedildi"),
                accessibilityLabel: Text("Affedildi")
            )
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            .accessibilityHidden(true)
            Text(
                "\(Text("\(date) affedildi:").fontWeight(.semibold).foregroundStyle(Color.ink.text)) önceki iki gün ve ertesi gün yapıldı."
            )
            .font(.ink.meta)
            .foregroundStyle(Color.ink.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("goal.forgivenDay")
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

    /// "12 Kas Perşembe düzenleniyor" over the panel, always: the day the panel and the mark
    /// button write to. A past day adds "Bugüne dön".
    private func editedDayLine(_ day: CalendarDate) -> some View {
        let date = LocalDay.instant(for: day)
            .formatted(.dateTime.day().month(.abbreviated).weekday(.wide).locale(locale))
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(date) düzenleniyor")
                .font(.ink.meta.weight(.semibold))
                .foregroundStyle(pickedDay == nil ? Color.ink.secondaryText : Color.ink.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("goal.editedDay")
            Spacer(minLength: 8)
            if pickedDay != nil {
                Button("Bugüne dön") {
                    focusToken = 0
                    pickedDay = nil
                }
                .buttonStyle(InkTextButtonStyle())
                .accessibilityIdentifier("button.goal.backToToday")
            }
        }
        .frame(minHeight: TapTarget.minimumLength)
    }

    /// A heatmap cell or a log row: the panel at the top edits that day (no separate sheet). The
    /// day shows at once from the page's history and takes input once it loaded; a failed load
    /// stays on that day with its error, never falling back to today.
    private func edit(_ day: CalendarDate, focuses: Bool = true) async {
        if day == history.day {
            pickedDay = nil
        } else {
            let model = GoalDayModel(store: store, day: day, startingFrom: history)
            pickedDay = model
            await model.load()
        }
        if focuses, goal.kind == .number { focusToken += 1 }
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
