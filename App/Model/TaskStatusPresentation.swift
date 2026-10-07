import VaultFormat

/// View-independent cues for overdue and completed tasks (contrast, no punishment).
struct TaskStatusPresentation: Equatable, Sendable {
    /// Past-due open task: warning color plus a non-color mark; never for completed work.
    var showsOverdueCue: Bool
    /// Completed work stays readable: secondary text, never reduced opacity.
    var usesSecondaryText: Bool
    /// Always 1; kept explicit so opacity-based “punishment” cannot sneak back in.
    var opacity: Double

    static func make(due: CalendarDate?, asOf day: CalendarDate, isCompleted: Bool) -> Self {
        let pastDue = due.map { $0 < day } ?? false
        return Self(
            showsOverdueCue: pastDue && !isCompleted,
            usesSecondaryText: isCompleted,
            opacity: 1
        )
    }

    /// When the caller already knows whether the due day is before today.
    static func make(isPastDue: Bool, isCompleted: Bool) -> Self {
        Self(
            showsOverdueCue: isPastDue && !isCompleted,
            usesSecondaryText: isCompleted,
            opacity: 1
        )
    }
}
