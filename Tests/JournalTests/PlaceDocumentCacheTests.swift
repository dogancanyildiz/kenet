import EntityRecognition
import Foundation
import Testing
import VaultFormat

@testable import Journal

/// After every write the place files are read for coordinates. An unchanged file is not read again;
/// a file changed outside the app, or a place renamed onto another's path, is.
@MainActor
struct PlaceDocumentCacheTests {
    private static let office = "places/Liman Ofis.md"

    /// A coordinated read of the place reaches its presenter as `toReader`; none means no read.
    @Test func aWriteDoesNotReadAnUnchangedPlaceAgain() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let probe = PresenterProbe(context.root.appendingPathComponent(Self.office))
        defer { probe.remove() }

        #expect(await context.store.addEvent(on: context.today, text: "kurgu olay", time: nil))
        #expect(await context.store.addEvent(on: context.today, text: "ikinci olay", time: nil))

        #expect(probe.drain().filter { $0 == "toReader" }.isEmpty)
        #expect(Self.officePlace(in: context)?.coordinate == PlaceCoordinate(latitude: 10.5, longitude: 20.029))
    }

    /// Same size, written in place, no refresh: the next write still shows the new coordinates.
    @Test func aPlaceChangedOutsideTheAppIsReadAgainByTheNextWrite() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let url = context.root.appendingPathComponent(Self.office)
        let probe = PresenterProbe(url)
        defer { probe.remove() }
        let original = try Data(contentsOf: url)
        let changed = Data(
            String(decoding: original, as: UTF8.self).replacingOccurrences(of: "10.5000", with: "11.5000").utf8)
        #expect(changed.count == original.count && changed != original)
        try changed.write(to: url)

        #expect(await context.store.addEvent(on: context.today, text: "kurgu olay", time: nil))

        #expect(probe.drain().filter { $0 == "toReader" }.count == 1)
        #expect(Self.officePlace(in: context)?.coordinate == PlaceCoordinate(latitude: 11.5, longitude: 20.029))
        #expect(context.store.mapPlaces.first { $0.entity.file == Self.office }?.coordinate.latitude == 11.5)
    }

    /// A tool that writes in place and then puts the old modification time back leaves the same
    /// size, inode and modification time; only the status change time moves. The file is read again.
    @Test func aPlaceWrittenBackToItsOldModificationTimeIsReadAgain() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let url = context.root.appendingPathComponent(Self.office)
        var before = stat()
        #expect(stat(url.path, &before) == 0)
        let original = try Data(contentsOf: url)
        try Data(String(decoding: original, as: UTF8.self).replacingOccurrences(of: "10.5000", with: "12.5000").utf8)
            .write(to: url)
        var times = [before.st_atimespec, before.st_mtimespec]
        #expect(utimensat(AT_FDCWD, url.path, &times, 0) == 0)
        var after = stat()
        #expect(stat(url.path, &after) == 0)
        #expect(after.st_ino == before.st_ino && after.st_size == before.st_size)
        #expect(after.st_mtimespec.tv_sec == before.st_mtimespec.tv_sec)
        #expect(after.st_mtimespec.tv_nsec == before.st_mtimespec.tv_nsec)

        #expect(await context.store.addEvent(on: context.today, text: "kurgu olay", time: nil))

        #expect(Self.officePlace(in: context)?.coordinate == PlaceCoordinate(latitude: 12.5, longitude: 20.029))
    }

    /// One place renamed away, another renamed onto its path: each path shows its own file.
    @Test func renamedPlacesShowTheFileNowAtEachPath() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let store = context.store

        let moved = try await store.renameEntity(at: Self.office, to: "Liman Merkez", qualifier: nil)
        #expect(moved.path == "places/Liman Merkez.md" && moved.failures.isEmpty)
        let onto = try await store.renameEntity(at: "places/Tepe Spor Salonu.md", to: "Liman Ofis", qualifier: nil)
        #expect(onto.path == Self.office && onto.failures.isEmpty)

        let places = Dictionary(uniqueKeysWithValues: store.nearbyPlaces.map { ($0.entity.file, $0) })
        #expect(places["places/Liman Merkez.md"]?.coordinate == PlaceCoordinate(latitude: 10.5, longitude: 20.029))
        #expect(places["places/Liman Merkez.md"]?.radius == 100)
        #expect(places[Self.office]?.coordinate == PlaceCoordinate(latitude: 10.521, longitude: 20.0415))
        #expect(places[Self.office]?.radius == 80)
        #expect(places["places/Tepe Spor Salonu.md"] == nil)
        #expect(Set(store.mapPlaces.map(\.entity.file)) == ["places/Liman Merkez.md", Self.office])
    }

    /// Forty writes, each after an outside change (same size in place, replaced, deleted and written
    /// anew, none): every write shows exactly the places a fresh read of the disk gives.
    @Test func everyWriteShowsThePlacesOnDisk() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let office = context.root.appendingPathComponent(Self.office)
        let home = context.root.appendingPathComponent("places/Ev.md")
        let cafe = context.root.appendingPathComponent("places/Çınaraltı Kafe.md")
        let officeText = String(decoding: try Data(contentsOf: office), as: UTF8.self)
        for round in 0..<40 {
            switch round % 4 {
            case 0:
                let latitude = "1\(round % 10).5000"
                try Data(officeText.replacingOccurrences(of: "10.5000", with: latitude).utf8).write(to: office)
            case 1:
                let text =
                    "---\ntype: place\nname: Ev\naliases: []\ncoordinates: [41.0, 29.0]\nradius: \(round + 1)\n---\n"
                try Data(text.utf8).write(to: home, options: .atomic)
            case 2:
                try FileManager.default.removeItem(at: cafe)
                let text = "---\ntype: place\nname: Çınaraltı Kafe\naliases: []\ncoordinates: [\(round).0, 30.0]\n---\n"
                try Data(text.utf8).write(to: cafe)
            default: break
            }

            #expect(await context.store.addEvent(on: context.today, text: "tur \(round)", time: nil))

            let onDisk = try Self.diskDocuments(in: context)
            let nearby = onDisk.compactMap { NearbyPlace(entity: $0.entity, document: $0.document) }
            let mapped = onDisk.compactMap { place in
                PlaceCoordinate(document: place.document).map { "\(place.entity.file) \($0)" }
            }
            #expect(context.store.nearbyPlaces == nearby, "round \(round)")
            #expect(context.store.mapPlaces.map { "\($0.entity.file) \($0.coordinate)" } == mapped, "round \(round)")
        }
    }

    private static func diskDocuments(in context: TaskTestContext) throws -> [(
        entity: KnownEntity, document: RawDocument
    )] {
        try context.store.knownEntities.filter { $0.kind == .place }.map { entity in
            let bytes = try Data(contentsOf: context.root.appendingPathComponent(entity.file))
            return (entity, RawDocument(bytes: Array(bytes)))
        }
    }

    private static func officePlace(in context: TaskTestContext) -> NearbyPlace? {
        context.store.nearbyPlaces.first { $0.entity.file == office }
    }
}
