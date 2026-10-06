import Foundation
import VaultFormat

/// Spoken VoiceOver strings for cues that are otherwise icon- or canvas-only.
enum VoiceOverCopy {
    static func taskCompletionValue(isCompleted: Bool, locale: Locale = .current) -> String {
        boxStatusValue(isCompleted ? .done : .todo, locale: locale, presentation: false)
    }

    static func priorityValue(_ priority: TaskPriority, locale: Locale = .current) -> String {
        boxPriorityValue(priority, locale: locale, presentation: false)
    }

    /// Task box cue for the Today presentation; the catalog language follows `locale`
    /// (unlike the two lookups above, which follow the process language).
    static func taskBoxValue(state: TaskBoxState, locale: Locale) -> String {
        let status = boxStatusValue(state.status, locale: locale, presentation: true)
        guard let priority = state.priority else { return status }
        return "\(status), \(boxPriorityValue(priority, locale: locale, presentation: true))"
    }

    static func dayRowLabel(
        date: CalendarDate, eventCount: Int, preview: String?, locale: Locale = .current
    ) -> String {
        let formatted = LocalDay.instant(for: date).formatted(
            .dateTime.day().month().year().locale(locale))
        var parts = [formatted, String(localized: "Olaylar: \(eventCount)", locale: locale)]
        if let preview, !preview.isEmpty { parts.append(preview) }
        return parts.joined(separator: ", ")
    }

    static func moveActionName(columnTitle: String, locale: Locale = .current) -> String {
        String(localized: "Taşı: \(columnTitle)", locale: locale)
    }

    static func changeDateActionName(locale: Locale = .current) -> String {
        String(localized: "Tarihi değiştir", locale: locale)
    }

    static func disclosureValue(isExpanded: Bool, locale: Locale = .current) -> String {
        String(localized: isExpanded ? "Genişletilmiş" : "Daraltılmış", locale: locale)
    }

    static func timelineBarLabel(
        text: String, start: CalendarDate?, due: CalendarDate?, isOverdue: Bool,
        locale: Locale = .current
    ) -> String {
        var parts = [text]
        let style = Date.FormatStyle.dateTime.day().month(.abbreviated).year().locale(locale)
        switch (start, due) {
        case (let start?, let due?):
            parts.append(
                "\(LocalDay.instant(for: start).formatted(style))–\(LocalDay.instant(for: due).formatted(style))"
            )
        case (let start?, nil):
            parts.append(
                "\(LocalDay.instant(for: start).formatted(style)), \(String(localized: "Açık uçlu", locale: locale))"
            )
        case (nil, let due?):
            parts.append(LocalDay.instant(for: due).formatted(style))
        case (nil, nil):
            break
        }
        if isOverdue { parts.append(String(localized: "Devreden", locale: locale)) }
        return parts.joined(separator: ", ")
    }

    static func graphNodeKind(_ kind: GraphNode.Kind, locale: Locale = .current) -> String {
        switch kind {
        case .person: String(localized: "Kişi", locale: locale)
        case .place: String(localized: "Konum", locale: locale)
        case .day: String(localized: "Gün", locale: locale)
        }
    }

    static func graphNodeLabel(
        name: String, kind: GraphNode.Kind, neighborCount: Int, locale: Locale = .current
    ) -> String {
        let kindText = graphNodeKind(kind, locale: locale)
        let neighbors = String(localized: "\(neighborCount) komşu", locale: locale)
        return "\(name), \(kindText), \(neighbors)"
    }

    /// Shared status switch for process-language helpers and presentation-locale lookups.
    private static func boxStatusValue(
        _ status: TaskStatus, locale: Locale, presentation: Bool
    ) -> String {
        let key: String.LocalizationValue =
            switch status {
            case .inProgress: "Devam"
            case .done: "Tamamlandı"
            case .cancelled: "İptal"
            case .todo, .unknown: "Açık"
            }
        return localize(key, locale: locale, presentation: presentation)
    }

    /// Shared priority switch for process-language helpers and presentation-locale lookups.
    private static func boxPriorityValue(
        _ priority: TaskPriority, locale: Locale, presentation: Bool
    ) -> String {
        let key: String.LocalizationValue =
            switch priority {
            case .high: "Yüksek öncelik"
            case .medium: "Orta öncelik"
            case .low: "Düşük öncelik"
            case .other(let token): "Öncelik \(token)"
            }
        return localize(key, locale: locale, presentation: presentation)
    }

    private static func localize(
        _ key: String.LocalizationValue, locale: Locale, presentation: Bool
    ) -> String {
        if presentation {
            return String(
                localized: key, bundle: PresentationLocalization.bundle(locale), locale: locale)
        }
        return String(localized: key, locale: locale)
    }
}

/// VoiceOver-facing row for a graph node (canvas itself is not accessible).
struct GraphAccessibleNode: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let kind: GraphNode.Kind
    let neighborCount: Int

    func accessibilityLabel(locale: Locale = .current) -> String {
        VoiceOverCopy.graphNodeLabel(name: name, kind: kind, neighborCount: neighborCount, locale: locale)
    }

    static func list(from graph: GraphModel) -> [Self] {
        graph.nodes.map {
            Self(id: $0.id, name: $0.name, kind: $0.kind, neighborCount: graph.neighbors(of: $0.id).count)
        }
    }
}
