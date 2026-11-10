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
    @ScaledMetric(relativeTo: .body) private var scrollColumnWidth: CGFloat = 118
    /// The drawing's 30 pt ring and "+" in the card's top row.
    @ScaledMetric(relativeTo: .body) private var markSide: CGFloat = 30
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
        let columns = daily + period
        if !columns.isEmpty {
            VStack(alignment: .leading, spacing: InkSpacing.row) {
                SectionHeader(
                    title: String(
                        localized: "Hedefler",
                        bundle: PresentationLocalization.bundle(locale), locale: locale),
                    counter: counter
                        ?? "\(daily.filter { model.isComplete(for: $0) }.count)/\(daily.count)"
                )
                // One small card per goal (the drawing's three cards), equal heights in a row.
                Group {
                    if columns.count <= 3 {
                        HStack(alignment: .top, spacing: 8) {
                            ForEach(columns, id: \.id) { goal in
                                goalCard(goal)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 8) {
                                ForEach(columns, id: \.id) { goal in
                                    goalCard(goal)
                                        .frame(width: scrollColumnWidth, alignment: .topLeading)
                                        .frame(maxHeight: .infinity, alignment: .top)
                                }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
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

    /// A goal's own card: filled while open; a finished goal keeps only the outline and recedes.
    private func goalCard(_ goal: GoalDefinition) -> some View {
        let complete = GoalStripPresentation.isPeriodComplete(status: model.status(for: goal))
        return goalColumn(goal, metaText: goal.period == .day ? nil : periodMeta(for: goal))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                if !complete {
                    RoundedRectangle(cornerRadius: InkCorner.card, style: .continuous)
                        .fill(Color.ink.surface)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: InkCorner.card, style: .continuous)
                    .stroke(Color.ink.rule, lineWidth: 1)
            }
    }

    @ViewBuilder private func goalColumn(_ goal: GoalDefinition, metaText: String?) -> some View {
        let status = model.status(for: goal)
        let progress = GoalStripPresentation.progressValue(status: status)
        let isBooleanMark = goal.kind == .boolean || goal.kind == .milestone
        let marked = isBooleanMark && model.isComplete(for: goal)
        let complete = GoalStripPresentation.isPeriodComplete(status: status)
        let value = valueText(for: goal)
        let openValue = openAccessibilityValue(
            value: value, meta: metaText, streak: status.streak, locale: locale)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                ringControl(goal: goal, progress: progress, marked: marked, isBooleanMark: isBooleanMark)
                Spacer(minLength: 0)
                trailingSlot(
                    goal: goal, marked: marked, isBooleanMark: isBooleanMark, complete: complete)
            }
            .frame(height: markSide)
            // The name and meta block opens the goal; the open button lies under the block so
            // its hit area spans the whole block (at least 44 pt tall, accessibility audit: hit
            // region) while the value button on top keeps its own taps (screens.md, Dokunma).
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: goal.name)
                    .font(.subheadline.weight(complete ? .medium : .semibold))
                    .foregroundStyle(complete ? Color.ink.secondaryText : Color.ink.text)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)

                if let value {
                    Button {
                        if model.canEdit { editing = GoalValueModel(dayModel: model, goal: goal) }
                    } label: {
                        // 44 pt tall to the touch, one line to the eye: the frame reaches into the
                        // name above and the card padding below without taking layout room.
                        Text(valueAttributed(value, complete: complete))
                            .font(.ink.meta)
                            .foregroundStyle(Color.ink.secondaryText)
                            .monospacedDigit()
                            .lineLimit(2)
                            .frame(
                                maxWidth: .infinity, minHeight: TapTarget.minimumLength,
                                alignment: .leading
                            )
                            .contentShape(Rectangle())
                            .padding(.vertical, -valueOverlap)
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.canEdit)
                    .accessibilityLabel(Text(verbatim: value))
                    .accessibilityHint(Text("Miktar gir"))
                    .accessibilitySortPriority(1)
                } else if let metaText {
                    // No line limit: at large Dynamic Type sizes the period line wraps in its
                    // narrow column instead of being cut (accessibility audit: text clipped).
                    Text(verbatim: metaText)
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                }
                if let badge = GraceDayPresentation.badge(status: status, locale: locale) {
                    badge
                }
            }
            .background {
                Button {
                    onOpen?(goal)
                } label: {
                    Color.clear.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(onOpen == nil)
                // Label is the name alone; value and chain ride on the value (screens.md: name,
                // value and the "Ayrıntıları göster" hint).
                .accessibilityLabel(Text(verbatim: goal.name))
                .accessibilityValue(Text(verbatim: openValue))
                .accessibilityHint(Text("Ayrıntıları göster"))
                // VoiceOver meets the goal by name first, then its value, ring and plus.
                .accessibilitySortPriority(2)
            }
        }
        // One container per goal: columns sit side by side, so without it VoiceOver would read
        // every ring and plus across the strip before the first name.
        .accessibilityElement(children: .contain)
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

    @ViewBuilder private func ringControl(
        goal: GoalDefinition, progress: Double, marked: Bool, isBooleanMark: Bool
    ) -> some View {
        let ring = GoalRing(
            progress: progress, isBoolean: GoalStripPresentation.isBooleanRing(goal: goal),
            diameter: markSide)
        if marked {
            Button {
                Task {
                    if await model.toggle(goal) { geofences?.clearLockedMarkNotice() }
                }
            } label: {
                ring
            }
            .buttonStyle(.plain)
            .disabled(!model.canEdit)
            .accessibilityLabel(
                Text(
                    verbatim: String(
                        localized: "\(goal.name), işareti kaldır",
                        bundle: PresentationLocalization.bundle(locale), locale: locale)))
        } else {
            ring.accessibilityHidden(true)
        }
    }

    @ViewBuilder private func trailingSlot(
        goal: GoalDefinition, marked: Bool, isBooleanMark: Bool, complete: Bool
    ) -> some View {
        // The slot keeps its place; a marked yes/no goal shows "✓ Tamam" in it (the drawing). A
        // number goal keeps its plus when its period is done: the amount may go past the target,
        // and the plus stays put while a write runs (screens.md, Hedefler).
        if isBooleanMark && marked {
            Label {
                Text("Tamam")
            } icon: {
                Image(systemName: "checkmark")
            }
            .labelStyle(GoalStripDoneLabelStyle())
            .font(.ink.meta)
            .foregroundStyle(Color.ink.secondaryText)
            .lineLimit(1)
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                Text(
                    verbatim: String(
                        localized: "Tamamlandı",
                        bundle: PresentationLocalization.bundle(locale), locale: locale)))
        } else {
            Button {
                if isBooleanMark {
                    Task {
                        if await model.toggle(goal) { geofences?.clearLockedMarkNotice() }
                    }
                } else {
                    Task { await increment(goal) }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.ink.meta.weight(.semibold))
                    .foregroundStyle(Color.ink.accent)
                    .frame(width: markSide, height: markSide)
                    .background(Circle().fill(Color.ink.accentSoft))
                    // 44 pt to the touch around the 30 pt mark, without growing the row.
                    .frame(width: TapTarget.minimumLength, height: TapTarget.minimumLength)
                    .contentShape(Rectangle())
                    .padding(-(TapTarget.minimumLength - markSide) / 2)
                    .opacity(model.canEdit ? 1 : InkGoalRowTrailing.busyPlusOpacity)
            }
            .buttonStyle(.plain)
            .disabled(!model.canEdit)
            .accessibilityLabel(
                Text(
                    verbatim: String(
                        localized: "\(goal.name), artır",
                        bundle: PresentationLocalization.bundle(locale), locale: locale)))
        }
    }

    /// How far the value button's 44 pt frame reaches past its one line of text, each side.
    private var valueOverlap: CGFloat { max(0, (TapTarget.minimumLength - 20) / 2) }

    /// "**12**/20 sayfa": the amount done stands out.
    private func valueAttributed(_ value: String, complete: Bool) -> AttributedString {
        var text = AttributedString(value)
        if !complete, let slash = value.firstIndex(of: "/"),
            let range = Range(NSRange(value.startIndex..<slash, in: value), in: text)
        {
            text[range].inlinePresentationIntent = .stronglyEmphasized
            text[range].foregroundColor = Color.ink.text
        }
        return text
    }

    private func openAccessibilityValue(
        value: String?, meta: String?, streak: Int, locale: Locale
    ) -> String {
        var pieces: [String] = []
        if let value, !value.isEmpty { pieces.append(value) } else if let meta, !meta.isEmpty { pieces.append(meta) }
        if streak > 0 {
            pieces.append(
                String(
                    localized: "\(streak) gün zincir",
                    bundle: PresentationLocalization.bundle(locale), locale: locale))
        }
        return pieces.joined(separator: ", ")
    }

    private func valueText(for goal: GoalDefinition) -> String? {
        guard goal.kind == .number else { return nil }
        let amount: Double =
            if case .number(let number) = model.value(for: goal) { number } else { 0 }
        let unit = goal.unit.map { " \($0)" } ?? ""
        let done = amount.formatted(.number.locale(locale))
        let target = goal.target.formatted(.number.locale(locale))
        return "\(done)/\(target)\(unit)"
    }

    private func increment(_ goal: GoalDefinition) async {
        let current: Double =
            if case .number(let number) = model.value(for: goal) { number } else { 0 }
        if await model.set(goal, value: .number(current + 1)) {
            geofences?.clearLockedMarkNotice()
        }
    }
}

/// "✓ Tamam" with a tight gap.
private struct GoalStripDoneLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.accessibilityHidden(true)
            configuration.title
        }
    }
}
