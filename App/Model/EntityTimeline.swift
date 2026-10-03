import VaultFormat
import VaultIndex

struct EntityTimelineDay: Identifiable, Sendable {
    let date: CalendarDate
    let rows: [EntityTimelineRow]
    var id: CalendarDate { date }
}

struct EntityTimelineRow: Identifiable, Sendable {
    let file: String
    let ordinal: Int
    let text: LinkedText
    var id: String { file + ":" + String(ordinal) }
}

enum EntityTimeline {
    static func build(snapshot: IndexSnapshot) -> [String: [EntityTimelineDay]] {
        let dates = Dictionary(
            uniqueKeysWithValues: snapshot.files.compactMap { file -> (String, CalendarDate)? in
                guard file.kind == "day", let value = file.date, let date = CalendarDate(value) else { return nil }
                return (file.path, date)
            })
        let links = Dictionary(grouping: snapshot.links, by: \.file)
        var result: [String: [CalendarDate: [EntityTimelineRow]]] = [:]
        for block in snapshot.blocks
        where block.kind == "event" || (block.kind == "paragraph" && block.section == "Journal") {
            guard let date = dates[block.file] else { continue }
            let source = links[block.file] ?? []
            let targets = Set(source.filter { $0.block == block.ordinal }.compactMap(\.resolvedFile))
            for target in targets {
                result[target, default: [:]][date, default: []].append(
                    EntityTimelineRow(
                        file: block.file, ordinal: block.ordinal, text: LinkedText(row: block, links: source)))
            }
        }
        return result.mapValues { days in
            days.map {
                EntityTimelineDay(date: $0.key, rows: $0.value.sorted { ($0.file, $0.ordinal) > ($1.file, $1.ordinal) })
            }
            .sorted { $0.date > $1.date }
        }
    }
}
