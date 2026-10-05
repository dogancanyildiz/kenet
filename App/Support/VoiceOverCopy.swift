import Foundation
import VaultFormat

/// Spoken VoiceOver strings for cues that are otherwise icon- or canvas-only.
enum VoiceOverCopy {
    static func taskCompletionValue(isCompleted: Bool, locale: Locale = .current) -> String {
        String(localized: isCompleted ? "Tamamlandı" : "Açık", locale: locale)
    }

    static func priorityValue(_ priority: TaskPriority, locale: Locale = .current) -> String {
        switch priority {
        case .high: String(localized: "Yüksek öncelik", locale: locale)
        case .medium: String(localized: "Orta öncelik", locale: locale)
        case .low: String(localized: "Düşük öncelik", locale: locale)
        case .other(let token): String(localized: "Öncelik \(token)", locale: locale)
        }
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
