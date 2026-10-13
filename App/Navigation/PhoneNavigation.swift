import SwiftUI

/// Each phone tab retains its own navigation stack. The selection, the stacks and the Settings
/// sheet live in the bridge (`ShellNavigationState`), which outlives the shell: the iPhone Duo
/// builds this shell anew each time it closes.
struct PhoneNavigation: View {
    let store: IndexStore
    @Environment(IntentNavigation.self) private var intentNavigation
    @Environment(NotificationService.self) private var notifications
    @State private var navigation: ShellNavigationState

    init(store: IndexStore, navigation: ShellNavigationState) {
        self.store = store
        _navigation = State(initialValue: navigation)
    }

    var body: some View {
        @Bindable var navigation = navigation
        TabView(selection: $navigation.selectedTab) {
            Tab("Bugün", systemImage: "sun.max", value: PhoneTab.today) {
                NavigationStack(path: $navigation.todayPath) {
                    TodayView(store: store)
                        .environment(\.openSettings, { navigation.showingSettings = true })
                }
            }
            .accessibilityIdentifier("tab.today")
            Tab("Günlük", systemImage: "book.closed", value: PhoneTab.days) {
                NavigationStack { DaysView(store: store) }
            }
            .accessibilityIdentifier("tab.days")
            Tab("Görevler", systemImage: "checklist", value: PhoneTab.tasks) {
                NavigationStack(path: $navigation.tasksPath) {
                    TasksView(
                        store: store,
                        notificationRequest: notifications.navigationRequest?.destination == .tasks
                            ? notifications.navigationRequest?.id : nil)
                }
            }
            .accessibilityIdentifier("tab.tasks")
            Tab("Kişiler ve Konumlar", systemImage: "person.2", value: PhoneTab.entities) {
                NavigationStack(path: $navigation.entitiesPath) {
                    EntitiesView(store: store, initialUnseenExpanded: navigation.unseenReveal != nil)
                        .id(navigation.unseenReveal)
                }
            }
            .accessibilityIdentifier("tab.entities")
            Tab("Hedefler", systemImage: "target", value: PhoneTab.goals) {
                NavigationStack { GoalsView(store: store) }
            }
            .accessibilityIdentifier("tab.goals")
        }
        // `initial: true` so a request from before the shell was built is still routed; the
        // bridge tells a shell rebuilt after the request to leave it alone.
        .onChange(of: intentNavigation.todayRequest, initial: true) { _, request in
            guard navigation.claimTodayRequest(request) else { return }
            navigation.showingSettings = false
            navigation.todayPath = NavigationPath()
            navigation.selectedTab = .today
        }
        .onChange(of: notifications.navigationRequest?.id, initial: true) { _, id in
            guard navigation.claimNavigationRequest(id), let request = notifications.navigationRequest else { return }
            navigation.showingSettings = false
            switch NotificationRoute(request.destination) {
            case .tasks:
                navigation.tasksPath = NavigationPath()
                navigation.selectedTab = .tasks
            case .unseenPeople:
                navigation.entitiesPath = NavigationPath()
                navigation.unseenReveal = request.id
                navigation.selectedTab = .entities
            case .today:
                navigation.todayPath = NavigationPath()
                navigation.selectedTab = .today
            }
        }
        .phoneSettingsSheet(store: store, isPresented: $navigation.showingSettings)
        // After `.sheet` so the accent also reaches what the tab view presents.
        .tint(Color.ink.accent)
    }
}

extension View {
    /// Both iOS shells present the same settings stack and close action.
    func phoneSettingsSheet(store: IndexStore, isPresented: Binding<Bool>) -> some View {
        sheet(isPresented: isPresented) {
            NavigationStack {
                PhoneSettingsView(store: store)
                    .inkSheet(
                        "Ayarlar", closeIdentifier: "button.settings.close",
                        onClose: { isPresented.wrappedValue = false })
            }
            .inkToggle()
            .inkAdaptiveFormPresentation()
        }
    }
}
