import SwiftUI
import VaultFormat

struct DaysCalendarView: View {
    let store: IndexStore
    var selected: CalendarDate? = nil
    let select: (CalendarDate) -> Void
    @Environment(\.locale) private var locale
    @Environment(\.clockNow) private var clockNow
    @State private var month: CalendarDate?
    /// The last month whose days were queried. Until the asked month's answer arrives it stays on
    /// screen, so the grid never shows a month without its marks; before the first answer the
    /// days are not drawn.
    @State private var loaded: JournalCalendar?
    private var resolvedMonth: CalendarDate { month ?? LocalDay.today(at: clockNow()) }
    private var model: JournalCalendar {
        loaded ?? JournalCalendar(month: resolvedMonth, days: [])
    }
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.locale = locale
        return result
    }
    private var today: CalendarDate { LocalDay.today(at: clockNow()) }
    private var monthRequest: DayRangeRequest {
        let range = JournalCalendar.range(of: resolvedMonth)
        return DayRangeRequest(from: range.lowerBound, to: range.upperBound, updated: store.lastUpdated)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                // From the asked month, not the one on screen: a second tap before the first
                // month's answer arrives moves on instead of asking for the same month again.
                Button {
                    month = JournalCalendar(month: resolvedMonth, days: []).adjacentMonth(-1)
                } label: {
                    Label("Önceki ay", systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.ink.accent)
                        .tapTarget()
                }
                Spacer()
                Text(LocalDay.instant(for: model.month), format: .dateTime.month(.wide).year())
                    .font(.ink.section)
                    .foregroundStyle(.ink.text)
                Spacer()
                Button {
                    month = JournalCalendar(month: resolvedMonth, days: []).adjacentMonth(1)
                } label: {
                    Label("Sonraki ay", systemImage: "chevron.right")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.ink.accent)
                        .tapTarget()
                }
            }
            // Inside a List row every bordered button fires on one tap; borderless keeps them separate.
            .buttonStyle(.borderless)
            let symbols = calendar.veryShortStandaloneWeekdaySymbols
            let weekday = calendar.firstWeekday
            let cells = model.cells(firstWeekday: weekday)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7)) {
                ForEach(0..<7, id: \.self) { offset in
                    Text(verbatim: symbols[(weekday - 1 + offset) % 7])
                        .font(.ink.meta)
                        .foregroundStyle(.ink.secondaryText)
                }
                ForEach(cells.indices, id: \.self) { index in
                    if let day = cells[index] {
                        let isToday = day == today
                        let level = model.level(for: day)
                        let isSelected = day == selected
                        Button {
                            select(day)
                        } label: {
                            DaysCalendarDayMark(
                                day: day.day, level: level, isToday: isToday, isSelected: isSelected
                            )
                            .tapTarget()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            Text(LocalDay.instant(for: day), format: .dateTime.day().month().year())
                        )
                        .accessibilityHint(level > 0 ? Text("Günlük kaydı var") : Text("Boş gün"))
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        // Until the first answer the days keep their place but are not drawn:
                        // a month drawn without its marks would flash them in a moment later.
                        .opacity(loaded == nil ? 0 : 1)
                        .accessibilityHidden(loaded == nil)
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }
        }.padding(.vertical, 4)
            .onAppear {
                if month == nil { month = LocalDay.today(at: clockNow()) }
            }
            .task(id: monthRequest) {
                let asked = resolvedMonth
                let range = JournalCalendar.range(of: asked)
                if let days = try? await store.computeDaySummaries(from: range.lowerBound, to: range.upperBound) {
                    loaded = JournalCalendar(month: asked, days: days)
                }
            }
    }
}

/// Caps the preferred (Dynamic Type–scaled) mark so it never exceeds the grid cell.
enum DaysCalendarMarkLayout {
    static func markDiameter(preferred: CGFloat, cellWidth: CGFloat) -> CGFloat {
        min(preferred, max(0, cellWidth))
    }

    /// Minimum gap between the day numeral and today's ring / selected disc.
    static let numeralInset: CGFloat = 2

    /// Diameter of each density dot marker.
    static let dotDiameter: CGFloat = 4

    /// Spacing between density dots.
    static let dotSpacing: CGFloat = 2

