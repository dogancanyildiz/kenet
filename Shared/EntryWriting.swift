import Foundation
import VaultFormat
import VaultIndex
import VaultStore

// The share extension's way into the vault (docs/architecture.md, "Paylaşım uzantısı"). The app and
// the extension both compile this file: the extension adds a shared text, the app reads what the
// extension left in the App Group. Foundation and Core only; no index is opened here.

/// Whether the shared text becomes an event line (`- HH:MM …`) or an open task (`- [ ] …`).
enum ShareEntryKind: String, Codable, CaseIterable, Sendable {
    case event
    case task
}

/// One shared text on its way into the vault: an event line for `day` at `time`, or an open task
/// line for `day`, as the extension saw the clock when the user tapped the confirm button. `id`
/// names the record in the App Group lists.
struct ShareEntry: Codable, Equatable, Sendable {
    let id: String
    let text: String
    /// `YYYY-MM-DD`, the user's local day.
    let day: String
    /// `HH:MM`, 24 hours; nil for tasks or untimed events.
    let time: String?
    let sharedAt: Date
    /// The line text the app is saving for this record, set in the queue just before the write and
    /// cleared when the write fails. A record still carrying it was saved by a run that stopped
    /// before the record left the queue: the next run finds the line and does not write it again.
    var writing: String?
    /// Block identifiers (`^id`) of the lines on `day` that already read as this record (same text,
    /// and for an event the same time or none) when the queue marked it: a run that stopped after
    /// the write finds a line outside this list, so an older identical line is never taken for the
    /// new one. Every line the app adds carries an identifier.
    var existingLineIDs: [String]?
    let kind: ShareEntryKind

    private enum CodingKeys: String, CodingKey {
        case id, text, day, time, sharedAt, writing, existingLineIDs, kind
    }

    init(
        id: String, text: String, day: String, time: String?, sharedAt: Date,
        writing: String? = nil, existingLineIDs: [String]? = nil, kind: ShareEntryKind = .event
    ) {
        self.id = id
        self.text = text
        self.day = day
        self.time = time
        self.sharedAt = sharedAt
        self.writing = writing
        self.existingLineIDs = existingLineIDs
        self.kind = kind
    }

    /// The entry the user confirms at `instant`: today, at the current minute (for events) or open task.
    init(text: String, at instant: Date, id: UUID = UUID(), kind: ShareEntryKind = .event) {
        self.init(text: text, kind: kind, time: instant, sharedAt: instant, id: id)
    }

    /// The entry the user confirms with a chosen `kind` and optional `time` on `sharedAt`'s local day.
    init(
        text: String, kind: ShareEntryKind, time: Date?, sharedAt: Date = Date(),
        id: UUID = UUID()
    ) {
        let formattedTime: String?
        switch kind {
        case .event:
            if let time {
                let clock = LocalDay.clock(at: time)
                formattedTime =
                    (clock.hour < 10 ? "0" : "") + "\(clock.hour):"
                    + (clock.minute < 10 ? "0" : "") + "\(clock.minute)"
            } else {
                formattedTime = nil
            }
        case .task:
            formattedTime = nil
        }
        self.init(
            id: id.uuidString, text: text, day: "\(LocalDay.today(at: sharedAt))",
            time: formattedTime, sharedAt: sharedAt, kind: kind)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        day = try container.decode(String.self, forKey: .day)
        time = try container.decodeIfPresent(String.self, forKey: .time)
        sharedAt = try container.decode(Date.self, forKey: .sharedAt)
        writing = try container.decodeIfPresent(String.self, forKey: .writing)
        existingLineIDs = try container.decodeIfPresent([String].self, forKey: .existingLineIDs)
        kind = try container.decodeIfPresent(ShareEntryKind.self, forKey: .kind) ?? .event
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(day, forKey: .day)
        try container.encodeIfPresent(time, forKey: .time)
        try container.encode(sharedAt, forKey: .sharedAt)
        try container.encodeIfPresent(writing, forKey: .writing)
        if let existingLineIDs, !existingLineIDs.isEmpty {
            try container.encode(existingLineIDs, forKey: .existingLineIDs)
        }
        if kind != .event {
            try container.encode(kind, forKey: .kind)
        }
    }

    var calendarDay: CalendarDate? { CalendarDate(day) }

