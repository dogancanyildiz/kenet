import GoalTracking
import SwiftUI
import VaultFormat

/// Card row for one goal on the Goals list.
struct GoalListCard<Detail: View>: View {
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
    /// A large number goal's pencil (``GoalAmountPresentation/usesQuickIncrement(_:)``).
    let onEnterAmount: () -> Void
    let onUnmark: () -> Void

    @ScaledMetric(relativeTo: .body) private var plusSide: CGFloat = 46

    private var progress: Double { GoalRowPresentation.progress(goal: goal, status: status) }
    private var complete: Bool { GoalListPresentation.isComplete(goal: goal, status: status) }
    private var isBooleanMark: Bool { GoalListPresentation.isBooleanMark(goal.kind) }

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
            .accessibilityHint(Text(verbatim: openHint))
        } else if let onOpen {
            Button(action: onOpen) { body }
                .buttonStyle(.plain)
                .disabled(goal.kind == .milestone && (!canEdit || markReadOnly))
                .accessibilityLabel(Text(verbatim: accessibilityLabelText))
                .accessibilityHint(Text(verbatim: openHint))
        } else {
            body
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: accessibilityLabelText))
        }
    }

    private var openHint: String {
        GoalListPresentation.listOpenHint(kind: goal.kind, markedToday: markedToday, locale: locale)
    }

    /// One element: "ad, değer" (or meta for milestones), matching list query tests.
    private var accessibilityLabelText: String {
        GoalListPresentation.accessibilityLabel(goal: goal, status: status, locale: locale)
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
                Text(verbatim: GoalRowPresentation.meta(goal: goal, status: status, locale: locale) ?? "")
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
                    ? PresentationLocalization.string(localized: "Bu hafta", locale: locale) : nil)
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
        } else if !GoalAmountPresentation.usesQuickIncrement(goal) {
            // Opens the goal page also while the vault is read-only (to look); faded then.
            Button(action: onEnterAmount) {
                trailingGlyph("pencil")
                    .opacity(canEdit ? 1 : InkGoalRowTrailing.busyPlusOpacity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                Text(
                    verbatim: String(
                        localized: "\(goal.name), miktar gir", bundle: PresentationLocalization.bundle(locale),
                        locale: locale))
            )
            .accessibilityHint(Text("Hedef sayfasını açar"))
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
        trailingGlyph("plus")
            .opacity(canEdit && !markReadOnly ? 1 : InkGoalRowTrailing.busyPlusOpacity)
    }

    private func trailingGlyph(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.title3.weight(.medium))
            .foregroundStyle(Color.ink.accent)
            .frame(width: plusSide, height: plusSide)
            .background {
                Circle().fill(Color.ink.well)
                Circle().strokeBorder(Color.ink.rule, lineWidth: 1)
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }
}

/// Icon and title close together on one baseline ("🔗 Zincir 12 gün").
struct GoalStreakLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            configuration.icon.accessibilityHidden(true)
            configuration.title
        }
    }
}
