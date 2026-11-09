import SwiftUI

/// Day manşet: optional ring + day number + day name, with an action slot.
struct InkDayHeader<Actions: View>: View {
    var date: Date
    /// Remaining work fraction for the ring (completed/total). Ignored when ``showsRing`` is false.
    var progress: Double
    /// Number drawn in the ring center (remaining count).
    var remainingCount: Int
    /// Hide the ring when the day has no daily goals.
    var showsRing: Bool = true
    /// Compact single-row layout (scrolled / collapsed): small ring + ``compactTitle``.
    var compact: Bool = false
    /// Compact title ("20 Eylül Pazar"); falls back to day number + weekday when nil.
    var compactTitle: String? = nil
    @ViewBuilder var actions: () -> Actions

    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var dayNumberSize = InkSize.largeNumber
    @ScaledMetric(relativeTo: .body) private var ringSide = InkSize.dayRing
    @ScaledMetric(relativeTo: .body) private var compactRingSide = InkSize.goalRing

    var body: some View {
        Group {
            if compact || dynamicTypeSize.isAccessibilitySize {
                compactLayout
            } else {
                expandedLayout
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var expandedLayout: some View {
        HStack(alignment: .center, spacing: 12) {
            if showsRing { ring(side: ringSide) }
            VStack(alignment: .leading, spacing: 2) {
                dayNumberText(size: dayNumberSize)
                dayNameText
            }
            Spacer(minLength: 0)
            actionGroup
        }
    }

    private var compactLayout: some View {
        HStack(alignment: .center, spacing: 10) {
            if showsRing { ring(side: compactRingSide) }
            if let compactTitle, !compactTitle.isEmpty {
                Text(verbatim: compactTitle)
                    .font(.ink.dayName)
                    .foregroundStyle(Color.ink.text)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
            } else {
                dayNumberText(size: dayNumberSize * 0.7)
                dayNameText
            }
            Spacer(minLength: 0)
            actionGroup
        }
    }

    private func ring(side: CGFloat) -> some View {
        GoalRing(
            progress: progress,
            diameter: side,
            centerLabel: String(remainingCount)
        )
        .accessibilityLabel(
            Text(
                verbatim: TodayDayRing.accessibilityLabel(
                    remaining: remainingCount, locale: locale)))
    }

    private func dayNumberText(size: CGFloat) -> some View {
        Text(verbatim: dayNumber)
            .font(.system(size: size, weight: .bold, design: .default).monospacedDigit())
            .foregroundStyle(Color.ink.text)
            .accessibilityAddTraits(.isHeader)
    }

    private var dayNameText: some View {
        Text(verbatim: dayName)
            .font(.ink.dayName)
            .foregroundStyle(Color.ink.secondaryText)
            .lineLimit(1)
    }

    private var actionGroup: some View {
        actions()
            .buttonStyle(InkHeaderButtonStyle())
            .environment(\.isInkHeaderActionSlot, true)
    }

    private var dayNumber: String {
        String(calendar.component(.day, from: date))
    }

    private var dayName: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
        return formatter.string(from: date)
    }
}

extension InkDayHeader where Actions == EmptyView {
    init(
        date: Date, progress: Double, remainingCount: Int, showsRing: Bool = true,
        compact: Bool = false, compactTitle: String? = nil
    ) {
        self.init(
            date: date, progress: progress, remainingCount: remainingCount, showsRing: showsRing,
            compact: compact, compactTitle: compactTitle
        ) { EmptyView() }
    }
}
