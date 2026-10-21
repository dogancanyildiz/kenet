import Foundation
import GoalTracking
import VaultFormat

/// Fictional vault for the chain-day screens (decision 67), the day before `today` and back.
///
/// "Esneme" (daily yes/no) is done every day from 13 July 2026 except four misses covered by
/// chain days and one free forgiveness:
///
/// | Days | Done | Balance after |
/// |---|---|---|
/// | 13 Jul – 9 Aug | 28 | 3 (rewards at 7, 14, 21; the 28th is dropped at the cap) |
/// | 10–11 Aug missed | — | 1: two chain days spent |
/// | 12 Aug – 2 Sep | 22 (50 in all) | 3: rewards at 35 and 42; 49 dropped |
/// | 3 Sep missed, 4 Sep done | 1 (51) | 3: free forgiveness, nothing spent |
/// | 5–13 Sep | 9 (60) | 3: 56 dropped |
/// | 14–15 Sep missed | — | 1: two chain days spent |
/// | 16–19 Sep | 4 (64) | 2: reward at 63 |
///
/// On 20 September (today, not marked yet) the streak is 64, the balance 2 and the spent days
/// 10, 11 August and 14, 15 September, all inside the six weeks an AX3 heatmap shows.
/// "Okuma" (daily number, 20 sayfa) has a few scattered days and no balance: its row has no badge.
enum GraceDayVault {
    static let today = CalendarDate("2026-09-20")!
    static let first = CalendarDate("2026-07-13")!
    static let freeForgiven = CalendarDate("2026-09-03")!
    static let spent = ["2026-08-10", "2026-08-11", "2026-09-14", "2026-09-15"].map { CalendarDate($0)! }
    static let balance = 2
    static let streak = 64

    static let stretching = GoalDefinition(
        id: "goals/Esneme.md", key: "esneme", name: "Esneme", period: .day, kind: .boolean, target: 1)!
    static let reading = GoalDefinition(
        id: "goals/Okuma.md", key: "okuma", name: "Okuma", period: .day, kind: .number, target: 20, unit: "sayfa")!

    private static let readingDays: [String: Int] = [
        "2026-09-12": 20, "2026-09-15": 12, "2026-09-17": 25, "2026-09-19": 8,
    ]

    /// Every day from `first` to the day before `today` that "Esneme" was done.
    static var stretchingDays: [CalendarDate] {
        let missed = Set(spent + [freeForgiven])
        var days: [CalendarDate] = []
        var day = first
        while day < today {
            if !missed.contains(day) { days.append(day) }
            day = day.addingDays(1)!
        }
        return days
    }

    static var stretchingLogs: [GoalLog] {
        stretchingDays.map { GoalLog(day: $0, value: .boolean(true)) }
    }

    static func generate(at root: URL) throws {
        try write(root, ".app/vault.json", "{ \"formatVersion\": 1 }\n")
        try write(
            root, "goals/Esneme.md",
            "---\ntype: goal\nname: Esneme\nkey: esneme\nperiod: day\nkind: boolean\ntarget: 1\n---\n")
        try write(
            root, "goals/Okuma.md",
            "---\ntype: goal\nname: Okuma\nkey: okuma\nperiod: day\nkind: number\ntarget: 20\nunit: sayfa\n---\n")
        let done = Set(stretchingDays)
        var day = first
        while day < today {
            var goals = done.contains(day) ? "  esneme: true\n" : ""
            if let pages = readingDays["\(day)"] { goals += "  okuma: \(pages)\n" }
            let front = goals.isEmpty ? "" : "goals:\n" + goals
            try write(root, "journal/\(day).md", "---\ntype: journal\ndate: \(day)\n\(front)---\n")
            day = day.addingDays(1)!
        }
        try write(
            root, "journal/\(today).md",
            "---\ntype: journal\ndate: \(today)\n---\n\n## Events\n- 08:30 Sabah yürüyüşü ^gr4c01\n")
    }

    private static func write(_ root: URL, _ path: String, _ text: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
}
