import SwiftUI
import VaultFormat

struct DaysCalendarView: View {
    let store: IndexStore
    var selected: CalendarDate? = nil
    let select: (CalendarDate) -> Void
    @Environment(\.locale) private var locale
    @Environment(\.clockNow) private var clockNow
    @State private var month: CalendarDate?
    private var resolvedMonth: CalendarDate { month ?? LocalDay.today(at: clockNow()) }
    private var model: JournalCalendar {
        JournalCalendar(month: resolvedMonth, days: store.content.days)
    }
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.locale = locale
        return result
    }
    private var today: CalendarDate { LocalDay.today(at: clockNow()) }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    month = model.adjacentMonth(-1)
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
                    month = model.adjacentMonth(1)
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
                        let isMarked = model.markedDays.contains(day)
                        let isSelected = day == selected
                        Button {
                            select(day)
                        } label: {
                            DaysCalendarDayMark(
                                day: day.day, isToday: isToday, isMarked: isMarked, isSelected: isSelected
                            )
                            .tapTarget()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            Text(LocalDay.instant(for: day), format: .dateTime.day().month().year())
                        )
                        .accessibilityHint(isMarked ? Text("Günlük kaydı var") : Text("Boş gün"))
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }
        }.padding(.vertical, 4)
            .onAppear {
                if month == nil { month = LocalDay.today(at: clockNow()) }
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

/// Day cell: today = ring, marked = filled marker, selected = filled disc (form beyond color).
struct DaysCalendarDayMark: View {
    let day: Int
    let isToday: Bool
    let isMarked: Bool
    let isSelected: Bool
    @ScaledMetric(relativeTo: .body) private var preferredDiameter = 32.0

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
                    .padding(DaysCalendarMarkLayout.numeralInset(diameter: diameter))
                    .frame(width: diameter, height: diameter)
                    .background {
                        if isSelected {
                            Circle().fill(Color.ink.accent)
                        } else if isToday {
                            Circle().strokeBorder(Color.ink.accent, lineWidth: InkStroke.control)
                        }
                    }
                Group {
                    if isMarked {
                        if isSelected {
                            // Selected already fills; mark with a square so form differs from the disc.
                            RoundedRectangle(cornerRadius: 1, style: .continuous)
                                .fill(Color.ink.accent)
                                .frame(width: 4, height: 4)
                        } else {
                            Circle()
                                .fill(Color.ink.accent)
                                .frame(width: 4, height: 4)
                        }
                    } else {
                        Color.clear.frame(width: 4, height: 4)
                    }
                }
                .accessibilityHidden(true)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .accessibilityValue(
            Text(
                verbatim: [
                    isToday ? String(localized: "Bugün") : nil,
                    isMarked ? String(localized: "Günlük kaydı var") : nil,
                    isSelected ? String(localized: "Seçili") : nil,
                ].compactMap { $0 }.joined(separator: ", ")))
    }
}