    /// Identifiers of the lines in `document` that read as this record written as `text`: an
    /// open-or-any task with that text, or an event with that text at the record's time (both
    /// untimed when the record has none). Lines without an identifier are not the app's and never count.
    func matchingLineIDs(in document: RawDocument, text: String) -> [String] {
        let lines = document.bodyLines
        switch kind {
        case .event:
            let clock = self.clock
            return lines.events.filter { event in
                event.block.text == text && event.time?.hour == clock?.hour
                    && event.time?.minute == clock?.minute
            }.compactMap(\.block.id)
        case .task:
            return lines.tasks.filter { $0.block.text == text }.compactMap(\.block.id)
        }
    }

    /// Whether `document` holds the line a marked run wrote: a matching line that was not there
    /// when the record was marked (`existingLineIDs`).
    func isWritten(_ text: String, in document: RawDocument) -> Bool {
        let earlier = Set(existingLineIDs ?? [])
        return matchingLineIDs(in: document, text: text).contains { !earlier.contains($0) }
    }

    var clock: LineClock? {
        guard let time else { return nil }
        let parts = time.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ $0.count == 2 }), let hour = Int(parts[0]),
            let minute = Int(parts[1])
        else { return nil }
        return try? LineClock(hour: hour, minute: minute)
    }

    /// A record the app can write: a known day, a valid time, a text Core accepts as one event or task line.
    var isWritable: Bool {
        guard UUID(uuidString: id) != nil, calendarDay != nil else { return false }
        switch kind {
        case .event:
            return (time == nil || clock != nil)
                && EntryWriting.canWrite(text, kind: .event, timed: time != nil)
        case .task:
            return time == nil && EntryWriting.canWrite(text, kind: .task, timed: false)
        }
    }
}

/// Turning shared content into one event line.
enum EntryWriting {
    /// The text the form starts with: the page title and its link (Safari), or the shared text,
    /// or, from an app that shares its text only as the item's content text, that text (`title`).
    /// Line breaks and runs of white space become one space: an event is one line. A page title
    /// comes from the page, not the user, so its markup is made plain words (`plainWords`).
    static func prefill(title: String?, url: URL?, text: String?) -> String {
        if let url {
            let link = url.absoluteString
            let heading = plainWords(title ?? "")
            return heading.isEmpty || heading == link ? link : heading + " " + link
        }
        let shared = singleLine(text ?? "")
        return shared.isEmpty ? singleLine(title ?? "") : shared
    }

    static func singleLine(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    /// A title is words, not markup: `[[`/`]]` lose a bracket so no link forms, and an `@` or `#`
    /// at a word's start becomes its full-width form, which neither mentions nor tags. The same
    /// rule as Journaling Suggestions' titles.
    static func plainWords(_ text: String) -> String {
        var words = singleLine(text)
        while words.contains("[[") { words = words.replacingOccurrences(of: "[[", with: "[") }
        while words.contains("]]") { words = words.replacingOccurrences(of: "]]", with: "]") }
        return
            words
            .split(separator: " ")
            .map { word in
                guard let first = word.first, first == "@" || first == "#" else { return String(word) }
                return (first == "@" ? "＠" : "＃") + word.dropFirst()
            }
            .joined(separator: " ")
    }

    /// Whether Core writes `text` as one event or task line, as the extension writes it. The
    /// form asks it of the text it would add (`singleLine`), so practically only empty text is
    /// refused; a record read from the queue is asked again, with or without its time.
    static func canWrite(_ text: String, kind: ShareEntryKind = .event, timed: Bool = true) -> Bool {
        guard !text.allSatisfy(\.isWhitespace) else { return false }
        do {
            switch kind {
            case .event:
                let time = timed ? try? LineClock(hour: 12, minute: 0) : nil
                _ = try RawDocument(bytes: []).addingEvent(text: text, id: "aaaaaa", time: time)
            case .task:
                _ = try RawDocument(bytes: []).addingTask(text: text, id: "aaaaaa")
            }
            return true
        } catch {
            return false
        }
    }
}

/// Where the iCloud vault lives in the container: the same folder `VaultLocation` opens.
enum ShareVault {
    static func cloudRoot(in container: URL) -> URL {
        container.appendingPathComponent("Documents/Kenet", isDirectory: true)
    }
}

/// What the app tells the extension about its vault, in `share/target.json`. The extension writes
/// the vault itself only into the iCloud vault of an app without app lock; everything else waits
/// in the queue. No file, or a file this version cannot read, means the queue.
struct ShareTarget: Codable, Equatable, Sendable {
    enum Vault: String, Codable, Sendable {
        case icloud, local, selected, none
    }

    var vault: Vault
    var appLock: Bool

