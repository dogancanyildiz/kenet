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

    /// Byline parts (Şafak drawing): "Kişi · takma ad Baran · son görülme 19 Eyl". The year shows
    /// only when the last-seen day falls in another year than `today`.
    static func byline(
        kindLabel: String, aliases: [String], lastSeen: CalendarDate?, today: CalendarDate = LocalDay.today(),
        locale: Locale
    ) -> String {
        var parts = [kindLabel]
        let aliasText = aliases.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: ", ")
        if !aliasText.isEmpty {
            parts.append(PresentationLocalization.string(localized: "takma ad \(aliasText)", locale: locale))
        }
        if let lastSeen {
            let style: Date.FormatStyle =
                lastSeen.year == today.year
                ? .dateTime.day().month(.abbreviated) : .dateTime.day().month(.abbreviated).year()
            let date = LocalDay.instant(for: lastSeen).formatted(style.locale(locale))
            parts.append(PresentationLocalization.string(localized: "son görülme \(date)", locale: locale))
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
