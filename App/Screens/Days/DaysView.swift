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
                MarginRow(kind: .external, time: nil) {
                    Label("Özetler", systemImage: "chart.bar")
                        .font(.body)
                        .foregroundStyle(.ink.text)
                }
            }
            Section {
                DaysCalendarView(store: store, selected: selectedDay) { selectedDay = $0 }
            }
            ForEach(store.content.days) { day in
                NavigationLink {
                    DayView(store: store, date: day.date)
                } label: {
                    DayRow(day: day)
                }
            }
            if store.content.days.isEmpty {
                EmptyState("Henüz gün yok")
            }
        }
        .listStyle(.plain)
        .inkPage()
        .navigationDestination(item: $selectedDay) { day in DayView(store: store, date: day) }
        .navigationTitle("Günlük")
        .accessibilityIdentifier("screen.days")
        .toolbar { SearchButton() }
    }
}

struct DayRow: View {
    let day: DaySummary

    var body: some View {
        MarginRow(kind: .vault, time: nil) {
            Text(LocalDay.instant(for: day.date), format: .dateTime.day().month().year())
                .foregroundStyle(.ink.text)
        } secondary: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Olaylar: \(day.events.count)")
                    .font(.ink.meta)
                    .foregroundStyle(.ink.secondaryText)
                if let preview = day.preview {
                    Text(verbatim: VaultDisplayText.line(preview))
                        .font(.ink.meta)
                        .foregroundStyle(.ink.secondaryText)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text(
                verbatim: VoiceOverCopy.dayRowLabel(
                    date: day.date, eventCount: day.events.count, preview: day.preview)))
    }
}
