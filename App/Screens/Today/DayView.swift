import SwiftUI
import VaultFormat

/// The same read-only layout serves today and a selected historical day.
struct DayView: View {
    let store: IndexStore
    let date: CalendarDate
    var isToday = false
    @Environment(\.locale) private var locale

    private var day: DaySummary { store.content.day(on: date) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if store.isProcessing && !store.isWriting { ProgressView("İndeks güncelleniyor…") }
                if let error = store.errorText { Text(verbatim: error).foregroundStyle(.red) }
                if day.events.isEmpty && day.journal.isEmpty {
                    Group {
                        if isToday {
                            Text("Bugün henüz bir şey yazılmadı.")
                        } else {
                            Text("Bu gün henüz bir şey yazılmadı.")
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                if !day.events.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Olaylar").font(.headline).accessibilityAddTraits(.isHeader)
                        ForEach(day.events) { event in
                            VStack(alignment: .leading, spacing: 4) {
                                if let time = event.time {
                                    Text(
                                        LocalDay.instant(for: date, time: time, timeZone: .gmt),
                                        format: Date.FormatStyle(
                                            date: .omitted, time: .shortened, locale: locale, timeZone: .gmt)
                                    )
                                    .font(.subheadline).foregroundStyle(.secondary)
                                }
                                LinkedTextView(text: event.text, store: store)
                            }
                        }
                    }
                }
                if !day.journal.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Günlük yazısı").font(.headline).accessibilityAddTraits(.isHeader)
                        NavigationLink {
                            JournalView(store: store, date: date)
                        } label: {
                            Text(verbatim: day.preview ?? day.journal[0].text.plainText)
                                .lineLimit(4).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .accessibilityLabel("Günlük yazısını oku")
                    }
                }
            }
            .padding().frame(maxWidth: 700, alignment: .leading).frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) { QuickEntryBar(store: store, isEnabled: isToday) }
        .navigationTitle(
            isToday ? Text("Bugün") : Text(LocalDay.instant(for: date), format: .dateTime.day().month().year())
        )
        .toolbar { SearchButton() }
    }
}

/// Recomputes the local day across midnight without reopening the app.
struct TodayView: View {
    let store: IndexStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            DayView(store: store, date: LocalDay.today(at: context.date), isToday: true)
        }
    }
}
