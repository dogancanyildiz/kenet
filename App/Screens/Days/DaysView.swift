import SwiftUI

/// Reverse chronological summaries lead into the shared day layout.
struct DaysView: View {
    let store: IndexStore

    var body: some View {
        List(store.content.days) { day in
            NavigationLink {
                DayView(store: store, date: day.date)
            } label: {
                DayRow(day: day)
            }
        }
        .overlay {
            if store.content.days.isEmpty {
                ContentUnavailableView(
                    "Henüz gün yok", systemImage: "book.closed", description: Text("Günlerin burada görünecek."))
            }
        }
        .navigationTitle("Günlük")
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
    }
}
