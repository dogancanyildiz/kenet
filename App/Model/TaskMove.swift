import DateParsing
import Foundation
import VaultFormat
import VaultStore

/// Where an open task can be moved in one action.
enum TaskMoveDestination: Hashable, Sendable {
    case today
    case tomorrow
    case nextWeek

    var titleKey: String {
        switch self {
        case .today: "Bugüne"
        case .tomorrow: "Yarına"
        case .nextWeek: "Haftaya"
        }
    }
}

/// One offered move: the menu and VoiceOver both read this list.
struct TaskMoveOption: Hashable, Sendable {
    let destination: TaskMoveDestination
    let date: CalendarDate
}

/// Due dates for the move actions. Next week is the day quick entry gives for `haftaya` / `next week`.
enum TaskMove {
    /// Quick entry parses without a week start (`QuickEntryModel.dateExpression`), so this passes none either;
    /// giving one here would make the menu and the typed expression disagree.
    static func date(_ destination: TaskMoveDestination, today: CalendarDate) -> CalendarDate? {
        switch destination {
        case .today: today
        case .tomorrow: DateExpressionParser.parse("yarın", today: today, language: [.turkish])?.date
        case .nextWeek: DateExpressionParser.parse("haftaya", today: today, language: [.turkish])?.date
        }
    }

    /// Closed tasks get no move actions. A destination the task is already due on is not offered.
    static func options(for row: TaskRow, on today: CalendarDate) -> [TaskMoveOption] {
        guard !row.isClosed else { return [] }
        return [TaskMoveDestination.today, .tomorrow, .nextWeek].compactMap { destination in
            guard let date = date(destination, today: today), date != row.due else { return nil }
            return TaskMoveOption(destination: destination, date: date)
        }
    }

    /// Each task is read again right before its own write, so an earlier write in the same file cannot
    /// leave a later row pointing at old lines. A changed task is skipped; later rows still write.
    @MainActor
    static func apply(_ rows: [TaskRow], to date: CalendarDate, in store: IndexStore) async -> TaskMoveReport {
        var report = TaskMoveReport()
        let root = store.vaultURL
        for row in rows where !row.isClosed && row.due != date {
            let editor = TaskEditorModel(store: store, row: row)
            await editor.load()
            // The rows were listed from `root`; another vault may hold a look-alike task at the same path.
            var saved = false
            if editor.target != nil, store.vaultURL == root { saved = await editor.setDue(date) }
            if saved {
                report.moved += 1
                // Saved, but the index did not follow.
                if report.failureText == nil { report.failureText = editor.errorText }
            } else if editor.isStale {
                report.unchanged += 1
            } else {
                report.failed += 1
                if report.failureText == nil {
                    report.failureText =
                        editor.errorText
                        ?? String(localized: "Değişiklik kaydedilemedi. Kasayı kontrol edip yeniden dene.")
                }
            }
        }
        return report
    }
}

struct TaskMoveReport: Equatable, Sendable {
    var moved = 0
    /// Skipped because the task changed or disappeared since it was listed.
    var unchanged = 0
    /// Not written for any other reason (missing file, read-only vault, write error).
    var failed = 0
    var failureText: String?

    var isPartial: Bool { unchanged > 0 || failed > 0 }

    func text(locale: Locale) -> String? {
        let bundle = PresentationLocalization.bundle(locale)
        var parts: [String] = []
        if moved > 0 {
            parts.append(String(localized: "\(moved) görev taşındı", bundle: bundle, locale: locale))
        }
        if unchanged > 0 {
            parts.append(
                String(
                    localized: "\(unchanged) görev değişmiş olduğu için taşınmadı", bundle: bundle,
                    locale: locale))
        }
        if failed > 0 {
            parts.append(String(localized: "\(failed) görev taşınamadı", bundle: bundle, locale: locale))
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: ", ")
    }
}
