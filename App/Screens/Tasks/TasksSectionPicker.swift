import SwiftUI

/// Single view-mode control for Tasks: same labels, order, and placement (toolbar) on iPhone and Mac.
struct TasksSectionPicker: View {
    @Binding var section: TasksModel.Section

    var body: some View {
        Picker("Görev bölümü", selection: $section) {
            Text("Yaklaşan").tag(TasksModel.Section.upcoming)
            Text("Tarihsiz").tag(TasksModel.Section.undated)
            Text("Tamamlanan").tag(TasksModel.Section.completed)
            Text("Projeler").tag(TasksModel.Section.projects)
            Text("Kanban").tag(TasksModel.Section.kanban)
            Text("Zaman çizelgesi").tag(TasksModel.Section.timeline)
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("tasks.section")
    }
}

extension TasksModel.Section {
    /// Device preference key for the last chosen Tasks view.
    static let storageKey = "tasks.section"
}
