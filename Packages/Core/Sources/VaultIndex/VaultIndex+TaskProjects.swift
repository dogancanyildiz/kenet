import Foundation
import GRDB

extension VaultIndex {
    /// The project names the task screens offer: one spelling per ``projectKey(_:)`` across every
    /// task, open, done or cancelled. Of a key's spellings the least by Swift order wins; of
    /// spellings Swift counts equal (precomposed and decomposed), the one written first by file and
    /// line. Ordered by Swift order, as ``projectNames(_:)`` orders them.
    public func taskProjects() throws -> [String] {
        let names = try database.read {
            try String.fetchAll(
                $0, sql: "SELECT project FROM blocks WHERE kind='task' AND project IS NOT NULL ORDER BY file, ordinal")
        }
        // Swift `Set` compares canonically, so only the first of equal spellings is kept.
        var seen: Set<String> = []
        return Self.projectNames(names.filter { seen.insert($0).inserted })
    }
}
