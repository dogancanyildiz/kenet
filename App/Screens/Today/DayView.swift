import SwiftUI
import VaultFormat

/// The same editable layout serves today and a selected historical day.
struct DayView: View {
    let store: IndexStore
    let date: CalendarDate
    var isToday = false
    @Environment(NotificationService.self) private var notifications
    @Environment(CalendarService.self) private var calendar
    @State private var showsJournal = false

    private var taskGroups: TaskGroups { TaskGroups(rows: store.content.tasks, on: date, isToday: isToday) }
    private var day: DaySummary { store.content.day(on: date) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                GoalStripView(store: store, day: date).id(date.description + (store.vaultURL?.path ?? ""))
                if store.isProcessing && !store.isWriting { ProgressView("İndeks güncelleniyor…") }
                if let error = store.errorText { Text(verbatim: error).foregroundStyle(.red) }
                if day.events.isEmpty && day.journal.isEmpty && taskGroups.isEmpty && !day.hasGoalRecords {
                    Group {
                        if isToday {
                            Text("Gününden bir an yaz; @ ile kişi ekle")
                        } else {
                            Text("Bu gün henüz bir şey yazılmadı.")
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                DayTasksView(store: store, date: date, isToday: isToday)
                    .id(date.description + (isToday ? "today-tasks" : "day-tasks"))
                DayCalendarView(date: date)
                if !day.events.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Olaylar").font(.headline).accessibilityAddTraits(.isHeader)
                        ForEach(day.events) { event in
                            DayEventView(store: store, day: date, event: event)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Günlük yazısı").font(.headline).accessibilityAddTraits(.isHeader)
                    #if os(iOS)
                        Button {
                            showsJournal = true
                        } label: {
                            journalPreview
                        }
                        .accessibilityLabel("Günlük yazısını düzenle")
                    #else
                        NavigationLink {
                            JournalView(store: store, date: date)
                        } label: {
                            journalPreview
                        }
                        .accessibilityLabel("Günlük yazısını düzenle")
                    #endif
                }
            }
            .padding().frame(maxWidth: 700, alignment: .leading).frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            QuickEntryBar(
                store: store, isEnabled: true, day: isToday ? nil : date,
                focusRequest: isToday && notifications.navigationRequest?.destination == .journal
                    ? notifications.navigationRequest?.id : nil, acceptsPeopleMentions: isToday
            )
            .id(isToday ? "today" : date.description)
        }
        .navigationTitle(
            isToday ? Text("Bugün") : Text(LocalDay.instant(for: date), format: .dateTime.day().month().year())
        )
        .toolbar { SearchButton() }
        .task(id: date) {
            if AppLaunchPolicy.allowsAutomaticStart() { await calendar.load(date) }
        }
        .sheet(isPresented: $showsJournal) {
            NavigationStack { JournalView(store: store, date: date) }
        }
    }

    @ViewBuilder private var journalPreview: some View {
        if let preview = day.preview {
            Text(verbatim: preview).lineLimit(4).frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("Günlük yazısı ekle…").frame(maxWidth: .infinity, alignment: .leading)
        }
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
