import SwiftUI
import VaultFormat

struct DaysCalendarView: View {
    let store: IndexStore
    let select: (CalendarDate) -> Void
    @Environment(\.locale) private var locale
    @State private var month = LocalDay.today()
    private var model: JournalCalendar { JournalCalendar(month: month, days: store.content.days) }
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.locale = locale
        return result
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    month = model.adjacentMonth(-1)
                } label: {
                    Label("Önceki ay", systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                        .tapTarget()
                }
                Spacer()
                Text(LocalDay.instant(for: model.month), format: .dateTime.month(.wide).year()).font(.headline)
                Spacer()
                Button {
                    month = model.adjacentMonth(1)
                } label: {
                    Label("Sonraki ay", systemImage: "chevron.right")
                        .labelStyle(.iconOnly)
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
                    Text(verbatim: symbols[(weekday - 1 + offset) % 7]).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(cells.indices, id: \.self) { index in
                    if let day = cells[index] {
                        Button {
                            select(day)
                        } label: {
                            VStack(spacing: 2) {
                                Text(day.day, format: .number)
                                Circle().fill(model.markedDays.contains(day) ? Color.accentColor : Color.clear)
                                    .frame(width: 4, height: 4)
                            }
                            // Visual row was 30 pt; tap floor raises the laid-out cell to 44 pt on iOS.
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .tapTarget()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(LocalDay.instant(for: day), format: .dateTime.day().month().year()))
                        .accessibilityHint(model.markedDays.contains(day) ? Text("Günlük kaydı var") : Text("Boş gün"))
                    } else {
                        Color.clear.frame(height: 30)
                    }
                }
            }
        }.padding()
    }
}
