import SwiftUI
import VaultFormat

/// Priority emoji with a spoken VoiceOver value (icon alone is silent).
struct TaskPriorityMark: View {
    let priority: TaskPriority

    var body: some View {
        Text(verbatim: priority.token)
            .accessibilityLabel("Öncelik")
            .accessibilityValue(Text(verbatim: VoiceOverCopy.priorityValue(priority)))
    }
}
