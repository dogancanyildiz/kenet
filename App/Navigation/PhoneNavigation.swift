import SwiftUI

/// Each phone tab retains its own navigation stack.
struct PhoneNavigation: View {
    let store: IndexStore
    @Environment(IntentNavigation.self) private var intentNavigation
    @Environment(NotificationService.self) private var notifications
    @State private var selectedTab = PhoneTab.today
    @State private var todayPath = NavigationPath()
    @State private var taskPath = NavigationPath()
    @State private var showingSettings = false

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Bugün", systemImage: "sun.max", value: PhoneTab.today) {
                NavigationStack(path: $todayPath) {
                    TodayView(store: store)
                        .toolbar {
                            Button("Ayarlar", systemImage: "gearshape") { showingSettings = true }
                                .labelStyle(.iconOnly)
                        }
                }
            }
            Tab("Günlük", systemImage: "book.closed", value: PhoneTab.days) {
                NavigationStack { DaysView(store: store) }
            }
            Tab("Görevler", systemImage: "checklist", value: PhoneTab.tasks) {
                NavigationStack(path: $taskPath) {
                    TasksView(
                        store: store,
                        notificationRequest: notifications.navigationRequest?.destination == .tasks
                            ? notifications.navigationRequest?.id : nil)
                }
            }
            Tab("Kişiler ve Konumlar", systemImage: "person.2", value: PhoneTab.entities) {
                NavigationStack { EntitiesView(store: store) }
            }
            Tab("Hedefler", systemImage: "target", value: PhoneTab.goals) {
                NavigationStack { GoalsView(store: store) }
            }
        }
        .onChange(of: intentNavigation.todayRequest, initial: true) { _, request in
            guard request != nil else { return }
            showingSettings = false
            todayPath = NavigationPath()
            selectedTab = .today
        }
        .onChange(of: notifications.navigationRequest?.id, initial: true) { _, id in
            guard id != nil, let request = notifications.navigationRequest else { return }
            showingSettings = false
            if request.destination == .tasks {
                taskPath = NavigationPath()
                selectedTab = .tasks
            } else {
                todayPath = NavigationPath()
                selectedTab = .today
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                DiagnosticsView(store: store)
                    .navigationTitle("Ayarlar")
                    .toolbar { Button("Kapat") { showingSettings = false } }
            }
        }
    }
}

private enum PhoneTab: Hashable { case today, days, tasks, entities, goals }
