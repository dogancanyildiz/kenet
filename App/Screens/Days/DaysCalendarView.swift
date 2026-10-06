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

/// Day cell: today = ring, marked = filled marker, selected = filled disc (form beyond color).
struct DaysCalendarDayMark: View {
    let day: Int
    let isToday: Bool
    let isMarked: Bool
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(Color.ink.accent)
                        .frame(width: 32, height: 32)
                } else if isToday {
                    Circle()
                        .strokeBorder(Color.ink.accent, lineWidth: InkStroke.control)
                        .frame(width: 32, height: 32)
                }
                Text(day, format: .number)
                    .font(.ink.value)
                    .foregroundStyle(isSelected ? Color.ink.onAccent : Color.ink.text)
                    .minimumScaleFactor(0.35)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .frame(minWidth: 28, minHeight: 28)
            .frame(maxWidth: .infinity)
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
