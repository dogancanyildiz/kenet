import VaultFormat

enum TimelineBarMark: Equatable {
    case circle
    case capsule

    static func choice(for span: TimelineSpan) -> Self {
        span.first == span.last ? .circle : .capsule
    }
}
