import SwiftUI

/// Day manşet: ring + day number + day name, with an optional action slot.
struct InkDayHeader<Actions: View>: View {
    var date: Date
    /// Ring fill 0…1; accent arc shows remaining work (caller passes remaining/total).
    var progress: Double
    /// Number drawn in the ring center (remaining count).
    var remainingCount: Int
    /// Hide the ring when the day has no daily goals (screens.md).
    var showsRing: Bool = true
    /// Compact single-row layout (scrolled / collapsed).
    var compact: Bool = false
    /// Compact title ("20 Eylül Pazar"); falls back to day number + day name when nil.
    var compactTitle: String? = nil
    @ViewBuilder var actions: () -> Actions

    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Design table: 48 on iPhone, 34 on Mac; scales with Dynamic Type.
    #if os(macOS)
        @ScaledMetric(relativeTo: .largeTitle) private var dayNumberSize: CGFloat = 34
    #else
        @ScaledMetric(relativeTo: .largeTitle) private var dayNumberSize = InkSize.largeNumber
    #endif
    @ScaledMetric(relativeTo: .body) private var ringSide = InkSize.dayRing

    private var dayNameFormatter: DateFormatter {
        InkWeekStrip.makeFormatter(template: "EEEE", calendar: calendar, locale: locale)
    }

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
            if showsRing { ring }
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
            if showsRing { ring }
            if let compactTitle, !compactTitle.isEmpty {
                Text(verbatim: compactTitle)
                    .font(.ink.dayName)
                    .foregroundStyle(Color.ink.text)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
            } else {
                dayNumberText
                dayNameText
            }
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
        .accessibilityLabel(
            Text(
                verbatim: TodayDayRing.accessibilityLabel(
                    remaining: remainingCount, locale: locale)))
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
        Text(verbatim: dayNameFormatter.string(from: date))
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
