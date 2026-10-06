import Foundation
import Testing

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
        // Only builds that carry this test's event count; other suites run in parallel.
        let marker = "Off-main model"
        VaultPublishedContent.buildProbe = { _, body in
            let published = try body()
            let hasMarker = published.content.days.contains { day in
                day.events.contains { $0.text.plainText.contains(marker) }
            }
            guard hasMarker else { return published }
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
        #expect(await store.addEvent(on: LocalDay.today(), text: marker, time: nil))
        #expect(probe.builds >= 1)
        #expect(probe.offMain >= 1)
        #expect(probe.onMain == 0)
        #expect(
            store.content.days.contains { day in
                day.events.contains { $0.text.plainText == marker }
            })
    }
}