    /// Width of the density dots for a given level (0–3).
    static func dotsWidth(for level: Int) -> CGFloat {
        let count = min(max(0, level), 3)
        guard count > 0 else { return 0 }
        return CGFloat(count) * dotDiameter + CGFloat(count - 1) * dotSpacing
    }

    /// Square padding so the numeral's layout box fits inside the circle with ``numeralInset``
    /// clearance to the inner edge of the stroke (not merely to the square frame).
    static func numeralInset(diameter: CGFloat, strokeWidth: CGFloat = InkStroke.control) -> CGFloat {
        let gap = numeralInset
        let innerRadius = max(0, diameter / 2 - strokeWidth / 2)
        let maxHalfDiagonal = max(0, innerRadius - gap)
        let contentSide = maxHalfDiagonal * CGFloat(2).squareRoot()
        return max(gap, (diameter - contentSide) / 2)
    }
}

/// Day cell: today = ring, marked = 1–3 density dots, selected = filled disc (form beyond color).
struct DaysCalendarDayMark: View {
    let day: Int
    let level: Int
    let isToday: Bool
    let isSelected: Bool
    var isMarked: Bool { level > 0 }
    @ScaledMetric(relativeTo: .body) private var preferredDiameter = 32.0

    init(day: Int, level: Int = 0, isToday: Bool = false, isSelected: Bool = false) {
        self.day = day
        self.level = level
        self.isToday = isToday
        self.isSelected = isSelected
    }

    init(day: Int, isToday: Bool, isMarked: Bool, isSelected: Bool) {
        self.init(day: day, level: isMarked ? 1 : 0, isToday: isToday, isSelected: isSelected)
    }

    nonisolated static func accessibilityValueText(
        level: Int, isToday: Bool, isSelected: Bool
    ) -> String {
        [
            isToday ? String(localized: "Bugün") : nil,
            level > 0 ? String(localized: "Yoğunluk \(level) / 3") : nil,
            isSelected ? String(localized: "Seçili") : nil,
        ].compactMap { $0 }.joined(separator: ", ")
    }

    var body: some View {
        GeometryReader { geo in
            let diameter = DaysCalendarMarkLayout.markDiameter(
                preferred: preferredDiameter, cellWidth: geo.size.width)
            VStack(spacing: 2) {
                Text(day, format: .number)
                    .font(.ink.value)
                    .foregroundStyle(isSelected ? Color.ink.onAccent : Color.ink.text)
                    .minimumScaleFactor(0.35)
                    .lineLimit(1)
                    // Only cells that draw a ring or disc need clearance; plain days keep full size.
                    .padding(
                        isToday || isSelected
                            ? DaysCalendarMarkLayout.numeralInset(diameter: diameter) : 0
                    )
                    .frame(width: diameter, height: diameter)
                    .background {
                        if isSelected {
                            Circle().fill(Color.ink.accent)
                        } else if isToday {
                            Circle().strokeBorder(Color.ink.accent, lineWidth: InkStroke.control)
                        }
                    }
                Group {
                    if level > 0 {
                        HStack(spacing: DaysCalendarMarkLayout.dotSpacing) {
                            ForEach(0..<min(level, 3), id: \.self) { _ in
                                if isSelected {
                                    // Selected already fills; mark with a square so form differs from the disc.
                                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                                        .fill(Color.ink.accent)
                                        .frame(
                                            width: DaysCalendarMarkLayout.dotDiameter,
                                            height: DaysCalendarMarkLayout.dotDiameter)
                                } else {
                                    Circle()
                                        .fill(Color.ink.accent)
                                        .frame(
                                            width: DaysCalendarMarkLayout.dotDiameter,
                                            height: DaysCalendarMarkLayout.dotDiameter)
                                }
                            }
                        }
                        .frame(height: DaysCalendarMarkLayout.dotDiameter)
                    } else {
                        Color.clear.frame(height: DaysCalendarMarkLayout.dotDiameter)
                    }
                }
                .accessibilityHidden(true)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .accessibilityValue(
            Text(
                verbatim: Self.accessibilityValueText(
                    level: level, isToday: isToday, isSelected: isSelected)))
    }
}
