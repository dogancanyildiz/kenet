import VaultFormat
import VaultIndex

struct GraphInput: Sendable {
    struct Day: Sendable {
        let date: CalendarDate
        let mentions: [String: Int]
    }
    var entities: [EntitySummary] = []
    var totals: [String: Int] = [:]
    var days: [Day] = []
    init() {}
    init(snapshot: IndexSnapshot, entities: [EntitySummary]) {
        self.entities = entities
        let known = Set(entities.map(\.id))
        let dates = Dictionary(
            uniqueKeysWithValues: snapshot.files.compactMap { file -> (String, CalendarDate)? in
                guard file.kind == "day", let date = file.date.flatMap(CalendarDate.init) else { return nil }
                return (file.path, date)
            })
        var days: [CalendarDate: [String: Int]] = [:]
        for link in snapshot.links {
            guard let target = link.resolvedFile, known.contains(target) else { continue }
            totals[target, default: 0] += 1
            if let date = dates[link.file] { days[date, default: [:]][target, default: 0] += 1 }
        }
        self.days = days.map { Day(date: $0.key, mentions: $0.value) }.sorted { $0.date < $1.date }
    }
}
