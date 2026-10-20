import GoalTracking
import SwiftUI
import VaultFormat

/// Preference for snapshot hosts waiting until the strip's model finished loading: the day page
/// and the close-day flow set it, also when the vault has no goal.
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

    /// Goals still open for their period first, then complete ones; each group by name. `status`
    /// is asked once per goal, not per comparison.
    static func ordered(_ goals: [GoalDefinition], status: (GoalDefinition) -> GoalStatus) -> [GoalDefinition] {
        goals.map { (goal: $0, isDone: isPeriodComplete(status: status($0))) }
            .sorted {
                if $0.isDone != $1.isDone { return !$0.isDone }
                return $0.goal.name.localizedStandardCompare($1.goal.name) == .orderedAscending
            }
            .map(\.goal)
    }

    /// The order a strip keeps while its day is on screen: the ids of `previous` that are still
    /// listed, in their order, then the new ones in `current`'s order. A goal marked done keeps its
    /// place; a goal added goes last.
    static func stableOrder(previous: [String], current: [String]) -> [String] {
        let listed = Set(current)
        let kept = previous.filter { listed.contains($0) }
        let known = Set(kept)
        return kept + current.filter { !known.contains($0) }
    }
}

/// A goal page pushed from the Today strip; the page reads the goal's newest definition by id.
struct GoalDetailRoute: Hashable {
    let goal: GoalDefinition

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.goal.id == rhs.goal.id }
    func hash(into hasher: inout Hasher) { hasher.combine(goal.id) }
}

struct GoalStripView: View {
    @Environment(GeofenceService.self) private var geofences: GeofenceService?
    @Environment(\.locale) private var locale
    @State private var editing: GoalValueModel?
    /// The order taken once the day's history first loaded (open goals first); later loads keep
    /// it. The strip is a new view per day and vault (``GoalStripIdentity``), with a new order.
    @State private var keptOrder: [String]?
    /// The page's editing model for the day: its count draws an edit made here before the answer.
    /// The page loads it on every publish; with no goals loaded the strip draws nothing.
    private let model: GoalDayModel
    private let countedGoalIDs: [String]
    private let counter: String?
    private let onOpen: ((GoalDefinition) -> Void)?

    init(
        model: GoalDayModel, countedGoalIDs: [String] = [], counter: String? = nil,
        onOpen: ((GoalDefinition) -> Void)? = nil
    ) {
        self.model = model
        self.countedGoalIDs = countedGoalIDs
        self.counter = counter
        self.onOpen = onOpen
    }

    var body: some View {
        let order = goalOrder
        let daily = ordered(dailySource, by: order)
        let period = ordered(model.goals.filter { $0.period != .day }, by: order)
        if !daily.isEmpty || !period.isEmpty {
            VStack(alignment: .leading, spacing: InkSpacing.row) {
                SectionHeader(
                    title: String(
                        localized: "Hedefler",
                        bundle: PresentationLocalization.bundle(locale), locale: locale),
                    counter: counter
                        ?? "\(daily.filter { model.isComplete(for: $0) }.count)/\(daily.count)"
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
            .onChange(of: model.hasLoaded, initial: true) { keepOrder() }
            .onChange(of: model.goals.map(\.id)) { keepOrder() }
            .sheet(item: $editing) { editor in
                NavigationStack { GoalValueEditor(model: editor) }
                    .inkAdaptiveSheetPresentation(fitsContent: true, usesPhoneDetents: false)
                    .onChange(of: editor.isSaved) { _, saved in
                        if saved { geofences?.clearLockedMarkNotice() }
                    }
            }
        }
    }

    private var dailySource: [GoalDefinition] {
        let counted = Set(countedGoalIDs)
        return counted.isEmpty
            ? model.goals.filter { $0.period == .day }
            : model.goals.filter { counted.contains($0.id) }
    }

    /// Every goal's id by the open-first rule, as the history now stands.
    private var currentOrder: [String] {
        GoalStripPresentation.ordered(model.goals, status: model.status(for:)).map(\.id)
    }

    /// Before the first load the order follows the history; from then on it is the kept one.
    private var goalOrder: [String] {
        let current = currentOrder
        guard let keptOrder else { return current }
        return GoalStripPresentation.stableOrder(previous: keptOrder, current: current)
    }

    private func keepOrder() {
        guard model.hasLoaded else { return }
        keptOrder = goalOrder
    }

    private func ordered(_ goals: [GoalDefinition], by order: [String]) -> [GoalDefinition] {
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return goals.sorted { (rank[$0.id] ?? .max) < (rank[$1.id] ?? .max) }
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
        let isBooleanMark = goal.kind == .boolean || goal.kind == .milestone
        let marked = isBooleanMark && model.isComplete(for: goal)
        // The controls are there whether or not the model takes edits now (a write or a reload
        // runs): the row keeps its layout, and `isEditable` turns the taps off.
        InkGoalRow(
            name: goal.name,
            progress: progress,
            isBoolean: GoalStripPresentation.isBooleanRing(goal: goal),
            meta: metaText,
            valueText: valueText(for: goal),
            onIncrement: marked
                ? nil
                : {
                    if isBooleanMark {
                        Task {
                            if await model.toggle(goal) { geofences?.clearLockedMarkNotice() }
                        }
                    } else {
                        Task { await increment(goal) }
                    }
                },
            onValueTap: goal.kind == .number
                ? { if model.canEdit { editing = GoalValueModel(dayModel: model, goal: goal) } } : nil,
            onMarkTap: marked
                ? {
                    Task {
                        if await model.toggle(goal) { geofences?.clearLockedMarkNotice() }
                    }
                } : nil,
            onOpen: onOpen.map { open in { open(goal) } },
            showsPlus: !marked,
            isEditable: model.canEdit,
            keepsLayout: true,
            incrementLabel: LocalizedStringKey(marked ? "İşareti kaldır" : "Artır")
        )
        .contextMenu {
            if model.canEdit, goal.kind == .number {
                Button("Miktar gir") { editing = GoalValueModel(dayModel: model, goal: goal) }
            }
            if model.canEdit, marked {
                Button("İşareti kaldır") {
                    Task {
                        if await model.toggle(goal) { geofences?.clearLockedMarkNotice() }
                    }
                }
            }
        }
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
