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
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    /// Design table: 48 on iPhone, 34 on Mac; scales with Dynamic Type.
    #if os(macOS)
        @ScaledMetric(relativeTo: .largeTitle) private var dayNumberSize: CGFloat = 34
    #else
        @ScaledMetric(relativeTo: .largeTitle) private var dayNumberSize = InkSize.largeNumber
    #endif
    @ScaledMetric(relativeTo: .body) private var ringSide = InkSize.dayRing

    var body: some View {
        Group {
            switch InkDayHeaderLayout.resolve(
                compact: compact, dynamicTypeSize: dynamicTypeSize, isWide: isWide)
            {
            case .singleRow: compactLayout
            case .fitted: fittedLayout(triesOneRow: true)
            case .stacked: fittedLayout(triesOneRow: false)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var isWide: Bool {
        #if os(iOS)
            horizontalSizeClass == .regular
        #else
            false
        #endif
    }

    /// The first arrangement that fits the row's width, so the page never grows wider than the
    /// screen. One row gives way title first: the full day name ("19 Cumartesi"), then the week
    /// strip's short name ("19 Cmt"), then the number alone. When the icons leave no room even
    /// for the number, or at an accessibility text size, the icons move to a row above the title.
    /// The number never wraps and no name is cut with an ellipsis.
    private func fittedLayout(triesOneRow: Bool) -> some View {
        let names = InkDayHeaderTitle.names(for: date, calendar: calendar, locale: locale)
        return ViewThatFits(in: .horizontal) {
            if triesOneRow {
                ForEach(names.drawn, id: \.self) { name in
                    expandedRow { numberAndName(name, spokenAs: names.full) }
                }
                expandedRow { numberAlone(spokenAs: names.full) }
            }
            stackedLayout(names)
        }
    }

    /// Ring, then day number and day name on one baseline ("20 Pazar"), icons on the right.
    private func expandedRow(@ViewBuilder title: () -> some View) -> some View {
        HStack(alignment: .center, spacing: 12) {
            if showsRing { ring }
            title()
            Spacer(minLength: 0)
            actionGroup
        }
    }

    /// Large text: the ring and the icons above, the day number and its name below at the row's
    /// full width. The icons stop growing at ``InkDayHeaderLayout/largestActionSize`` so three of
    /// them fit the narrowest phone; when the ring leaves them no room they take their own row.
    private func stackedLayout(_ names: InkDayHeaderTitle.Names) -> some View {
        VStack(alignment: .leading, spacing: InkSpacing.row) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    if showsRing { ring }
                    Spacer(minLength: 0)
                    stackedActions
                }
                VStack(alignment: .leading, spacing: InkSpacing.row) {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        stackedActions
                    }
                    if showsRing { ring }
                }
            }
            ViewThatFits(in: .horizontal) {
                ForEach(names.drawn, id: \.self) { name in
                    numberAndName(name, spokenAs: names.full)
                }
                numberAlone(spokenAs: names.full)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stackedActions: some View {
        HStack(spacing: InkHeaderActionChrome.spacing) { actionGroup }
            .dynamicTypeSize(...InkDayHeaderLayout.largestActionSize)
    }

    private func numberAndName(_ name: String, spokenAs full: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            dayNumberText.fixedSize()
            dayNameText(name, spokenAs: full).fixedSize()
        }
    }

    /// VoiceOver reads the full name whichever title is drawn.
    private func numberAlone(spokenAs full: String) -> some View {
        dayNumberText.fixedSize()
            .accessibilityLabel(Text(verbatim: "\(dayNumber) \(full)"))
    }

    /// One row with the compact title ("20 Eyl Pazar"): the collapsed header, and the iPad page at
    /// an accessibility text size.
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

/// Which arrangement the day manşet draws (unit-tested).
enum InkDayHeaderLayout: Equatable, Sendable {
    /// One row with the compact title; a title too long for it is cut.
    case singleRow
    /// One row while the day number fits beside the icons, else ``stacked``.
    case fitted
    /// The icons on a row above the day number.
    case stacked

    /// The manşet icons stop growing here once they sit on their own row (the app's cap for
    /// controls, as in the quick entry): three chips then fit a 320 pt screen.
    static let largestActionSize = DynamicTypeSize.accessibility2

    /// - Parameter isWide: regular-width iOS page (iPad), whose row has room for the compact title.
    static func resolve(compact: Bool, dynamicTypeSize: DynamicTypeSize, isWide: Bool) -> Self {
        if compact { return .singleRow }
        guard dynamicTypeSize.isAccessibilitySize else { return .fitted }
        return isWide ? .singleRow : .stacked
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
