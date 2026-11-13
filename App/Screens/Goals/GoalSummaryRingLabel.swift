import GoalTracking
import SwiftUI
import VaultFormat

/// One goal in the summary card: a large progress ring with the percent, the name and the value.
struct GoalSummaryRingLabel: View {
    let goal: GoalDefinition
    let status: GoalStatus
    let locale: Locale
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 64

    var body: some View {
        let progress = GoalRowPresentation.progress(goal: goal, status: status)
        let complete = GoalListPresentation.isComplete(goal: goal, status: status)
        let percent = GoalListPresentation.percentLabel(
            done: status.progress.done, target: goal.target, locale: locale)
        VStack(spacing: 4) {
            GoalRing(progress: progress, diameter: side, centerLabel: percent, emphasizesArc: true)
                .padding(.bottom, 4)
            Text(verbatim: goal.name)
                .font(.ink.meta.weight(.semibold))
                .foregroundStyle(Color.ink.text)
                .lineLimit(1)
            Text(verbatim: valueLine(complete: complete))
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(minWidth: 72)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: goal.name))
        .accessibilityValue(Text(verbatim: "\(percent), \(valueLine(complete: complete))"))
    }

    private func valueLine(complete: Bool) -> String {
        if goal.period == .week {
            let amount =
                status.progress.done.formatted(.number.locale(locale)) + "/"
                + goal.target.formatted(.number.locale(locale))
            return PresentationLocalization.string(localized: "bu hafta \(amount)", locale: locale)
        }
        let base = GoalRowPresentation.valueText(goal: goal, status: status, locale: locale) ?? ""
        return complete ? "✓ \(base)" : base
    }
}
