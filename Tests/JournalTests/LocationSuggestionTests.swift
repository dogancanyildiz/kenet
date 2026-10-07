import EntityRecognition
import Foundation
import Testing
import VaultFormat

@testable import Journal

@MainActor
final class FakeLocationSource: LocationSource {
    var authorization = LocationAuthorization.notDetermined
    var onAuthorizationChange: (() -> Void)?
    var onLocation: ((PlaceCoordinate?) -> Void)?
    var accessRequests = 0
    var locationRequests = 0
    var fix: PlaceCoordinate? = PlaceCoordinate(latitude: 10.5, longitude: 20.029)
    func requestWhenInUseAuthorization() { accessRequests += 1 }
    func requestLocation() {
        locationRequests += 1
        onLocation?(fix)
    }
}

@Suite("Nearby places")
struct NearbyPlacesTests {
    func place(_ name: String, _ fields: String) throws -> NearbyPlace {
        try #require(
            NearbyPlace(
                entity: KnownEntity(file: "places/\(name).md", kind: .place, name: name),
                document: RawDocument(bytes: "---\ntype: place\nname: \(name)\n\(fields)\n---\n".utf8)))
    }

    @Test func sampleInsideAndOutside() throws {
        let office = try place("Liman Ofis", "coordinates: [10.5000, 20.0290]\nradius: 100")
        let gym = try place("Tepe Spor Salonu", "coordinates: [10.5210, 20.0415]\nradius: 80")
        #expect(NearbyPlaces.nearest(to: office.coordinate, among: [gym, office]) == office)
        #expect(NearbyPlaces.nearest(to: gym.coordinate, among: [office, gym]) == gym)
        #expect(
            NearbyPlaces.nearest(to: PlaceCoordinate(latitude: 10.502, longitude: 20.029), among: [office, gym]) == nil)
        #expect(NearbyPlaces.nearest(to: PlaceCoordinate(latitude: 10.5218, longitude: 20.0415), among: [gym]) == nil)
        #expect(
            abs(
                NearbyPlaces.distance(from: office.coordinate, to: PlaceCoordinate(latitude: 10.501, longitude: 20.029))
                    - 111.195) < 0.01)
    }

    @Test func nearestAndDefaultRadius() throws {
        let first = try place("A", "coordinates: [10.5000, 20.0290]")
        let second = try place("B", "coordinates: [10.5005, 20.0290]\nradius: 100")
        #expect(first.radius == 100)
        #expect(
            NearbyPlaces.nearest(to: PlaceCoordinate(latitude: 10.5004, longitude: 20.029), among: [first, second])
                == second)
    }

    @Test(arguments: [
        "", "coordinates: [91, 20]", "coordinates: [10, 181]", "coordinates: [10]",
        "coordinates: [10, 20]\nradius: -1", "coordinates: [10, 20]\nradius: wrong", "coordinates: [a, b]",
    ])
    func invalidOrMissingFields(_ fields: String) {
        let entity = KnownEntity(file: "places/No.md", kind: .place, name: "No")
        #expect(NearbyPlace(entity: entity, document: RawDocument(bytes: "---\n\(fields)\n---\n".utf8)) == nil)
    }

    @Test func datelineDistance() {
        let distance = NearbyPlaces.distance(
            from: PlaceCoordinate(latitude: 0, longitude: 179.999),
            to: PlaceCoordinate(latitude: 0, longitude: -179.999))
        #expect(abs(distance - 222.39) < 0.1)
    }
}

@MainActor @Suite("Location service")
struct LocationServiceTests {
    @Test(arguments: [LocationAuthorization.notDetermined, .denied, .restricted])
    func unauthorizedIsSilent(_ authorization: LocationAuthorization) throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let source = FakeLocationSource()
        source.authorization = authorization
        let service = LocationService(source: source, defaults: defaults.defaults)
        service.requestLocationIfNeeded()
        #expect(source.locationRequests == 0)
        #expect(source.accessRequests == 0)
        #expect(service.currentCoordinate == nil)
    }

    @Test func permissionOnlyOnButton() throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let source = FakeLocationSource()
        let service = LocationService(source: source, defaults: defaults.defaults)
        service.refreshAuthorization()
        #expect(source.accessRequests == 0)
        service.requestAccess()
        service.requestAccess()
        #expect(source.accessRequests == 1)
        source.authorization = .authorized
        source.onAuthorizationChange?()
        #expect(service.authorization == .authorized)
        #expect(!service.isRequesting)
        #expect(source.locationRequests == 0)
    }

    @Test func minuteLimitFailureAndToggle() throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let source = FakeLocationSource()
        source.authorization = .authorized
        var date = Date(timeIntervalSince1970: 1000)
        let service = LocationService(source: source, defaults: defaults.defaults, now: { date })
        service.requestLocationIfNeeded()
        service.requestLocationIfNeeded()
        #expect(source.locationRequests == 1)
        #expect(service.currentCoordinate == source.fix)
        date.addTimeInterval(59)
        service.requestLocationIfNeeded()
        #expect(source.locationRequests == 1)
        date.addTimeInterval(1)
        #expect(service.currentCoordinate == nil)
        source.fix = nil
        service.requestLocationIfNeeded()
        service.requestLocationIfNeeded()
        #expect(source.locationRequests == 2)
        #expect(service.currentCoordinate == nil)
        service.isEnabled = false
        date.addTimeInterval(60)
        service.requestLocationIfNeeded()
        #expect(source.locationRequests == 2)
        #expect(!LocationService(source: FakeLocationSource(), defaults: defaults.defaults).isEnabled)
    }

    @Test func revocationClearsFix() throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let source = FakeLocationSource()
        source.authorization = .authorized
        let service = LocationService(source: source, defaults: defaults.defaults)
        service.requestLocationIfNeeded()
        source.authorization = .denied
        source.onAuthorizationChange?()
        #expect(service.currentCoordinate == nil)
    }
}

