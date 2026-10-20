import Foundation
import XCTest

/// One element the accessibility audit may report for one audit type, and why the report stands.
///
/// An element is named by its accessibility identifier or by its String Catalog key: the key matches the
/// element's label in every language of `App/Resources/Localizable.xcstrings` (a format argument
/// matches any text), so the table holds in an English and a Turkish run alike. `open` marks a real
/// finding that is not fixed yet; the reason says what fixing it needs.
struct AccessibilityAuditExemption {
    enum Element {
        case identifier(String)
        case identifierPrefix(String)
        case catalogKey(String)
        /// A label that carries the key's text among other parts ("Kişi · … · Son görülme: …").
        case containsCatalogKey(String)
        /// System chrome the catalog does not hold: its label in the test languages.
        case systemLabel([String])
        case labelPattern(String)
    }

    let type: XCUIAccessibilityAuditType
    let element: Element
    let reason: String
    var open = false

    /// The reason as logged: an open finding says so.
    var logged: String { open ? "OPEN FINDING: " + reason : reason }

    func matches(identifier: String, label: String) -> Bool {
        switch element {
        case .identifier(let wanted): identifier == wanted
        case .identifierPrefix(let prefix): identifier.hasPrefix(prefix)
        case .catalogKey(let key): Catalog.shared.patterns(for: key).contains { label.wholeMatch(of: $0) != nil }
        case .containsCatalogKey(let key): Catalog.shared.patterns(for: key).contains { label.contains($0) }
        case .systemLabel(let labels): labels.contains(label)
        case .labelPattern(let pattern): (try? Regex(pattern)).map { label.wholeMatch(of: $0) != nil } ?? false
        }
    }
}

extension AccessibilityAuditExemption {
    /// Audit issues that name their element. Each entry is one element and one audit type.
    static let all: [AccessibilityAuditExemption] = [
        // MARK: dynamicType
        // Sheet toolbar words (InkSheet) sit in the system bar, which keeps bar-item text at its own
        // size at every Dynamic Type size (component.sheetReadingAX3.png); the page under it scales.
        .init(type: .dynamicType, element: .identifier("button.settings.close"), reason: Reason.barItem),
        .init(type: .dynamicType, element: .identifier("button.closeDay.close"), reason: Reason.barItem),
        .init(type: .dynamicType, element: .identifier("button.weeklyReview.cancel"), reason: Reason.barItem),
        // List rows: the text uses semantic text styles and grows with Dynamic Type in the AX3
        // references; the audit's live size change does not reach text hosted in a list cell or a
        // system Menu label.
        .init(
            type: .dynamicType, element: .catalogKey("Bölüm"),
            reason: "section menu label grows (tasksScreen.tasksAX3.png)"),
        .init(
            type: .dynamicType, element: .catalogKey("Yaklaşan"),
            reason: "section menu value grows (tasksScreen.tasksAX3.png)"),
        .init(
            type: .dynamicType, element: .catalogKey("Bir süredir görüşmediklerin"),
            reason: "SectionHeader in a list row grows (entities.peopleAX3.png)"),
        .init(
            type: .dynamicType, element: .catalogKey("Bağlanmamış anmalar"),
            reason: "SectionHeader in a list row grows (entities.peopleAX3.png: same component)"),
        .init(
            type: .dynamicType, element: .labelPattern("[0-9]+"),
            reason: "SectionHeader counter, tabular body font (entities.peopleAX3.png: same component)"),
        // The entity page grows at AX3: subtitle, row dates, meta lines and links
        // (entities.personDatesAX3.png).
        .init(
            type: .dynamicType, element: .catalogKey("Günlükteki geçişlere dayanır."),
            reason: Reason.entityPage),
        .init(type: .dynamicType, element: .catalogKey("Tümünü göster (%lld)"), reason: Reason.entityPage),
        .init(type: .dynamicType, element: .catalogKey("İlk geçiş"), reason: Reason.entityPage),
        .init(type: .dynamicType, element: .containsCatalogKey("Son görülme: %@"), reason: Reason.entityPage),
        .init(type: .dynamicType, element: .labelPattern(Pattern.shortDate), reason: Reason.entityPage),
        // MARK: textClipped
        .init(
            type: .textClipped, element: .catalogKey("Takvim ve Konum"),
            reason: "Settings row wraps to two lines at AX3 (shellSheet.settingsSheetAX3.png)"),
        .init(
            type: .textClipped, element: .catalogKey("Tanılama"),
            reason: "Settings row; rows wrap at AX3 (shellSheet.settingsSheetAX3.png)"),
        .init(
            type: .textClipped, element: .identifier("field.entities.filter"),
            reason: "single-line filter field: typed text scrolls sideways, as every text field does"),
        // iPad split shell at accessibility sizes: the sidebar and the list column keep their width,
        // so long row titles end in "…" and the list column's leading edge is cut off
        // (shell.todayLandscapeAX3.png). Widening the columns is shell work (App/Navigation,
        // ShellStyle), outside this audit change.
        .init(type: .textClipped, element: .identifierPrefix("sidebar."), reason: Reason.padColumns, open: true),
        .init(type: .textClipped, element: .catalogKey("Özetler"), reason: Reason.padColumns, open: true),
        .init(type: .textClipped, element: .catalogKey("Yeni kişi"), reason: Reason.padColumns, open: true),
        .init(type: .textClipped, element: .catalogKey("Rehberden aktar"), reason: Reason.padColumns, open: true),
        .init(
            type: .textClipped, element: .containsCatalogKey("Son görülme: %@"), reason: Reason.padColumns,
            open: true),
        .init(
            type: .textClipped, element: .labelPattern(Pattern.monthTitle), reason: Reason.padColumns, open: true),
        // MARK: hitRegion
        .init(
            type: .hitRegion, element: .systemLabel(["Hide Sidebar", "Kenar Çubuğunu Gizle", "Kenar çubuğunu gizle"]),
            reason: "the split view's own sidebar button (system chrome)"),
        .init(
            type: .hitRegion, element: .labelPattern("[0-9]+"),
            reason: "value of a read-only list row (EntityView \"Gelen bağlantılar\"); the list cell is the row"),
    ]

