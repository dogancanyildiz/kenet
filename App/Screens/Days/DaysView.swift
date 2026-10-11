import SwiftUI
import VaultFormat

/// Reverse chronological summaries lead into the shared day layout.
struct DaysView: View {
    let store: IndexStore
    var previewSelectedDay: CalendarDate? = nil
    @State private var selectedDay: CalendarDate?
    @State private var showsWeeklyReview = false
    @State private var weeklyReviewNotice: WeeklyReviewNotice?

    var body: some View {
        List {
            InkPageTitleRow("Günlük") {
                SearchButton()
            }
            NavigationLink {
                SummariesView(store: store)
            } label: {
                MarginRow(kind: .external, time: nil) {
                    Label("Özetler", systemImage: "chart.bar")
                        .font(.body)
                        .foregroundStyle(.ink.text)
                }
            }
            .inkListRow()
            // Opens a sheet, not a page: a button in the same row skeleton, without the chevron.
            Button {
                showsWeeklyReview = true
            } label: {
                MarginRow(kind: .external, time: nil) {
                    Label("Haftalık inceleme", systemImage: "checklist")
                        .font(.body)
                        .foregroundStyle(.ink.text)
                } secondary: {
                    WeeklyReviewEntryStatus()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("button.weeklyReview")
            .inkListRow()
            if let notice = weeklyReviewNotice {
                InfoBand(kind: notice.kind, verbatim: notice.text, onDismiss: { weeklyReviewNotice = nil })
                    .inkListRow()
            }
            Section {
                DaysCalendarView(
                    store: store, selected: selectedDay ?? previewSelectedDay
                ) { selectedDay = $0 }
                .inkListRow()
            }
            ForEach(store.content.days) { day in
                NavigationLink {
                    DayView(store: store, date: day.date)
                } label: {
                    DayRow(day: day)
                }
                .inkListRow()
            }
            if store.content.days.isEmpty {
                EmptyState("Henüz gün yok")
                    .inkListRow()
            }
        }
        .listStyle(.plain)
        .inkPage()
        .inkPageScrollColumn()
        .navigationDestination(item: $selectedDay) { day in DayView(store: store, date: day) }
        .weeklyReviewSheet(isPresented: $showsWeeklyReview, store: store) { weeklyReviewNotice = $0 }
        .inkRootPageNavigationTitle("Günlük")
        .accessibilityIdentifier("screen.days")
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
                        .font(.ink.contentSmall)
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
