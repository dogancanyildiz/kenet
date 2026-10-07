import Foundation
import VaultFormat

/// Pure reading-page copy for an entity (manşet künye and field grouping).
enum EntityReadPresentation {
    struct FieldRow: Identifiable, Equatable, Sendable {
        let key: String
        let label: String
        let value: String
        /// When true, shown under "Diğer alanlar" with secondary styling.
        let isOther: Bool
        /// Byte identity so NFC/NFD-equivalent keys stay distinct in `ForEach`.
        var id: [UInt8] { Array(key.utf8) }
    }

    /// Byline parts: type name, aliases, optional last-seen date text.
    static func byline(
        kindLabel: String, aliases: [String], lastSeen: CalendarDate?, locale: Locale
    ) -> String {
        var parts = [kindLabel]
        let aliasText = aliases.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: ", ")
        if !aliasText.isEmpty { parts.append(aliasText) }
        if let lastSeen {
            let date = LocalDay.instant(for: lastSeen).formatted(
                .dateTime.day().month(.abbreviated).year().locale(locale))
            parts.append(String(localized: "Son görülme: \(date)", locale: locale))
        }
        return parts.joined(separator: " · ")
    }

    /// Groups schema fields first; unknown keys become secondary "other" rows.
    static func fieldRows(
        fields: [EntityField], schemaKeys: Set<String>, locale: Locale = .autoupdatingCurrent
    ) -> (known: [FieldRow], other: [FieldRow]) {
        var known: [FieldRow] = []
        var other: [FieldRow] = []
        for field in fields {
            let value = FrontmatterValueDisplay.text(field.value, locale: locale)
            let row = FieldRow(
                key: field.key,
                label: FrontmatterKeyLabel.display(field.key),
                value: value,
                isOther: !schemaKeys.contains(field.key) && FrontmatterKeyLabel.localized(field.key) == nil)
            if row.isOther {
                other.append(row)
            } else {
                known.append(row)
            }
        }
        return (known, other)
    }
}