@MainActor @Suite("Quick entry location")
struct QuickEntryLocationTests {
    @Test(arguments: [false, true])
    func pinnedPlaceSavedInBothModes(_ task: Bool) async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let source = FakeLocationSource()
        source.authorization = .authorized
        let location = LocationService(source: source, defaults: context.defaults.defaults)
        let model = context.model()
        model.locationService = location
        model.mode = task ? .task : .event
        model.text = "Çalıştım"
        model.focusLocation()
        #expect(model.suggestedPlace?.entity.name == "Liman Ofis")
        model.selectLocation()
        #expect(model.text == "Çalıştım @Liman Ofis")
        #expect(model.pins.last?.entity.file == "places/Liman Ofis.md")
        #expect(model.suggestedPlace == nil)
        #expect(await model.submit(time: nil))
        let document =
            task
            ? try context.document()
            : try RawDocument(
                bytes: Data(contentsOf: context.root.appendingPathComponent("journal/\(LocalDay.today()).md")))
        #expect(String(decoding: document.serialized(), as: UTF8.self).contains("Çalıştım [[Liman Ofis]]"))
        #expect(source.locationRequests == 1)
        #expect(model.suggestedPlace != nil)
    }

    @Test func dismissAndReloadCoordinates() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let source = FakeLocationSource()
        source.authorization = .authorized
        let model = context.model()
        model.locationService = LocationService(source: source, defaults: context.defaults.defaults)
        model.focusLocation()
        model.dismissLocation()
        model.text = "Yeni taslak"
        model.mode = .task
        model.focusLocation()
        #expect(model.suggestedPlace == nil)
        #expect(model.pins.isEmpty)
        let file = context.root.appendingPathComponent("places/Liman Ofis.md")
        let bytes = try Data(contentsOf: file)
        let changed = String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: "10.5000", with: "11.5000")
        try Data(changed.utf8).write(to: file)
        await context.store.refresh()
        #expect(context.store.nearbyPlaces.first { $0.entity.name == "Liman Ofis" }?.coordinate.latitude == 11.5)
        model.dismissedLocation = false
        #expect(model.suggestedPlace == nil)
    }

    @Test func duplicateNamePinsTheQualifiedFile() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let entity = try await context.store.createEntity(kind: .place, name: "Liman Ofis", qualifier: "iş")
        let bytes =
            "---\ntype: place\nname: Liman Ofis\nqualifier: iş\ncoordinates: [10.5210, 20.0415]\nradius: 80\n---\n"
        try Data(bytes.utf8).write(to: context.root.appendingPathComponent(entity.file))
        await context.store.refresh()
        let source = FakeLocationSource()
        source.authorization = .authorized
        source.fix = PlaceCoordinate(latitude: 10.521, longitude: 20.0415)
        let model = context.model()
        model.mode = .task
        model.locationService = LocationService(source: source, defaults: context.defaults.defaults)
        model.focusLocation()
        #expect(model.suggestedPlace?.entity.qualifier == "iş")
        model.selectLocation()
        #expect(model.text == "@Liman Ofis")
        #expect(model.pins.last?.entity == entity)
        #expect(await model.submit(time: nil))
        #expect(
            String(decoding: try context.document().serialized(), as: UTF8.self)
                .contains("[[Liman Ofis (iş)|Liman Ofis]]"))
    }

    @Test func sendingWithoutFocusRequestsFixButDoesNotInsert() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let source = FakeLocationSource()
        source.authorization = .authorized
        let model = context.model()
        model.mode = .task
        model.locationService = LocationService(source: source, defaults: context.defaults.defaults)
        model.text = "Oku"
        #expect(await model.submit(time: nil))
        #expect(source.locationRequests == 1)
        #expect(context.store.content.tasks.contains { $0.sourceText == "Oku" })
        #expect(model.pins.isEmpty)
    }
}
