import SwiftUI

/// Each phone tab retains its own navigation stack.
struct PhoneNavigation: View {
    let store: IndexStore
    @State private var showingSettings = false

    var body: some View {
        TabView {
            Tab("Bugün", systemImage: "sun.max") {
                NavigationStack {
                    TodayView(store: store)
                        .toolbar {
                            Button("Ayarlar", systemImage: "gearshape") { showingSettings = true }
                                .labelStyle(.iconOnly)
                        }
                }
            }
            Tab("Günlük", systemImage: "book.closed") {
                NavigationStack { DaysView(store: store) }
            }
            Tab("Görevler", systemImage: "checklist") {
                NavigationStack { TasksView(store: store) }
            }
            Tab("Kişiler ve Konumlar", systemImage: "person.2") {
                NavigationStack { EntitiesView(store: store) }
            }
            Tab("Hedefler", systemImage: "target") {
                NavigationStack { GoalsView(store: store) }
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
