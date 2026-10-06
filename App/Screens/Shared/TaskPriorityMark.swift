import SwiftUI
import VaultFormat

/// Spoken priority cue when a separate mark is still needed outside ``TaskBox``.
/// Prefer putting priority inside ``TaskBox``; this mark is text-only (no emoji).
struct TaskPriorityMark: View {
    let priority: TaskPriority

    var body: some View {
        Group {
            switch priority {
            case .high:
                Text(verbatim: "!!")
            case .medium:
                Text(verbatim: "!")
            case .low:
                Image(systemName: "arrow.down")
            case .other:
                Text(verbatim: priority.token)
            }
        }
        .font(.ink.meta.weight(.bold))
        .foregroundStyle(.ink.text)
        .accessibilityLabel("Öncelik")
        .accessibilityValue(Text(verbatim: VoiceOverCopy.priorityValue(priority)))
    }
}
