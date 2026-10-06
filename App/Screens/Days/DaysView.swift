import SwiftUI
import VaultFormat

/// Reverse chronological summaries lead into the shared day layout.
struct DaysView: View {
    let store: IndexStore
    @State private var selectedDay: CalendarDate?

    var body: some View {
        List {
            NavigationLink {
                SummariesView(store: store)
            } label: {
                Label("Özetler", systemImage: "chart.bar")
            }
            Section {
                DaysCalendarView(store: store) { selectedDay = $0 }
            }
            ForEach(store.content.days) { day in
                NavigationLink {
                    DayView(store: store, date: day.date)
                } label: {
                    DayRow(day: day)
                }
            }
            if store.content.days.isEmpty { Text("Henüz gün yok").foregroundStyle(.secondary) }
        }
        .navigationDestination(item: $selectedDay) { day in DayView(store: store, date: day) }
        .navigationTitle("Günlük")
        .accessibilityIdentifier("screen.days")
        .toolbar { SearchButton() }
    }
}

struct DayRow: View {
    let day: DaySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalDay.instant(for: day.date), format: .dateTime.day().month().year())
            Text("Olaylar: \(day.events.count)").font(.caption).foregroundStyle(.secondary)
            if let preview = day.preview {
                Text(verbatim: preview).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text(
                verbatim: VoiceOverCopy.dayRowLabel(
                    date: day.date, eventCount: day.events.count, preview: day.preview)))
    }
}