    var writesDirectly: Bool { vault == .icloud && !appLock }
}

/// The App Group paths of the share extension, under `share/`.
enum ShareFiles {
    static func directory(in group: URL) -> URL { group.appendingPathComponent("share", isDirectory: true) }
    /// Shared texts waiting for the app (local or selected vault, app lock, iCloud unavailable).
    static func pending(in group: URL) -> URL { directory(in: group).appendingPathComponent("pending.json") }
    /// Shared texts the extension wrote into the iCloud vault itself; the app refreshes its index.
    static func written(in group: URL) -> URL { directory(in: group).appendingPathComponent("written.json") }
    static func target(in group: URL) -> URL { directory(in: group).appendingPathComponent("target.json") }
    /// Bytes the app could not read, kept aside in the `share/` folder instead of deleted.
    static func damaged(inShareDirectory directory: URL) -> URL {
        directory.appendingPathComponent("damaged-" + UUID().uuidString + ".json")
    }
}

enum ShareTargetFile {
    static func read(from url: URL) -> ShareTarget? {
        guard let data = try? coordinatedRead(url) else { return nil }
        return try? JSONDecoder().decode(ShareTarget.self, from: data)
    }

    static func write(_ target: ShareTarget, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(target)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try coordinatedWrite(url) { try data.write(to: url, options: .atomic) }
    }
}

/// A JSON list in the App Group that both processes change: `{"format":1,"entries":[…]}`.
///
/// Every change is a coordinated read, change and atomic write of the whole file, so the extension
/// appending and the app removing never lose each other's record. Elements are kept as raw JSON:
/// a record this version cannot read stays in the list until the app moves it aside. A file that
/// is not such a list, or that cannot be read at all, is moved aside (`ShareFiles.damaged`, beside
/// the list) before the next change, never dropped or written over.
struct ShareListFile: Sendable {
    let url: URL
    static let format = 1

    /// One element: its JSON (sorted keys) and the record, or nil when it cannot be read.
    struct Element: Sendable {
        let raw: Data
        let entry: ShareEntry?
    }

    enum Contents: Sendable {
        case missing
        case unreadable
        case list([Element])

        var elements: [Element] {
            if case .list(let elements) = self { return elements }
            return []
        }
    }

    func read() -> Contents {
        guard let data = try? coordinatedRead(url) else {
            return FileManager.default.fileExists(atPath: url.path) ? .unreadable : .missing
        }
        guard let raws = Self.elements(in: data) else { return .unreadable }
        return .list(raws.map { Element(raw: $0, entry: Self.entry(from: $0)) })
    }

    func append(_ entry: ShareEntry) throws {
        let raw = try Self.encode(entry)
        try change { $0.append(raw) }
    }

    /// Puts `entry` in place of the record with its identifier; a list without it stays as it is.
    func replace(_ entry: ShareEntry) throws {
        let raw = try Self.encode(entry)
        try change { elements in
            elements = elements.map { Self.entry(from: $0)?.id == entry.id ? raw : $0 }
        }
    }

    /// Removes the records named `ids` and the unreadable elements in `raws`.
    func remove(ids: Set<String>, raws: Set<Data> = []) throws {
        try change { elements in
            elements.removeAll { raw in
                if raws.contains(raw) { return true }
                guard let entry = Self.entry(from: raw) else { return false }
                return ids.contains(entry.id)
            }
        }
    }

    /// Moves an unreadable file aside so the next change starts a new list; true if it did.
    @discardableResult func setAsideIfUnreadable() throws -> Bool {
        var moved = false
        try change(movedAside: &moved) { _ in }
        return moved
    }

    private func change(_ body: (inout [Data]) -> Void) throws {
        var moved = false
        try change(movedAside: &moved, body)
    }

    private func change(movedAside moved: inout Bool, _ body: (inout [Data]) -> Void) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var setAside = false
        try coordinatedWrite(url) {
            var elements: [Data] = []
            if FileManager.default.fileExists(atPath: url.path) {
                if let data = try? Data(contentsOf: url), let read = Self.elements(in: data) {
                    elements = read
                } else {
                    // Not a list, or a file this process cannot read: its bytes move aside whole
                    // before a new list takes the name. A failed move throws; nothing is replaced.
                    try FileManager.default.moveItem(
                        at: url, to: ShareFiles.damaged(inShareDirectory: url.deletingLastPathComponent()))
                    setAside = true
                }
            }
            let before = elements
            body(&elements)
            if elements.isEmpty {
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            } else if elements != before || setAside {
                try Self.serialize(elements).write(to: url, options: .atomic)
            }
        }
        moved = setAside
    }

