import AppIntents

struct JournalShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddEventIntent(), phrases: ["\(.applicationName) ile günlüğe olay ekle"],
            shortTitle: "Günlüğe olay ekle", systemImageName: "square.and.pencil")
        AppShortcut(
            intent: AddTaskIntent(), phrases: ["\(.applicationName) ile görev ekle"],
            shortTitle: "Görev ekle", systemImageName: "checklist")
        AppShortcut(
            intent: MarkGoalIntent(), phrases: ["\(.applicationName) ile hedefi işaretle"],
            shortTitle: "Hedefi işaretle", systemImageName: "target")
        AppShortcut(
            intent: OpenTodayIntent(), phrases: ["\(.applicationName) ile bugünü aç"],
            shortTitle: "Bugünü aç", systemImageName: "sun.max")
    }
}
