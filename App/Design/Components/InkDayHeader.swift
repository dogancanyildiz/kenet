import SwiftUI

/// Day manşet: ring + day number + day name, with an optional action slot.
struct InkDayHeader<Actions: View>: View {
    var date: Date
    /// Ring fill 0…1: the accent arc is the day's completed share; the ring center shows it as a
    /// percent ("67"), as in the drawing.
    var progress: Double
    /// Work left (VoiceOver: "3 hedef kaldı").
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

    /// Ring, then day number and day name on one baseline ("20 Pazar"), icons on the right.
    private var expandedLayout: some View {
        HStack(alignment: .center, spacing: 12) {
            if showsRing { ring }
            expandedTitle
                // Offered the row's free width before the spacer, so the widest fitting title wins.
                .layoutPriority(1)
            Spacer(minLength: 0)
            actionGroup
        }
    }

    /// The title gives way before the icons do: the full day name ("19 Cumartesi"), then the week
    /// strip's short name ("19 Cmt"), then the number alone. The number never wraps and no name is
    /// cut with an ellipsis. VoiceOver reads the full name whichever one is drawn.
    private var expandedTitle: some View {
        let names = InkDayHeaderTitle.names(for: date, calendar: calendar, locale: locale)
        return ViewThatFits(in: .horizontal) {
            ForEach(names.drawn, id: \.self) { name in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    dayNumberText.fixedSize()
                    dayNameText(name, spokenAs: names.full).fixedSize()
                }
            }
            dayNumberText.fixedSize()
                .accessibilityLabel(Text(verbatim: "\(dayNumber) \(names.full)"))
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
                dayNameText(fullDayName, spokenAs: fullDayName)
            }
            Spacer(minLength: 0)
            actionGroup
        }
    }

    private var fullDayName: String {
        InkDayHeaderTitle.names(for: date, calendar: calendar, locale: locale).full
    }

    private var ring: some View {
        GoalRing(
            progress: progress,
            diameter: ringSide,
            centerLabel: String(DayRingLabel.percent(progress)),
            emphasizesArc: true
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

    private func dayNameText(_ name: String, spokenAs full: String) -> some View {
        Text(verbatim: name)
            .font(.ink.dayName)
            .foregroundStyle(Color.ink.secondaryText)
            .lineLimit(1)
            .accessibilityLabel(Text(verbatim: full))
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

/// The day names the manşet title may draw (unit-tested).
enum InkDayHeaderTitle {
    struct Names: Equatable {
        /// "Cumartesi": drawn first and always what VoiceOver reads.
        var full: String
        /// Names in the order the title tries them: the full one, then the week strip's short one
        /// ("Cmt") when it differs.
        var drawn: [String]
    }

    static func names(for date: Date, calendar: Calendar, locale: Locale) -> Names {
        let full = InkWeekStrip.makeFormatter(template: "EEEE", calendar: calendar, locale: locale)
            .string(from: date)
        // Same template as the week strip's cells, so the two never disagree.
        let short = InkWeekStrip.makeFormatter(template: "EEE", calendar: calendar, locale: locale)
            .string(from: date)
        return Names(full: full, drawn: short == full ? [full] : [full, short])
    }
}

/// The number in the day ring: the completed share as a whole percent (unit-tested).
enum DayRingLabel {
    static func percent(_ progress: Double) -> Int {
        Int((GoalRingProgress.clamped(progress) * 100).rounded())
    }
}