    static func encode(_ entry: ShareEntry) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try normalized(encoder.encode(entry)) ?? encoder.encode(entry)
    }

    static func entry(from raw: Data) -> ShareEntry? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let entry = try? decoder.decode(ShareEntry.self, from: raw), entry.isWritable else { return nil }
        return entry
    }

    /// The list's elements, or nil when `data` is not a list of this format.
    static func elements(in data: Data) -> [Data]? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            object["format"] as? Int == format, let entries = object["entries"] as? [Any]
        else { return nil }
        return entries.map { element in
            (try? JSONSerialization.data(withJSONObject: element, options: [.sortedKeys, .fragmentsAllowed])) ?? Data()
        }
    }

    private static func normalized(_ data: Data) -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) else { return nil }
        return try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed])
    }

    private static func serialize(_ elements: [Data]) throws -> Data {
        let entries = try elements.map { try JSONSerialization.jsonObject(with: $0, options: .fragmentsAllowed) }
        return try JSONSerialization.data(
            withJSONObject: ["format": format, "entries": entries] as [String: Any], options: [.sortedKeys])
    }
}

/// The extension's side: writes a confirmed text into the iCloud vault itself when the app allows
/// it (`ShareTarget.writesDirectly`), and queues it in the App Group otherwise or when that write
/// fails. Nothing is written twice: a failed vault write saved no bytes, so the queue holds the
/// only copy.
struct ShareEntryWriter: Sendable {
    enum Outcome: Equatable, Sendable {
        /// The line is in the iCloud vault; the app refreshes its index when it next runs.
        case written
        /// The text waits in `share/pending.json` for the app.
        case queued
    }

    enum Failure: Error, Equatable {
        /// No App Group container: nothing can be queued either.
        case groupUnavailable
        /// Not one event line (`ShareEntry.isWritable`); the form does not offer it.
        case notAnEventLine
    }

    let group: URL?
    /// The iCloud container, or nil without iCloud. A fake folder in tests; never the real one.
    let cloudContainer: @Sendable () async -> URL?
    /// The coordination Core's writer holds around the day file (`NSFileCoordinator` in the extension).
    let coordination: any FileCoordination
    var randomValue: @Sendable () -> UInt64 = { UInt64.random(in: .min ... .max) }

    func add(_ entry: ShareEntry) async throws -> Outcome {
        guard let group else { throw Failure.groupUnavailable }
        guard entry.isWritable else { throw Failure.notAnEventLine }
        if let target = ShareTargetFile.read(from: ShareFiles.target(in: group)), target.writesDirectly,
            let container = await cloudContainer(),
            await writeToVault(entry, root: ShareVault.cloudRoot(in: container))
        {
            // The line is saved; a lost marker only delays the app's refresh until its own scan.
            try? ShareListFile(url: ShareFiles.written(in: group)).append(entry)
            return .written
        }
        try ShareListFile(url: ShareFiles.pending(in: group)).append(entry)
        return .queued
    }

    /// Adds the event through Core's writer: only the new line enters the day file, the rest of
    /// its bytes stay. False when nothing was saved (no vault there yet, a day still in iCloud, a
    /// read-only vault or day, coordination refused).
    func writeToVault(_ entry: ShareEntry, root: URL) async -> Bool {
        let settings = root.appendingPathComponent(".app/vault.json")
        guard FileManager.default.fileExists(atPath: settings.path), let day = entry.calendarDay,
            entry.isWritable
        else { return false }
        do {
            // An empty index in memory: the writer checks identifiers against the day file only.
            let store = VaultStore(
                vaultRoot: root, index: try VaultIndex(), randomValue: randomValue, fileCoordination: coordination)
            switch entry.kind {
            case .event:
                try await store.addingEvent(on: day, text: entry.text, time: entry.clock)
            case .task:
                try await store.addingTask(on: day, text: entry.text)
            }
            return true
        } catch VaultStoreError.indexUpdateFailed {
            return true
        } catch {
            return false
        }
    }
}

private func coordinatedRead(_ url: URL) throws -> Data {
    var result: Result<Data, any Error>?
    var denied: NSError?
    NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &denied) { url in
        result = Result { try Data(contentsOf: url) }
    }
    if let result { return try result.get() }
    throw denied ?? CocoaError(.fileReadUnknown)
}

private func coordinatedWrite(_ url: URL, _ body: () throws -> Void) throws {
    var result: Result<Void, any Error>?
    var denied: NSError?
    NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forMerging, error: &denied) { _ in
        result = Result { try body() }
    }
    if let result { return try result.get() }
    throw denied ?? CocoaError(.fileWriteUnknown)
}
