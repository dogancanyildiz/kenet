import SwiftUI

/// Day manşet: ring + day number + day name, with an optional action slot.
struct InkDayHeader<Actions: View>: View {
    var date: Date
    /// Remaining work fraction for the ring (0…1 remaining → progress = 1 − remaining share).
    /// Prefer passing ``progress`` as remaining/total inverted by the caller: accent shows remaining.
    var progress: Double
    /// Number drawn in the ring center (remaining count).
    var remainingCount: Int
    /// Compact single-row layout (scrolled / collapsed).
    var compact: Bool = false
    @ViewBuilder var actions: () -> Actions

    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var dayNumberSize = InkSize.largeNumber
    @ScaledMetric(relativeTo: .body) private var ringSide = InkSize.dayRing

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
            ring
            VStack(alignment: .leading, spacing: 2) {
                dayNumberText
                dayNameText
            }
            Spacer(minLength: 0)
            actionGroup
        }
    }

    private var compactLayout: some View {
        HStack(alignment: .center, spacing: 10) {
            ring
            dayNumberText
            dayNameText
            Spacer(minLength: 0)
            actionGroup
        }
    }

    private var ring: some View {
        GoalRing(
            progress: progress,
            diameter: ringSide,
            centerLabel: String(remainingCount)
        )
        .accessibilityLabel(Text(verbatim: "\(remainingCount)"))
    }

    private var dayNumberText: some View {
        Text(verbatim: dayNumber)
            .font(
                .system(
                    size: compact ? dayNumberSize * 0.7 : dayNumberSize, weight: .bold,
                    design: .default
                )
                .monospacedDigit()
            )
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
        date: Date, progress: Double, remainingCount: Int, compact: Bool = false
    ) {
        self.init(
            date: date, progress: progress, remainingCount: remainingCount, compact: compact
        ) { EmptyView() }
    }
}
