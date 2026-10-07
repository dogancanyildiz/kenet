import EntityRecognition
import Foundation
import Testing
import VaultFormat

@testable import Journal

/// A place created in the app had no way to receive coordinates, so the map stayed empty
/// whatever the location permission was.
@MainActor @Suite("Place coordinates")
struct PlaceCoordinateTests {
    @Test func createdPlaceReceivesCoordinatesAndAppearsOnMap() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let created = try await context.store.createEntity(kind: .place, name: "Kurgu Kafe", qualifier: nil)
        #expect(PlacesMapModel.pins(places: context.store.mapPlaces, usage: context.store.entityUsage).isEmpty)
        #expect(
            PlacesMapModel.withoutCoordinates(entities: context.store.knownEntities, places: context.store.mapPlaces)
                .map(\.file) == [created.file])

        let model = EntityDetailModel(store: context.store, path: created.file)
        await model.load()
        #expect(model.coordinate == nil && !model.hasCoordinatesField)
        let point = try #require(PlaceCoordinateInput.coordinate(latitude: "10,5", longitude: " 20.029 "))
        #expect(await model.saveCoordinate(point))

        #expect(model.coordinate == PlaceCoordinate(latitude: 10.5, longitude: 20.029))
        #expect(model.hasCoordinatesField)
        let written = try String(contentsOf: context.root.appendingPathComponent(created.file), encoding: .utf8)
        #expect(written.contains("\ncoordinates: [10.5, 20.029]\n"))
        let pins = PlacesMapModel.pins(places: context.store.mapPlaces, usage: context.store.entityUsage)
        #expect(pins.map(\.id) == [created.file])
        #expect(pins.first?.coordinate == point)
        #expect(
            PlacesMapModel.withoutCoordinates(entities: context.store.knownEntities, places: context.store.mapPlaces)
                .isEmpty)
    }

    @Test func savingReplacesAnUnusableValueAndKeepsTheRestOfTheFile() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        let file = context.root.appendingPathComponent("places/Liman Ofis.md")
        let original = try String(contentsOf: file, encoding: .utf8)
        // What "Alan ekle" writes when the pair is typed as text: not a coordinate for the map.
        let typed = original.replacingOccurrences(
            of: "coordinates: [10.5000, 20.0290]", with: "coordinates: \"10.5, 20.029\"")
        try typed.write(to: file, atomically: true, encoding: .utf8)
        await context.start()
        let model = EntityDetailModel(store: context.store, path: "places/Liman Ofis.md")
        await model.load()
        #expect(model.coordinate == nil && model.hasCoordinatesField)
        #expect(!context.store.mapPlaces.contains { $0.entity.file == "places/Liman Ofis.md" })

        #expect(await model.saveCoordinate(PlaceCoordinate(latitude: -33.5, longitude: 151)))
        #expect(
            try String(contentsOf: file, encoding: .utf8)
                == original.replacingOccurrences(of: "[10.5000, 20.0290]", with: "[-33.5, 151]"))
        #expect(context.store.mapPlaces.contains { $0.entity.file == "places/Liman Ofis.md" })
    }

    @Test func inputAcceptsDecimalCommaAndRejectsWhatTheMapCannotShow() {
        #expect(
            PlaceCoordinateInput.coordinate(latitude: "41,0082", longitude: "28.9784")
                == PlaceCoordinate(latitude: 41.0082, longitude: 28.9784))
        #expect(
            PlaceCoordinateInput.coordinate(latitude: "\u{2212}33.5", longitude: "+151")
                == PlaceCoordinate(latitude: -33.5, longitude: 151))
        for (latitude, longitude) in [
            ("", "20"), ("10", ""), ("91", "20"), ("10", "181"), ("1e1", "20"), ("10.", "20"), ("on", "20"),
            ("10 5", "20"), ("10.5.1", "20"),
        ] {
            #expect(PlaceCoordinateInput.coordinate(latitude: latitude, longitude: longitude) == nil)
        }
    }

    @Test func writtenSpellingIsPlainAndRoundTrips() {
        #expect(PlaceCoordinateInput.text(41.0082) == "41.0082")
        #expect(PlaceCoordinateInput.text(-0.1275) == "-0.1275")
        #expect(PlaceCoordinateInput.text(151) == "151")
        #expect(PlaceCoordinateInput.text(10.123456789) == "10.123457")
        #expect(PlaceCoordinateInput.text(0.00000001) == "0")
        let point = PlaceCoordinate(latitude: 10.5, longitude: -20.029)
        #expect(
            PlaceCoordinateInput.coordinate(
                latitude: PlaceCoordinateInput.text(point.latitude),
                longitude: PlaceCoordinateInput.text(point.longitude)) == point)
        #expect(PlaceCoordinateInput.literals(point) == [.number("10.5"), .number("-20.029")])
    }

    @Test func placesWithoutCoordinatesAreListedByName() {
        let office = KnownEntity(file: "places/Ofis.md", kind: .place, name: "Ofis")
        let cafe = KnownEntity(file: "places/Kafe.md", kind: .place, name: "Kafe")
        let person = KnownEntity(file: "people/Ada.md", kind: .person, name: "Ada")
        let invalid = MapPlace(entity: office, coordinate: PlaceCoordinate(latitude: 91, longitude: 0))
        #expect(
            PlacesMapModel.withoutCoordinates(entities: [office, person, cafe], places: [invalid]).map(\.name)
                == ["Kafe", "Ofis"])
        let valid = MapPlace(entity: office, coordinate: PlaceCoordinate(latitude: 1, longitude: 2))
        #expect(
            PlacesMapModel.withoutCoordinates(entities: [office, person, cafe], places: [valid]).map(\.name)
                == ["Kafe"])
    }
}

