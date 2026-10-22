import Foundation
import Observation
import VaultFormat

/// What one run over the share extension's lists did, for the band on the main screen.
struct ShareImportReport: Equatable, Sendable {
    /// Queued texts written now, and lines the extension wrote into the iCloud vault itself.
    var added = 0
    /// Records, or a whole list, the app could not read; their bytes are kept aside in the group.
    var unreadable = 0
    /// Records still waiting: the write failed, the next run tries again.
    var waiting = 0

    var isEmpty: Bool { added == 0 && unreadable == 0 && waiting == 0 }

    /// The band's sentences, in this order: added, unreadable, waiting.
    var message: String {
        var parts: [String] = []
        if added > 0 { parts.append(String(localized: "\(added) paylaşım eklendi.")) }
        if unreadable > 0 { parts.append(String(localized: "\(unreadable) paylaşım okunamadı.")) }
        if waiting > 0 { parts.append(String(localized: "\(waiting) paylaşım eklenemedi; sonra yeniden denenecek.")) }
        return parts.joined(separator: " ")
    }
}

/// The app's side of the share extension (docs/architecture.md, "Paylaşım uzantısı").
///
/// It tells the extension where the vault is (`share/target.json`) and, once the vault is open
/// and the app unlocked, takes in what the extension left: lines it wrote into the iCloud vault
/// itself (`share/written.json`: the index refreshes the journal folder) and texts waiting in the
/// queue (`share/pending.json`: each becomes an event on its own day and time through
/// `IndexStore.addEvent`, with the app's name recognition). A record leaves the queue right after
/// its line is saved, so no run writes it twice; a record that cannot be read is kept aside, a
/// failed write stays queued. Before the write the record is marked with the line it becomes
/// (`ShareEntry.writing`): when a run stops between the save and the removal, the next run finds
/// the line on its day and only removes the record.
@MainActor @Observable final class ShareQueueProcessor {
    private(set) var report: ShareImportReport?
    @ObservationIgnored private let store: IndexStore
    @ObservationIgnored private let group: any AppGroupStore
    @ObservationIgnored private let isLocked: () -> Bool
    @ObservationIgnored private let appLockEnabled: () -> Bool
    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private var again = false

    init(
        store: IndexStore, group: any AppGroupStore, isLocked: @escaping () -> Bool,
        appLockEnabled: @escaping () -> Bool
    ) {
        self.store = store
        self.group = group
        self.isLocked = isLocked
        self.appLockEnabled = appLockEnabled
    }

    /// Tells the extension which vault is open and whether app lock is on. Written when it changes.
    func publishTarget() {
        guard let root = group.containerURL else { return }
        let target = ShareTarget(vault: store.shareVault, appLock: appLockEnabled())
        let url = ShareFiles.target(in: root)
        if ShareTargetFile.read(from: url) == target { return }
        try? ShareTargetFile.write(target, to: url)
    }

    /// Takes in what the extension left. A call while a run is going runs once more afterwards.
    func process() {
        guard running == nil else {
            again = true
            return
        }
        running = Task { [weak self] in await self?.drain() }
    }

    /// Returns once no run is going.
    func settle() async {
        while let running { await running.value }
    }

    func dismissReport() { report = nil }

    private func drain() async {
        repeat {
            again = false
            await run()
        } while again
        running = nil
    }

    private func run() async {
        guard let root = group.containerURL, isReady else { return }
        var result = ShareImportReport()
        await takeWritten(in: root, into: &result)
        await takeQueued(in: root, into: &result)
        if !result.isEmpty { report = result }
    }

    /// Vault open, writable and published; app unlocked.
    private var isReady: Bool { !isLocked() && store.canAddEvent && store.lastUpdated != nil }

    private func takeWritten(in root: URL, into result: inout ShareImportReport) async {
        let file = ShareListFile(url: ShareFiles.written(in: root))
        let contents = file.read()
        if case .unreadable = contents {
            // Only markers: the lines are in the vault already.
            _ = try? file.setAsideIfUnreadable()
            await store.refresh(directories: ["journal"])
            return
        }
        let elements = contents.elements
        guard !elements.isEmpty else { return }
        await store.refresh(directories: ["journal"])
        let ids = Set(elements.compactMap(\.entry?.id))
        result.added += ids.count
        try? file.remove(ids: ids, raws: Set(elements.filter { $0.entry == nil }.map(\.raw)))
    }

    private func takeQueued(in root: URL, into result: inout ShareImportReport) async {
        let file = ShareListFile(url: ShareFiles.pending(in: root))
        switch file.read() {
        case .missing:
            return
        case .unreadable:
            if (try? file.setAsideIfUnreadable()) == true { result.unreadable += 1 }
        case .list(let elements):
            let damaged = elements.filter { $0.entry == nil }.map(\.raw)
            if !damaged.isEmpty, setAside(damaged, in: root) {
                try? file.remove(ids: [], raws: Set(damaged))
                result.unreadable += damaged.count
            }
            for entry in elements.compactMap(\.entry) {
                // Locked or the vault gone meanwhile: the rest waits for the next run.
                guard isReady else { return }
                switch await take(entry, from: file) {
                case .added: result.added += 1
                case .waiting: result.waiting += 1
                }
            }
        }
    }

    private enum Taken { case added, waiting }

    /// One queued record into the vault, at most once.
    private func take(_ entry: ShareEntry, from file: ShareListFile) async -> Taken {
        guard let day = entry.calendarDay else { return .waiting }
        if let line = entry.writing {
            // An earlier run marked it and may have saved the line before it stopped.
            guard let saved = await hasEvent(line, at: entry.clock, on: day) else { return .waiting }
            if saved {
                try? file.remove(ids: [entry.id])
                return .added
            }
        }
        // The event through the app's write path, with names recognised as in an App Intent.
        let text = (try? IntentText.linking(entry.text, entities: store.knownEntities)) ?? entry.text
        var marked = entry
        marked.writing = text
        // No mark, no write: a queue this run cannot change could not lose the record afterwards either.
        guard (try? file.replace(marked)) != nil else { return .waiting }
        guard await store.addEvent(on: day, text: text, time: entry.clock) else {
            // Nothing was saved now; the record waits as it came. An earlier mark stays: its line may be
            // in a day this run could not see (a day back in iCloud reads as empty and refuses the write).
            try? file.replace(entry)
            return .waiting
        }
        // Saved: the record leaves the queue now, so no later run writes it again.
        try? file.remove(ids: [entry.id])
        return .added
    }

    /// Whether the day file holds an event with this text and time; nil when the day cannot be read.
    private func hasEvent(_ text: String, at clock: LineClock?, on day: CalendarDate) async -> Bool? {
        guard let document = try? await store.dayDocument(for: day) else { return nil }
        return document.bodyLines.events.contains { event in
            event.block.text == text && event.time?.hour == clock?.hour && event.time?.minute == clock?.minute
        }
    }

    /// Keeps unreadable records' bytes in the group (`ShareFiles.damaged`) before they leave the queue.
    private func setAside(_ raws: [Data], in root: URL) -> Bool {
        let objects = raws.compactMap { try? JSONSerialization.jsonObject(with: $0, options: .fragmentsAllowed) }
        guard let data = try? JSONSerialization.data(withJSONObject: objects, options: [.sortedKeys]) else {
            return false
        }
        let url = ShareFiles.damaged(inShareDirectory: ShareFiles.directory(in: root))
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}
