import Foundation
import VaultIndex

/// Index rows for one Markdown path. Derived screen fields are rebuilt from the fragment map.
struct VaultFileFragment: Sendable, Equatable {
    var file: IndexSnapshot.File
    var entity: IndexedEntity?
    var aliases: [IndexedAlias]
    var blocks: [IndexedBlock]
    var links: [IndexedLink]
    var goalLogs: [IndexedGoalLog]

    init(contents: IndexedFileContents) {
        file = contents.file
        entity = contents.entity
        aliases = contents.aliases
        blocks = contents.blocks
        links = contents.links
        goalLogs = contents.goalLogs
    }

    init(
        file: IndexSnapshot.File, entity: IndexedEntity? = nil, aliases: [IndexedAlias] = [],
        blocks: [IndexedBlock] = [], links: [IndexedLink] = [], goalLogs: [IndexedGoalLog] = []
    ) {
        self.file = file
        self.entity = entity
        self.aliases = aliases
        self.blocks = blocks
        self.links = links
        self.goalLogs = goalLogs
    }
}

extension VaultIndex {
    func loadFragment(path: String) throws -> VaultFileFragment? {
        try contents(ofFile: path).map(VaultFileFragment.init(contents:))
    }
}
