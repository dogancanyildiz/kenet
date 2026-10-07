import Foundation
import VaultFormat
import VaultIndex

/// The serialized, file-first write gateway for one Markdown vault.
public actor VaultStore {
    let root: URL
    let index: VaultIndex
    let writeQueue: OperationQueue
    let linkFile: @Sendable (URL, URL) throws -> Void
    let moveFile: @Sendable (URL, URL) throws -> Void
    let restoreRenameFile: (@Sendable (Data, URL) throws -> Void)?
    let readFile: @Sendable (URL) throws -> Data
    let randomValue: @Sendable () -> UInt64
    /// Serialised with `writeQueue`; caches `.app/vault.json` mtime so writes do not re-parse every time.
    let writeGate: WriteGate

    /// Uses the caller's index and an existing vault root; random injection supports deterministic tests.
    public init(
        vaultRoot: URL, index: VaultIndex,
        randomValue: @escaping @Sendable () -> UInt64 = { UInt64.random(in: .min ... .max) }
    ) {
        root = vaultRoot.resolvingSymlinksInPath().standardizedFileURL
        self.index = index
        writeQueue = VaultWriteQueues.shared.queue(for: vaultRoot)
        self.randomValue = randomValue
        linkFile = { try FileManager.default.linkItem(at: $0, to: $1) }
        moveFile = { try FileManager.default.moveItem(at: $0, to: $1) }
        restoreRenameFile = nil
        readFile = { try Data(contentsOf: $0) }
        writeGate = WriteGate()
    }

    /// Internal filesystem seam for deterministic failure and creation-race tests.
    init(
        vaultRoot: URL, index: VaultIndex, randomValue: @escaping @Sendable () -> UInt64 = { 0 },
        linkFile: @escaping @Sendable (URL, URL) throws -> Void,
        moveFile: @escaping @Sendable (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) },
        restoreRenameFile: (@Sendable (Data, URL) throws -> Void)? = nil,
        readFile: @escaping @Sendable (URL) throws -> Data = { try Data(contentsOf: $0) }
    ) {
        root = vaultRoot.resolvingSymlinksInPath().standardizedFileURL
        self.index = index
        writeQueue = VaultWriteQueues.shared.queue(for: vaultRoot)
        self.randomValue = randomValue
        self.linkFile = linkFile
        self.moveFile = moveFile
        self.restoreRenameFile = restoreRenameFile
        self.readFile = readFile
        writeGate = WriteGate()
    }

    /// Returns the canonical vault-relative path of a day.
    public nonisolated func dayFilePath(for date: CalendarDate) -> String {
        "journal/" + date.description + ".md"
    }

    /// Reads the current disk bytes without querying the index.
    public func document(at relativePath: String) throws -> RawDocument {
        RawDocument(bytes: try readFile(checkedURL(relativePath)))
    }

    /// Reads an existing day from disk, throwing if it does not exist.
    public func dayDocument(for date: CalendarDate) throws -> RawDocument {
        try document(at: dayFilePath(for: date))
    }

    /// Adds an event, optionally with a local clock time, and returns the written document.
    @discardableResult
    public func addingEvent(on date: CalendarDate, text: String, time: LineClock? = nil) async throws -> RawDocument {
        try await perform {
            try self.editDay(date) { document in
                try document.addingEvent(text: text, id: self.freshID(in: document), time: time)
            }
        }
    }

    /// Adds a task with optional fields in canonical order.
    @discardableResult
    public func addingTask(
        on date: CalendarDate, text: String, due: CalendarDate? = nil, start: CalendarDate? = nil,
        priority: TaskPriority? = nil, project: String? = nil, recurrence: TaskRecurrence? = nil
    ) async throws -> RawDocument {
        try await perform {
            try self.editDay(date) { document in
                try document.addingTask(
                    text: text, id: self.freshID(in: document), due: due, start: start,
                    priority: priority, project: project, recurrence: recurrence)
            }
        }
    }

    /// Replaces only the target's text, assigning a unique identifier when required.
    @discardableResult
    public func changingText(of target: LineBlock, at path: String, to text: String) async throws -> RawDocument {
        try await perform {
            try self.edit(path) { document in
                try document.changingText(
                    of: target, to: text, newID: self.replacementID(target, path: path, in: document))
            }
        }
    }

    /// Changes a task's status, preserving unrelated bytes.
    @discardableResult
    public func changingStatus(
        of target: TaskLine, at path: String, to status: TaskStatus, completionDate: CalendarDate? = nil
    ) async throws -> RawDocument {
        try await perform {
            try self.edit(path) { document in
                let replacement = try self.replacementID(target.block, path: path, in: document)
                if status == .done, !target.status.isClosed, target.recurrence != nil {
                    guard let completionDate else { throw EditError.invalidValue }
                    // Reserve any repaired original identifier before generating the next one.
                    let reserved = try document.changingStatus(
                        of: target, to: .done, completionDate: completionDate, newID: replacement)
                    return try document.completingRecurringTask(
                        target, completionDate: completionDate,
                        newID: self.freshID(in: reserved), completedID: replacement)
                }
                return try document.changingStatus(
                    of: target, to: status, completionDate: completionDate, newID: replacement)
            }
        }
    }

    /// Changes or removes an event's clock time, applying the format's ordering rule.
    @discardableResult
    public func changingTime(of target: EventLine, at path: String, to time: LineClock?) async throws -> RawDocument {
        try await perform {
            try self.edit(path) { document in
                try document.changingTime(
                    of: target, to: time, newID: self.replacementID(target.block, path: path, in: document))
            }
        }
    }

    /// Deletes the target's complete block, retaining the section heading.
    @discardableResult
    public func deletingBlock(_ target: LineBlock, at path: String) async throws -> RawDocument {
        try await perform {
            try self.edit(path) { try $0.deletingBlock(target) }
        }
    }

    /// Replaces Journal content, preserving trailing blanks and leaving a missing section untouched for empty text.
    @discardableResult
    public func changingJournal(on date: CalendarDate, to text: String) async throws -> RawDocument {
        try await perform {
            try self.edit(self.dayFilePath(for: date), date: date, createDay: !text.allSatisfy(\.isWhitespace)) {
                try $0.replacingJournal(with: text)
            }
        }
    }

    nonisolated func perform<T: Sendable>(_ action: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            writeQueue.addOperation {
                do {
                    try self.ensureWritable()
                    continuation.resume(returning: try action())
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    /// Refuses writes when format version is unsupported.
    nonisolated func ensureWritable() throws {
        try ensureFormatVersionWritable()
    }

    /// Refuses a write whose path starts with a canonical reserved folder when a case variant exists on disk.
    ///
    /// Editing an existing file under the physical variant path (for example `People/Baran.md`) is allowed;
    /// creating or writing under the canonical spelling (`people/…`) is not.
    nonisolated func ensureReservedFolderCase(forCanonicalFolder folder: String) throws {
        let children: [URL]
        do {
            children = try FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        } catch {
            return
        }
        for url in children {
            let name = url.lastPathComponent
            guard name.lowercased() == folder, name != folder else { continue }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isSymbolicLink != true, values?.isDirectory == true else { continue }
            throw VaultStoreError.reservedFolderCaseMismatch(found: name, expected: folder)
        }
    }

    private nonisolated func ensureFormatVersionWritable() throws {
        let url = root.appendingPathComponent(".app/vault.json")
        let exists = FileManager.default.fileExists(atPath: url.path)
        if !exists {
            if writeGate.checked, writeGate.missing { return }
            writeGate.checked = true
            writeGate.missing = true
            writeGate.mtime = nil
            writeGate.allowsWrite = true
            return
        }
        let mtime = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        if writeGate.checked, !writeGate.missing, writeGate.mtime == mtime {
            if !writeGate.allowsWrite { throw VaultStoreError.readOnlyVault }
            return
        }
        // A failed read (dataless iCloud file, transient coordination error) is not cached:
        // the next write reads again instead of staying read-only until the store is recreated.
        let bytes: Data
        do {
            bytes = try readFile(url)
        } catch {
            throw VaultStoreError.readOnlyVault
        }
        let allows =
            VaultFormatVersion.formatVersion(in: bytes).map(VaultFormatVersion.canWrite(vaultVersion:)) ?? false
        writeGate.checked = true
        writeGate.missing = false
        writeGate.mtime = mtime
        writeGate.allowsWrite = allows
        if !allows { throw VaultStoreError.readOnlyVault }
    }

    nonisolated func editDay(_ date: CalendarDate, transform: (RawDocument) throws -> RawDocument) throws -> RawDocument
    {
        try edit(dayFilePath(for: date), date: date, transform: transform)
    }

    nonisolated func edit(
        _ path: String, date: CalendarDate? = nil, createDay: Bool = true,
        transform: (RawDocument) throws -> RawDocument
    ) throws -> RawDocument {
        for attempt in 0..<2 {
            do {
                return try editOnce(path, date: date, createDay: createDay, transform: transform)
            } catch VaultStoreError.nameTaken where date != nil {
                guard attempt == 0 else { throw VaultStoreError.staleTarget }
            }
        }
        throw VaultStoreError.staleTarget
    }

    private nonisolated func editOnce(
        _ path: String, date: CalendarDate?, createDay: Bool,
        transform: (RawDocument) throws -> RawDocument
    ) throws -> RawDocument {
        let url = try checkedURL(path, writing: true)
        let original: RawDocument
        let wasMissing: Bool
        do {
            original = RawDocument(bytes: try readFile(url))
            wasMissing = false
        } catch CocoaError.fileReadNoSuchFile where date != nil {
            guard createDay else { return RawDocument(bytes: []) }
            wasMissing = true
            original = try RawDocument(bytes: []).settingFrontmatterValue(.text("journal"), forKey: "type")
                .settingFrontmatterValue(.date(date!), forKey: "date")
        }
        let changed: RawDocument
        do { changed = try transform(original) } catch EditError.targetNotFound {
            throw VaultStoreError.staleTarget
        }
        guard changed != original else { return original }
        try persist(changed, path: path, exclusive: wasMissing)
        return changed
    }

    nonisolated func freshID(in document: RawDocument) throws -> String {
        var taken = try index.blockIdentifiers()
        taken.formUnion(document.bodyLines.tasks.compactMap { $0.block.id })
        taken.formUnion(document.bodyLines.events.compactMap { $0.block.id })
        var random = StoreRandom(nextValue: randomValue)
        return try BlockIDGenerator.generate(using: &random, isTaken: { taken.contains($0) })
    }

    nonisolated func replacementID(_ target: LineBlock, path: String, in document: RawDocument) throws -> String? {
        // Check staleness before consulting the index or consuming random candidates.
        guard
            document.bodyLines.tasks.contains(where: { $0.block == target })
                || document.bodyLines.events.contains(where: { $0.block == target })
        else { throw VaultStoreError.staleTarget }
        if let id = target.id {
            let normalizedPath = path.precomposedStringWithCanonicalMapping
            let owner = try index.owner(of: id)
            let earlierFileOwns =
                owner.map {
                    $0.file.utf8.lexicographicallyPrecedes(normalizedPath.utf8)
                } ?? false
            let blocks = document.bodyLines.tasks.map(\.block) + document.bodyLines.events.map(\.block)
            let firstOccurrence = blocks.filter { $0.id == id }.min { $0.line < $1.line }
            if !earlierFileOwns, firstOccurrence == target { return nil }
        }
        return try freshID(in: document)
    }
}
