import Foundation

/// Composes caller-localized PeriodSummary sentences and review answers without Markdown structure.
public enum WeeklyReviewText {
    public static func lines(
        title: String, summaryLines: [String] = [], selectedLines: [String] = [], note: String? = nil
    ) -> [String] {
        let body = (summaryLines + selectedLines + [note ?? ""]).flatMap(normalizedLines)
        guard !body.isEmpty else { return [] }
        let heading = normalizedLines(title).joined(separator: " ")
        return (heading.isEmpty ? [] : ["### " + heading]) + body.map { "· " + $0 }
    }

    private static func normalizedLines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines).map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
    }
}
