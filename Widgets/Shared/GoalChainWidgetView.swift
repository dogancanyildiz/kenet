import AppIntents
import SwiftUI

/// The chain widget's two sizes. WidgetKit's family is read by the widget target and mapped here,
/// so the app's snapshot tests can draw both without WidgetKit.
enum GoalChainLayout: Sendable {
    case small, medium
}

/// The home-screen chain widget: the day's daily goals, open ones first and in full ink, done
/// ones receded with a filled ring (Mürekkep rule 6), each with its chain and chain-day badge.
/// The background is the widget's container; this view draws only the content.
///
/// At accessibility text sizes the small widget shows only the first goal, large, and the medium
/// one two rows without the badge (VoiceOver still reads it). Text stops growing at AX3: past it
/// not even one row fits the widget.
struct GoalChainWidgetView: View {
    /// The day's goals; nil shows "open Kenet" (no snapshot: removed for an unavailable vault or an in-app lock).
    let day: WidgetSnapshot.Day?
    /// Builds the link a goal row opens; nil draws rows without links (the small widget, which
    /// has one tap target for the whole widget).
    let link: ((WidgetSnapshot.Goal) -> URL)?
    let layout: GoalChainLayout
    /// The App Intent a goal row runs in the widget's process instead of opening its link
    /// (``WidgetTap/markInWidget(goalID:)``); nil, or nil for a goal, keeps the link. The row
    /// looks the same either way.
    var intent: ((WidgetSnapshot.Goal) -> (any AppIntent)?)? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }

    private var isLarge: Bool { dynamicTypeSize.isAccessibilitySize }

    @ViewBuilder private var content: some View {
        if let day {
            if day.goals.isEmpty {
                message("Günlük hedef yok")
            } else if layout == .small, isLarge, let first = day.goals.first {
                GoalChainFocus(goal: first)
            } else {
                list(day.goals)
            }
        } else {
            message("Hedeflerini görmek için Kenet'i aç.")
        }
    }

    private var rowLimit: Int { isLarge ? 2 : 3 }

    private func list(_ goals: [WidgetSnapshot.Goal]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            header(done: goals.filter { !$0.isPending }.count, total: goals.count)
            ForEach(goals.prefix(rowLimit)) { goal in
                if let intent = intent?(goal) {
                    button(intent, goal: goal)
                } else if let link {
                    Link(destination: link(goal)) { row(goal) }
                } else {
                    row(goal)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func button(_ intent: any AppIntent, goal: WidgetSnapshot.Goal) -> some View {
        Button(intent: intent) { row(goal) }
            .buttonStyle(.plain)
    }

    private func row(_ goal: WidgetSnapshot.Goal) -> some View {
        GoalChainRow(goal: goal, details: layout == .medium && !isLarge, spaced: !isLarge)
    }

    private func header(done: Int, total: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Hedefler")
                .font(WidgetTheme.section)
                .foregroundStyle(WidgetTheme.text)
            Spacer(minLength: 4)
            Text(verbatim: "\(done)/\(total)")
                .font(WidgetTheme.meta)
                .foregroundStyle(WidgetTheme.secondaryText)
        }
        .lineLimit(1)
        .padding(.bottom, 2)
        .accessibilityElement(children: .combine)
    }

    private func message(_ text: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "Kenet")
                .font(WidgetTheme.section)
                .foregroundStyle(WidgetTheme.text)
            Text(text)
                .font(WidgetTheme.meta)
                .foregroundStyle(WidgetTheme.secondaryText)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
    }
}

/// One goal: ring, name, chain at the end. With `details` (the medium widget at ordinary text
/// sizes) the chain-day badge follows the name and the chain reads "64 gün"; otherwise the chain
/// is the bare count. `spaced` rows share the widget's height (ordinary text sizes).
struct GoalChainRow: View {
    let goal: WidgetSnapshot.Goal
    let details: Bool
    let spaced: Bool

    /// A row a finger can hit, three under the header.
    @ScaledMetric(relativeTo: .subheadline) private var minHeight: CGFloat = 34

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            WidgetGoalRing(goal: goal)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: goal.name)
                    .font(WidgetTheme.name)
                    .foregroundStyle(goal.isPending ? WidgetTheme.text : WidgetTheme.secondaryText)
                    .lineLimit(1)
                if details, goal.chainDays > 0 {
                    WidgetChainDayBadge(count: goal.chainDays)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 4)
            if goal.streak > 0 {
                (details ? Text("\(goal.streak) gün") : Text(verbatim: "\(goal.streak)"))
                    .font(WidgetTheme.meta)
                    .foregroundStyle(WidgetTheme.secondaryText)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, minHeight: spaced ? minHeight : nil, alignment: .leading)
        .contentShape(Rectangle())
        .goalChainAccessibility(goal)
    }
}

/// The small widget at accessibility text sizes: the first goal alone, its name allowed two lines.
struct GoalChainFocus: View {
    let goal: WidgetSnapshot.Goal

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                WidgetGoalRing(goal: goal)
                Spacer(minLength: 4)
                if goal.streak > 0 {
                    Text(verbatim: "\(goal.streak)")
                        .font(WidgetTheme.meta)
                        .foregroundStyle(WidgetTheme.secondaryText)
                }
            }
            Text(verbatim: goal.name)
                .font(WidgetTheme.name)
                .foregroundStyle(goal.isPending ? WidgetTheme.text : WidgetTheme.secondaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
        }
        .goalChainAccessibility(goal)
    }
}

extension View {
    /// One element per goal: its name, then its state, chain and chain days.
    fileprivate func goalChainAccessibility(_ goal: WidgetSnapshot.Goal) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: goal.name))
            .accessibilityValue(Text(GoalChainAccessibility.value(goal)))
    }
}

enum GoalChainAccessibility {
    static func value(_ goal: WidgetSnapshot.Goal) -> LocalizedStringKey {
        switch (goal.isPending, goal.chainDays > 0) {
        case (true, true): "Bekliyor. Güncel zincir: \(goal.streak). Zincir günü: \(goal.chainDays)"
        case (true, false): "Bekliyor. Güncel zincir: \(goal.streak)"
        case (false, true): "Yapıldı. Güncel zincir: \(goal.streak). Zincir günü: \(goal.chainDays)"
        case (false, false): "Yapıldı. Güncel zincir: \(goal.streak)"
        }
    }
}

/// The goal ring of the app (`GoalRing`), drawn small: an empty accent outline for an open goal,
/// an accent arc for a number goal on its way, a filled secondary disc once done.
struct WidgetGoalRing: View {
    let goal: WidgetSnapshot.Goal
    @ScaledMetric(relativeTo: .subheadline) private var side: CGFloat = 16

    var body: some View {
        ZStack {
            Circle().strokeBorder(goal.isPending ? WidgetTheme.accent : WidgetTheme.control, lineWidth: 1.5)
            if !goal.isPending {
                Circle().fill(WidgetTheme.secondaryText)
            } else if goal.kind == .number, goal.fraction > 0 {
                Circle()
                    .trim(from: 0, to: goal.fraction)
                    .stroke(WidgetTheme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(1.5)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// Chain-day balance, as the app's `GraceDayBadge`: a link glyph and the count in a thin capsule.
struct WidgetChainDayBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "link").imageScale(.small)
            Text(verbatim: "\(count)").monospacedDigit()
        }
        .font(WidgetTheme.meta)
        .foregroundStyle(WidgetTheme.secondaryText)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .overlay { Capsule(style: .circular).strokeBorder(WidgetTheme.control, lineWidth: 1) }
        .fixedSize()
        .accessibilityHidden(true)
    }
}
