import Foundation
import VaultFormat
import VaultIndex
import VaultStore

@testable import Journal

/// Small fictional vault for incremental read-model equivalence (not a real diary).
enum IncrementalReadModelVault {
    static let today = CalendarDate("2026-10-05")!

    @discardableResult
    static func seed(at root: URL) throws -> URL {
        try write(root, ".app/vault.json", "{ \"formatVersion\": 1 }\n")
        try write(root, "templates/person.md", "---\ntype: person\n---\n")
        try write(root, "templates/place.md", "---\ntype: place\n---\n")
        try write(
            root, "people/Deniz Example.md",
            """
            ---
            type: person
            name: Deniz Example
            aliases: [Deniz]
            ---
            """)
        try write(
            root, "places/Harbor Cafe.md",
            """
            ---
            type: place
            name: Harbor Cafe
            ---
            """)
        try write(
            root, "goals/Reading.md",
            """
            ---
            type: goal
            name: Reading
            key: reading
            period: day
            kind: number
            target: 20
            unit: pages
            ---
            """)
        try write(
            root, "journal/2026-10-05.md",
            """
            ---
            type: journal
            date: 2026-10-05
            goals:
              reading: 5
            ---

            ## Tasks
            - [ ] Buy oats 📅 2026-10-05 ^task1
            - [ ] Call [[Deniz Example]] ^task2

            ## Events
            - 09:15 Coffee at [[Harbor Cafe]] ^evt1

            ## Journal
            Morning with [[Deniz Example]].
            """)
        try write(
            root, "journal/2026-10-04.md",
            """
            ---
            type: journal
            date: 2026-10-04
            ---

            ## Events
            - 18:00 Walk near [[Harbor Cafe]] ^evt2

            ## Journal
            Quiet evening.
            """)
        try write(root, "notes/Scratch.md", "- [ ] Loose note ^note1\n")
        return root
    }

    static func write(_ root: URL, _ path: String, _ text: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    static func fullModel(index: VaultIndex, today: CalendarDate = today) throws -> VaultReadModel {
        VaultReadModel(snapshot: try index.snapshot(), today: today)
    }

    static func apply(
        _ previous: VaultReadModel, index: VaultIndex, result: RebuildResult, today: CalendarDate = today
    ) throws -> VaultReadModel {
        try VaultPublishedContent.applying(
            previous: previous, index: index, result: result, today: today
        ).content
    }
}
