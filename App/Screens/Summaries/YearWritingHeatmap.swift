import Summaries
import SwiftUI
import VaultFormat

/// "Yazılan günler" of the Özetler year: one row per month, one cell per date (1–31).
/// Dates the month lacks and days after today are not drawn. Accessibility sizes switch to large
/// cells in Monday weeks that scroll sideways and open on the last measured week.
struct YearWritingHeatmap: View {
    let calendar: YearWritingCalendar
    let today: CalendarDate
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .footnote) private var gutter: CGFloat = 18
    @ScaledMetric(relativeTo: .footnote) private var rowHeight: CGFloat = 14
    @ScaledMetric(relativeTo: .footnote) private var monthGutter: CGFloat = 32
    @State private var width: CGFloat = 350

    private let gap: CGFloat = 2
    /// Widest month-row cell; a narrow column shrinks it so that 31 days always fit.
    private let maxRowCell: CGFloat = 9
    private var bundle: Bundle { PresentationLocalization.bundle(locale) }
    private var year: Int { calendar.year }
    private var measuredMonths: [YearWritingCalendar.Month] { calendar.months.filter { !$0.days.isEmpty } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: String(localized: "Yazılan günler", bundle: bundle, locale: locale),
                counter: String(localized: "\(calendar.writtenDays) gün", bundle: bundle, locale: locale))
            Group {
                if dynamicTypeSize.isAccessibilitySize { scrollingWeeks } else { monthRows }
            }
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                width = $0
            }
            // One element per month instead of up to 366 cells.
            .accessibilityRepresentation {
                VStack {
                    ForEach(measuredMonths, id: \.month) { month in
                        let name = monthName(month.month, abbreviated: false)
                        Text(
                            verbatim: String(
                                localized: "\(name): \(month.writtenDays) gün yazıldı", bundle: bundle, locale: locale)
                        )
                    }
                }
            }
            legend
        }
    }

    private func kind(_ day: CalendarDate) -> HeatmapCellKind {
        switch calendar.day(day) {
        case nil: .future
        case .unwritten?: .empty
        case .journal?: .partial
        case .events?: .full
        }
    }

    private func cell(_ day: CalendarDate, size: CGFloat) -> some View {
        HeatmapCell(kind: kind(day), size: size, isToday: day == today, accessibilityValue: Text(verbatim: ""))
    }

    // MARK: Month rows

    private var monthRows: some View {
        let spacing: CGFloat = 1
        let size = max(1, min(maxRowCell, (width - monthGutter - 31 * spacing) / 31))
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(1...12, id: \.self) { month in
                HStack(spacing: spacing) {
                    Text(verbatim: monthName(month, abbreviated: true))
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: monthGutter, alignment: .leading)
                    ForEach(1...31, id: \.self) { number in
                        if let day = CalendarDate(year: year, month: month, day: number) {
                            cell(day, size: size)
                        } else {
                            Color.clear.frame(width: size, height: size)
                        }
                    }
                }
                .frame(height: rowHeight)
            }
        }
    }

    // MARK: Accessibility sizes

    private var start: CalendarDate? { CalendarDate(year: year, month: 1, day: 1) }

    /// Monday weeks from the one holding 1 January to the one holding the last measured day.
    private var weeks: [[CalendarDate]] {
        guard let first = start?.startOfWeek, let last = calendar.measuredEnd else { return [] }
        var result: [[CalendarDate]] = []
        var cursor = first
        while cursor <= last {
            result.append((0..<7).compactMap { cursor.addingDays($0) })
            guard let next = cursor.addingDays(7) else { break }
            cursor = next
        }
        return result
    }

    /// Six weeks fill the width.
    private var weekCell: CGFloat { max(14, floor((width - gutter - gap) / 6) - gap) }
    private var weekPitch: CGFloat { weekCell + gap }
    private var weekRow: CGFloat { max(weekCell, rowHeight) }

    private var scrollingWeeks: some View {
        let weeks = weeks
        return HStack(alignment: .top, spacing: gap) {
            VStack(spacing: gap) {
                Color.clear.frame(height: rowHeight)
                weekdayLabels
            }
            .frame(width: gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: gap) {
                    monthLabels(weeks)
                    HStack(alignment: .top, spacing: gap) {
                        ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                            VStack(spacing: gap) {
                                ForEach(week, id: \.self) { day in
                                    cell(day, size: weekCell)
                                        .frame(height: weekRow)
                                }
                            }
                        }
                    }
                }
            }
            .defaultScrollAnchor(.trailing)
        }
    }

    /// A label begins at its month's first whole Monday week and spans up to the next one.
    /// The last month may have too little room; its label is then left out.
    private func monthLabels(_ weeks: [[CalendarDate]]) -> some View {
        let starts = weeks.indices.filter { index in
            guard let first = weeks[index].first else { return false }
            return first.year == year && first.day <= 7
        }
        return HStack(spacing: 0) {
            if let first = starts.first {
                Color.clear.frame(width: CGFloat(first) * weekPitch)
            }
            ForEach(Array(starts.enumerated()), id: \.offset) { offset, index in
                let next = offset + 1 < starts.count ? starts[offset + 1] : weeks.count
                let span = CGFloat(next - index) * weekPitch
                ViewThatFits(in: .horizontal) {
                    Text(verbatim: monthName(weeks[index][0].month, abbreviated: true))
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                        .fixedSize()
                    Color.clear.frame(width: 0)
                }
                .frame(width: max(0, span - gap), height: rowHeight, alignment: .leading)
                .padding(.trailing, gap)
                .clipped()
            }
        }
        .frame(height: rowHeight)
        .accessibilityHidden(true)
    }

    private var weekdayLabels: some View {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.locale = locale
        let symbols = gregorian.veryShortStandaloneWeekdaySymbols
        // Monday first, as the weeks are.
        let ordered = Array(symbols.dropFirst()) + [symbols[0]]
        return VStack(spacing: gap) {
            ForEach(0..<7, id: \.self) { index in
                Text(verbatim: ordered[index])
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .frame(width: gutter, height: weekRow, alignment: .trailing)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Shared

    private func monthName(_ month: Int, abbreviated: Bool) -> String {
        guard let date = CalendarDate(year: year, month: month, day: 1) else { return "" }
        return LocalDay.instant(for: date).formatted(
            Date.FormatStyle(locale: locale).month(abbreviated ? .abbreviated : .wide))
    }

    private var legend: some View {
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(InkFlowLayout(spacing: 12, lineSpacing: 8))
        return layout {
            legendItem(.empty, "Yazılmadı")
            legendItem(.partial, "Günlük yazısı")
            legendItem(.full, "Olaylı gün")
        }
        .accessibilityElement(children: .combine)
    }

    private func legendItem(_ kind: HeatmapCellKind, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            HeatmapCell(kind: kind, size: 10, accessibilityValue: Text(verbatim: ""))
                .accessibilityHidden(true)
            Text(title).font(.ink.meta).foregroundStyle(Color.ink.secondaryText)
        }
    }
}
