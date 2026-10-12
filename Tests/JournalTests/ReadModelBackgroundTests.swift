import Foundation
import Testing
import VaultFormat

@testable import Journal

@MainActor
struct ReadModelBackgroundTests {
    @Test func addEventBuildsReadModelOffMainThread() async throws {
        final class Probe: @unchecked Sendable {
            var builds = 0
            var onMain = 0
            var offMain = 0
        }
        let probe = Probe()
        // Only builds that carry this test's day; other suites run in parallel. The read model keeps
        // no event text, so the day is one no other suite writes.
        let marker = "Off-main model"
        let date = CalendarDate("1999-07-13")!
        let path = "journal/\(date).md"
        VaultPublishedContent.buildProbe = { _, body in
            let published = try body()
            guard published.content.fragments[path]?.eventCount == 1 else { return published }
            probe.builds += 1
            if Thread.isMainThread {
                probe.onMain += 1
            } else {
                probe.offMain += 1
            }
            return published
        }
        defer { VaultPublishedContent.buildProbe = nil }

        let directory = try testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let store = IndexStore(
            location: VaultLocation(
                defaults: defaults.defaults, documentsURL: directory, bookmarks: pathBookmarks()),
            supportURL: directory.appendingPathComponent("indexes"))
        await store.start()
        #expect(store.lastUpdated != nil)

        probe.builds = 0
        probe.onMain = 0
        probe.offMain = 0
        #expect(await store.addEvent(on: date, text: marker, time: nil))
        #expect(probe.builds >= 1)
        #expect(probe.offMain >= 1)
        #expect(probe.onMain == 0)
        #expect(store.content.fragments[path]?.eventCount == 1)
        #expect(try await store.computeDay(on: date).events.map(\.text.plainText) == [marker])
    }
}
