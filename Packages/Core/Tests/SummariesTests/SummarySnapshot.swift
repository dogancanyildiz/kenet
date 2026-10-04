import Foundation
import Summaries

func fixtureDirectory() -> URL {
    if let path = ProcessInfo.processInfo.environment["FIXTURES_DIR"] { return URL(fileURLWithPath: path) }
    return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(
            "Fixtures")
}
func canonical(_ value: [String: Any]) throws -> String {
    String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self)
}
func snapshot(_ summary: PeriodSummary) -> [String: Any] {
    func counts(_ value: SummaryCounts) -> [String: Int] {
        [
            "events": value.events, "writtenDays": value.writtenDays, "peopleMentions": value.peopleMentions,
            "placeMentions": value.placeMentions,
            "firstPeople": value.firstPeople, "firstPlaces": value.firstPlaces, "createdTasks": value.createdTasks,
            "completedTasks": value.completedTasks,
            "overdueTasks": value.overdueTasks, "undatedTasks": value.undatedTasks,
        ]
    }
    func entities(_ values: [SummaryEntityCount]) -> [[String: Any]] {
        values.map { ["id": $0.id, "name": $0.name, "count": $0.count, "change": $0.change] }
    }
    return [
        "start": summary.range.lowerBound.description, "end": summary.range.upperBound.description,
        "previousStart": summary.previousRange?.lowerBound.description as Any? ?? NSNull(),
        "previousEnd": summary.previousRange?.upperBound.description as Any? ?? NSNull(),
        "counts": counts(summary.counts), "previous": counts(summary.previous), "change": counts(summary.change),
        "people": entities(summary.people), "places": entities(summary.places),
        "goals": summary.goals.map {
            [
                "id": $0.definition.id, "done": $0.progress.done, "target": $0.progress.target,
                "contribution": $0.contribution,
                "streak": $0.streak, "change": $0.change, "streakChange": $0.streakChange,
                "completionDate": $0.completionDate?.description as Any? ?? NSNull(),
            ] as [String: Any]
        }, "isEmpty": summary.isEmpty,
    ]
}