    /// Controls under 44 × 44 pt that ``AccessibilityAuditPolicy/assertTouchTargets(in:screen:)`` accepts.
    static let touchTargets: [AccessibilityAuditExemption] = [
        .init(
            type: .hitRegion, element: .catalogKey("Günlük yazısını düzenle"),
            reason: "Today's journal preview button is as tall as its text (20 pt with the placeholder);"
                + " a 44 pt frame lengthens the Today page and needs its references re-recorded",
            open: true),
        // Step buttons of Günü kapat and Haftalık inceleme (InkTextButtonStyle): 44 pt tall, as wide as
        // the word ("İleri", "Geri"). A 44 pt minimum width belongs in InkTextButtonStyle (App/Design)
        // and moves the words beside them, so the CloseDay and WeeklyReview references are re-recorded.
        .init(type: .hitRegion, element: .identifier("button.closeDay.next"), reason: Reason.stepButton, open: true),
        .init(type: .hitRegion, element: .identifier("button.closeDay.back"), reason: Reason.stepButton, open: true),
        .init(
            type: .hitRegion, element: .identifier("button.weeklyReview.back"), reason: Reason.stepButton, open: true),
        // Haftalık inceleme's "Çıktıya ekle" toggle row is as tall as its meta-size text (28 pt); a 44 pt
        // row lengthens four review pages and needs the WeeklyReview references re-recorded.
        .init(
            type: .hitRegion, element: .identifier("toggle.weeklyReview.include"),
            reason: "toggle row as tall as its text; a 44 pt row is a WeeklyReview layout and reference change",
            open: true),
    ]
}

private enum Reason {
    static let stepButton = "text step button as wide as its word; the minimum width is InkTextButtonStyle work"
    static let entityPage = "entity page text grows with Dynamic Type (entities.personDatesAX3.png)"
    static let padColumns = "iPad columns keep their width at accessibility sizes (shell.todayLandscapeAX3.png)"
    static let barItem =
        "sheet toolbar word in the system bar, which keeps bar-item text at a fixed size"
        + " (component.sheetReadingAX3.png)"
}

private enum Pattern {
    /// "10 Eki 2026" or "Oct 10, 2026".
    static let shortDate = #"\d{1,2} \p{L}{3}\.? \d{4}|\p{L}{3} \d{1,2}, \d{4}"#
    /// "Ekim 2026" or "October 2026": the calendar's month title.
    static let monthTitle = #"\p{L}+ \d{4}"#
}

/// The app's String Catalog read from the repository (the simulator shares the host's file system).
private final class Catalog: @unchecked Sendable {
    static let shared = Catalog()

    private let strings: [String: Any]

    private init() {
        let url = UITestSupport.repositoryRoot().appendingPathComponent("App/Resources/Localizable.xcstrings")
        let data = (try? Data(contentsOf: url)) ?? Data()
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        strings = root?["strings"] as? [String: Any] ?? [:]
    }

    /// Whole-label patterns for every translation of `key` (and the key itself): format arguments
    /// match any text.
    func patterns(for key: String) -> [Regex<AnyRegexOutput>] {
        var values = [key]
        if let entry = strings[key] as? [String: Any],
            let localizations = entry["localizations"] as? [String: Any]
        {
            for case let localization as [String: Any] in localizations.values {
                values += Self.values(in: localization)
            }
        }
        return values.compactMap { value in
            let escaped = NSRegularExpression.escapedPattern(for: value)
            let pattern = escaped.replacingOccurrences(
                of: #"%(\d+\\\$)?(lld|ld|d|@|f|\.\d+f)"#, with: ".+", options: .regularExpression)
            return try? Regex(pattern)
        }
    }

    /// Every `stringUnit.value` in a localization, plural and device variations included.
    private static func values(in node: [String: Any]) -> [String] {
        var result: [String] = []
        if let unit = node["stringUnit"] as? [String: Any], let value = unit["value"] as? String {
            result.append(value)
        }
        for case let child as [String: Any] in node.values {
            result += values(in: child)
        }
        return result
    }
}
