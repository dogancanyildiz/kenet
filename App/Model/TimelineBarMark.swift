import VaultFormat

/// Çeyrek mark (screens.md "Biçim"): a due-only task is a one-day round badge; a task with a
/// start is a round-ended bar, even when it starts and ends on the same day, so it keeps the
/// grips that drag its dates.
enum TimelineBarMark: Equatable {
    case circle
    case capsule

    static func choice(for span: TimelineSpan) -> Self {
        span.isMilestone ? .circle : .capsule
    }
}
