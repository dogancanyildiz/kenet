import GoalTracking
import SwiftUI
import VaultFormat

/// One goal in the split shell's Hedefler column (Mac and iPad drawing): a small ring, the name
/// with its period chip and the value on one line; under it the last 7 days and "zincir 12"
/// (daily), the year's bar and percent (yearly) or the milestone's state. The whole card selects
/// the goal; marking stays in the context menu and on the detail page. A milestone has no page:
/// its card marks or unmarks today (``GoalListContent``).
struct GoalColumnRow: View {
    let goal: GoalDefinition
    let status: GoalStatus
    let day: CalendarDate
    let logs: [GoalLog]
    let locale: Locale
    let isDisabled: Bool
    /// Today's own mark: a milestone's card toggles it, so its hint names the direction.
    let markedToday: Bool
    var isSelected = false
    let onOpen: () -> Void
    @ScaledMetric(relativeTo: .body) private var ringSide: CGFloat = 28
    @Environment(\.dynamicTypeSize) private var typeSize

    private var progress: Double { GoalRowPresentation.progress(goal: goal, status: status) }

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 12) {
                GoalRing(progress: progress, diameter: ringSide, emphasizesArc: true)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    titleLine
                    subLine
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: TapTarget.minimumLength, alignment: .leading)
            .modifier(InkCardModifier(cornerRadius: InkCorner.md))
            .inkCardSelection(isSelected)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(Text(verbatim: accessibilityLabelText))
        .accessibilityHint(
            Text(
                verbatim: GoalListPresentation.listOpenHint(
                    kind: goal.kind, markedToday: markedToday, locale: locale)))
    }

    private var titleLine: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                name
                TagChip(title: GoalListPresentation.periodChip(goal.period, locale: locale))
                Spacer(minLength: 4)
                value
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    name
                    TagChip(title: GoalListPresentation.periodChip(goal.period, locale: locale))
                }
                value
            }
        }
    }

    private var name: some View {
        Text(verbatim: goal.name)
            .font(.ink.content.weight(.semibold))
            .foregroundStyle(Color.ink.text)
            .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
    }

    /// "**30** / 20 sayfa", "bu hafta **3**/3", or "—" for a milestone.
    @ViewBuilder private var value: some View {
        let done = status.progress.done.formatted(.number.locale(locale))
        let target = goal.target.formatted(.number.locale(locale))
        let unit = goal.unit.map { " " + $0 } ?? ""
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if goal.kind == .milestone {
                Text(verbatim: "—")
            } else {
                if goal.period == .week {
                    Text(verbatim: GoalListPresentation.columnWeekLabel(locale: locale))
                        .padding(.trailing, 4)
                }
                Text(verbatim: done).fontWeight(.semibold).foregroundStyle(Color.ink.text)
                Text(verbatim: goal.period == .week ? "/" + target : " / " + target + unit)
            }
        }
        .font(.ink.meta.monospacedDigit())
        .foregroundStyle(Color.ink.secondaryText)
        .lineLimit(1)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var subLine: some View {
        if goal.kind == .milestone {
            if let meta = GoalRowPresentation.meta(goal: goal, status: status, locale: locale) {
                Text(verbatim: meta)
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
            }
        } else if goal.period == .day {
            InkFlowLayout(spacing: 8, lineSpacing: 4) {
                GoalTallyStrip(
                    days: GoalListPresentation.tallyDays(
                        goal: goal, logs: logs, today: day, graceSpent: Set(status.graceSpentDays)))
                Text(verbatim: GoalListPresentation.columnStreakLabel(status.streak, locale: locale))
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                if let badge = GoalRowPresentation.graceBadge(goal: goal, status: status, locale: locale) {
                    badge
                }
            }
        } else if goal.period == .year {
            HStack(spacing: 8) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.ink.well)
                        Capsule().fill(Color.ink.accent)
                            .frame(width: proxy.size.width * min(max(status.progress.fraction, 0), 1))
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
                Text(GoalListPresentation.percentLabel(done: status.progress.done, target: goal.target, locale: locale))
                    .font(.ink.meta.monospacedDigit())
                    .foregroundStyle(Color.ink.secondaryText)
            }
        } else if let remaining = GoalListPresentation.remainingText(goal: goal, status: status, locale: locale) {
            Text(verbatim: remaining)
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
        }
    }

    private var accessibilityLabelText: String {
        GoalListPresentation.accessibilityLabel(goal: goal, status: status, locale: locale)
    }
}
