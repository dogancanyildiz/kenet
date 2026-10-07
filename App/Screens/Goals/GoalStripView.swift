import GoalTracking
import SwiftUI
import VaultFormat

/// Preference for snapshot hosts waiting until the strip finished loading.
struct GoalsStripReadyKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

/// Presentation helpers for the Today goal strip (unit-tested).
enum GoalStripPresentation {
    /// Ring fill from period progress (2/3 → partial arc, 3/3 → full).
    static func progressValue(status: GoalStatus) -> Double {
        status.progress.fraction
    }

    /// Daily boolean/milestone marks stay binary; multi-target periods draw an arc.
    static func isBooleanRing(goal: GoalDefinition) -> Bool {
        goal.kind != .number && goal.target <= 1
    }

    static func isPeriodComplete(status: GoalStatus) -> Bool {
        status.progress.isComplete
    }
}

struct GoalStripView: View {
    @Environment(GeofenceService.self) private var geofences: GeofenceService?
    @Environment(\.locale) private var locale
    @State private var model: GoalDayModel
    @State private var editing: GoalValueModel?
    private let countedGoalIDs: [String]
    private let counter: String?

    init(
        store: IndexStore, day: CalendarDate, countedGoalIDs: [String] = [],
        counter: String? = nil
    ) {
        _model = State(initialValue: GoalDayModel(store: store, day: day))
        self.countedGoalIDs = countedGoalIDs
        self.counter = counter
    }

    var body: some View {
        let daily = dailyGoals
        let period = periodGoals
        if !daily.isEmpty || !period.isEmpty {
            VStack(alignment: .leading, spacing: InkSpacing.row) {
                SectionHeader(
                    title: String(
                        localized: "Hedefler",
                        bundle: PresentationLocalization.bundle(locale), locale: locale),
                    counter: counter
                        ?? "\(daily.filter { model.isComplete(for: $0) }.count)/\(daily.count)",
                    isLoading: model.isLoading
                )
                ForEach(daily, id: \.id) { goal in
                    goalRow(goal, metaText: nil)
                }
                ForEach(period, id: \.id) { goal in
                    goalRow(goal, metaText: periodMeta(for: goal))
                }
                if let error = model.errorText {
                    InfoBand(kind: .error, verbatim: error)
                }
                if let notice = geofences?.lockedMarkNotice {
                    InfoBand(kind: .info, verbatim: notice)
                }
            }
            .accessibilityIdentifier(
                model.hasLoaded && !model.isLoading ? "goals.strip.ready" : "goals.strip.loading"
            )
            .preference(
                key: GoalsStripReadyKey.self, value: model.hasLoaded && !model.isLoading
            )
            .task(id: model.store.lastUpdated) { await model.load() }
            .sheet(item: $editing) { editor in
                NavigationStack { GoalValueEditor(model: editor) }
                    .onChange(of: editor.isSaved) { _, saved in
                        if saved { geofences?.clearLockedMarkNotice() }
                    }
            }
        }
    }

    private var dailyGoals: [GoalDefinition] {
        let counted = Set(countedGoalIDs)
        let source =
            counted.isEmpty
            ? model.goals.filter { $0.period == .day }
            : model.goals.filter { counted.contains($0.id) }
        return ordered(source)
    }

    private var periodGoals: [GoalDefinition] {
        ordered(model.goals.filter { $0.period != .day })
    }

    private func ordered(_ goals: [GoalDefinition]) -> [GoalDefinition] {
        goals.sorted {
            let leftDone = GoalStripPresentation.isPeriodComplete(status: model.status(for: $0))
            let rightDone = GoalStripPresentation.isPeriodComplete(status: model.status(for: $1))
            if leftDone != rightDone { return !leftDone }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func periodMeta(for goal: GoalDefinition) -> String {
        let status = model.status(for: goal)
        let periodKey: String.LocalizationValue =
            switch goal.period {
            case .day: "Bu gün"
            case .week: "Bu hafta"
            case .year: "Bu yıl"
            }
        let period = String(
            localized: periodKey, bundle: PresentationLocalization.bundle(locale), locale: locale)
        let amount =
            status.progress.done.formatted(.number.locale(locale)) + "/"
            + goal.target.formatted(.number.locale(locale))
        if let unit = goal.unit { return "\(period) \(amount) \(unit)" }
        return "\(period) \(amount)"
    }

    @ViewBuilder private func goalRow(_ goal: GoalDefinition, metaText: String?) -> some View {
        let status = model.status(for: goal)
        let progress = GoalStripPresentation.progressValue(status: status)
        let todayMarked = model.isComplete(for: goal)
        let isBooleanMark = goal.kind == .boolean || goal.kind == .milestone
        InkGoalRow(
            name: goal.name,
            progress: progress,
            isBoolean: GoalStripPresentation.isBooleanRing(goal: goal),
            valueText: valueText(for: goal),
            metaText: metaText,
            onIncrement: model.canEdit && !(isBooleanMark && todayMarked)
                ? {
                    if isBooleanMark {
                        Task {
                            if await model.toggle(goal) { geofences?.clearLockedMarkNotice() }
                        }
                    } else {
                        Task { await increment(goal) }
                    }
                } : nil,
            onValueTap: model.canEdit && goal.kind == .number
                ? { editing = GoalValueModel(dayModel: model, goal: goal) } : nil,
            onMarkTap: model.canEdit && isBooleanMark && todayMarked
                ? {
                    Task {
                        if await model.toggle(goal) { geofences?.clearLockedMarkNotice() }
                    }
                } : nil,
            showsPlus: !(isBooleanMark && todayMarked),
            incrementLabel: LocalizedStringKey(
                isBooleanMark && todayMarked ? "İşareti kaldır" : "Artır")
        )
        .contextMenu {
            if model.canEdit, goal.kind == .number {
                Button("Miktar gir") { editing = GoalValueModel(dayModel: model, goal: goal) }
            }
            if model.canEdit, isBooleanMark, todayMarked {
                Button("İşareti kaldır") {
                    Task {
                        if await model.toggle(goal) { geofences?.clearLockedMarkNotice() }
                    }
                }
            }
        }
        .disabled(!model.canEdit)
    }

    private func valueText(for goal: GoalDefinition) -> String? {
        guard goal.kind == .number else { return nil }
        let amount: Double =
            if case .number(let number) = model.value(for: goal) { number } else { 0 }
        let unit = goal.unit.map { " \($0)" } ?? ""
        let done = amount.formatted(.number.locale(locale))
        let target = goal.target.formatted(.number.locale(locale))
        return "\(done) / \(target)\(unit)"
    }

    private func increment(_ goal: GoalDefinition) async {
        let current: Double =
            if case .number(let number) = model.value(for: goal) { number } else { 0 }
        if await model.set(goal, value: .number(current + 1)) {
            geofences?.clearLockedMarkNotice()
        }
    }
}
