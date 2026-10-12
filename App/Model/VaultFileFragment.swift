import Foundation
import VaultIndex

/// Index rows for one Markdown path, cut to what the read model still derives: the file, its
/// entity and aliases, its links and goal values, and how many event and task blocks it has.
/// Block text (paragraphs, headings, tasks, events) stays in the index; screens query it.
struct VaultFileFragment: Sendable, Equatable {
    var file: IndexSnapshot.File
    var entity: IndexedEntity?
    var aliases: [IndexedAlias]
    var links: [IndexedLink]
    var goalLogs: [IndexedGoalLog]
    /// Event blocks of the file (`IndexCounts.events`).
    var eventCount: Int
    /// Task blocks of the file (`IndexCounts.tasks`).
    var taskCount: Int

    init(contents: IndexedFileContents) {
        self.init(
            file: contents.file, entity: contents.entity, aliases: contents.aliases, blocks: contents.blocks,
            links: contents.links, goalLogs: contents.goalLogs)
    }

    /// Keeps of `blocks` only how many are events and tasks.
    init(
        file: IndexSnapshot.File, entity: IndexedEntity? = nil, aliases: [IndexedAlias] = [],
        blocks: [IndexedBlock] = [], links: [IndexedLink] = [], goalLogs: [IndexedGoalLog] = []
    ) {
        self.file = file
        self.entity = entity
        self.aliases = aliases
        self.links = links
        self.goalLogs = goalLogs
        eventCount = blocks.count { $0.kind == "event" }
        taskCount = blocks.count { $0.kind == "task" }
    }
}

extension VaultIndex {
    func loadFragment(path: String) throws -> VaultFileFragment? {
        try contents(ofFile: path).map(VaultFileFragment.init(contents:))
    }
}