/// On a device the fix arrives seconds after the tap, or not at all; an explicit button must
/// neither stay dead for a minute nor wait forever.
@MainActor @Suite("Explicit location request")
struct ExplicitLocationRequestTests {
    @Test func failedFixIsReportedAndTheButtonRetriesWithinTheMinute() throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let source = FakeLocationSource()
        source.authorization = .authorized
        source.fix = nil
        let date = Date(timeIntervalSince1970: 1000)
        let service = LocationService(source: source, defaults: defaults.defaults, now: { date })
        service.requestLocationIfNeeded(userInitiated: true)
        #expect(source.locationRequests == 1)
        #expect(service.lastRequestFailed && !service.isLocating && service.currentCoordinate == nil)

        // The automatic suggestion keeps its one-request-per-minute limit.
        service.requestLocationIfNeeded()
        #expect(source.locationRequests == 1)

        source.fix = PlaceCoordinate(latitude: 10.5, longitude: 20.029)
        service.requestLocationIfNeeded(userInitiated: true)
        #expect(source.locationRequests == 2)
        #expect(!service.lastRequestFailed && service.currentCoordinate == source.fix)

        // A fresh fix is reused; tapping again does not ask the system once more.
        service.requestLocationIfNeeded(userInitiated: true)
        #expect(source.locationRequests == 2)
    }

    @Test func pendingRequestIsNotStackedAndEveryFixIsObservable() throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let source = SlowLocationSource()
        var date = Date(timeIntervalSince1970: 1000)
        let service = LocationService(source: source, defaults: defaults.defaults, now: { date })
        service.requestLocationIfNeeded(userInitiated: true)
        service.requestLocationIfNeeded(userInitiated: true)
        #expect(source.locationRequests == 1)
        #expect(service.isLocating && !service.lastRequestFailed && service.currentCoordinate == nil)

        let point = PlaceCoordinate(latitude: 10.5, longitude: 20.029)
        source.onLocation?(point)
        #expect(!service.isLocating && service.currentCoordinate == point)
        let first = try #require(service.lastFix)

        // The same coordinate measured again later is still a new fix for observers.
        date.addTimeInterval(90)
        #expect(service.currentCoordinate == nil)
        service.requestLocationIfNeeded(userInitiated: true)
        source.onLocation?(point)
        #expect(source.locationRequests == 2)
        #expect(service.currentCoordinate == point && service.lastFix != first)
    }

    @Test func permissionLossEndsThePendingRequest() throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let source = SlowLocationSource()
        let service = LocationService(source: source, defaults: defaults.defaults)
        service.requestLocationIfNeeded(userInitiated: true)
        source.authorization = .denied
        source.onAuthorizationChange?()
        #expect(!service.isLocating)
        service.requestLocationIfNeeded(userInitiated: true)
        #expect(source.locationRequests == 1)
    }
}

/// Answers only when the test delivers a fix, like a real device.
@MainActor
private final class SlowLocationSource: LocationSource {
    var authorization = LocationAuthorization.authorized
    var onAuthorizationChange: (() -> Void)?
    var onLocation: ((PlaceCoordinate?) -> Void)?
    var locationRequests = 0
    func requestWhenInUseAuthorization() {}
    func requestLocation() { locationRequests += 1 }
}
