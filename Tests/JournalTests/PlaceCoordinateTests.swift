import CoreLocation
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

/// The editor's rules, apart from the view.
@MainActor @Suite("Place coordinate draft")
struct PlaceCoordinateDraftTests {
    private func context(coordinates: String) async throws -> (TaskTestContext, URL, EntityDetailModel) {
        let context = try TaskTestContext(sample: true)
        let file = context.root.appendingPathComponent("places/Liman Ofis.md")
        let original = try String(contentsOf: file, encoding: .utf8)
        try original.replacingOccurrences(of: "coordinates: [10.5000, 20.0290]", with: coordinates)
            .write(to: file, atomically: true, encoding: .utf8)
        await context.start()
        let model = EntityDetailModel(store: context.store, path: "places/Liman Ofis.md")
        await model.load()
        return (context, file, model)
    }

    @Test func untouchedSaveWritesNothingAndOneEditedFieldKeepsTheOthersDigits() async throws {
        let (context, file, model) = try await context(coordinates: "coordinates: [41.00820012345, 28.9]")
        defer { context.clean() }
        let bytes = try Data(contentsOf: file)
        #expect(model.coordinateSpellings == ["41.00820012345", "28.9"])
        var draft = PlaceCoordinateDraft(spellings: model.coordinateSpellings)
        #expect(draft.latitude == "41.00820012345" && draft.longitude == "28.9" && !draft.isDirty)
        #expect(draft.submit() == .unchanged)
        #expect(try Data(contentsOf: file) == bytes)

        draft.longitude = "29,25"
        #expect(draft.isDirty)
        let submission = draft.submit()
        #expect(submission == .write(latitude: "41.00820012345", longitude: "29.25"))
        guard case .write(let latitude, let longitude) = submission else { return }
        #expect(await model.saveCoordinate(latitude: latitude, longitude: longitude))
        draft.finishSave(latitude: draft.latitude, longitude: draft.longitude, success: true)
        #expect(!draft.isDirty)
        let expected = String(decoding: bytes, as: UTF8.self).replacingOccurrences(
            of: "[41.00820012345, 28.9]", with: "[41.00820012345, 29.25]")
        #expect(try String(contentsOf: file, encoding: .utf8) == expected)
        #expect(model.coordinateSpellings == ["41.00820012345", "29.25"])
    }

    @Test(arguments: [
        "coordinates: \"10.5, 20.029\"", "coordinates: [10.5, 20.029, 3]", "coordinates: [91, 20]",
    ])
    func unusableValueIsShownAndReplacedBySave(_ line: String) async throws {
        let (context, file, model) = try await context(coordinates: line)
        defer { context.clean() }
        #expect(model.hasCoordinatesField && model.coordinate == nil && model.coordinateSpellings == nil)
        #expect(model.coordinatesWritable && model.coordinatesSource == line)
        var draft = PlaceCoordinateDraft(spellings: model.coordinateSpellings)
        #expect(draft.latitude.isEmpty && draft.submit() == .invalid)
        draft.latitude = "10.5"
        draft.longitude = "20.029"
        #expect(draft.submit() == .write(latitude: "10.5", longitude: "20.029"))
        #expect(await model.saveCoordinate(latitude: "10.5", longitude: "20.029"))
        #expect(try String(contentsOf: file, encoding: .utf8).contains("\ncoordinates: [10.5, 20.029]\n"))
        #expect(model.coordinate == PlaceCoordinate(latitude: 10.5, longitude: 20.029))
        #expect(model.coordinatesSource == "coordinates: [10.5, 20.029]")
    }

    @Test func rawValueIsShownAsNotWritableAndStaysUntouched() async throws {
        let (context, file, model) = try await context(coordinates: "coordinates: [1, [2]]")
        defer { context.clean() }
        let bytes = try Data(contentsOf: file)
        #expect(model.hasCoordinatesField && model.coordinate == nil)
        #expect(!model.coordinatesWritable && model.coordinatesSource == "coordinates: [1, [2]]")
        #expect(await !model.saveCoordinate(latitude: "10.5", longitude: "20.029"))
        #expect(try Data(contentsOf: file) == bytes)
    }

    @Test func currentLocationFillsOnlyWhileTheUserWaits() {
        let point = PlaceCoordinate(latitude: 10.5, longitude: -20.029)
        var draft = PlaceCoordinateDraft()
        draft.fill(point)
        #expect(draft.latitude.isEmpty && !draft.isDirty)

        draft.requestFix()
        #expect(draft.status(canLocate: true, fixFailed: false) == .locating)
        draft.fill(nil)
        #expect(draft.awaitingFix)
        draft.fill(point)
        #expect(draft.latitude == "10.5" && draft.longitude == "-20.029" && draft.isDirty && !draft.awaitingFix)
        #expect(draft.status(canLocate: true, fixFailed: false) == .none)

        // Typing takes over: the failure hint goes and a late fix does not overwrite the text.
        draft.requestFix()
        #expect(draft.status(canLocate: true, fixFailed: true) == .fixFailed)
        draft.latitude = "11"
        #expect(!draft.awaitingFix && draft.status(canLocate: true, fixFailed: true) == .none)
        draft.fill(PlaceCoordinate(latitude: 1, longitude: 2))
        #expect(draft.latitude == "11" && draft.longitude == "-20.029")

        // Setting the same text (a view refresh) is not an edit.
        draft.requestFix()
        draft.longitude = "-20.029"
        #expect(draft.awaitingFix)
    }

    @Test func statusShowsWhatBlocksTheSaveFirst() {
        var draft = PlaceCoordinateDraft()
        #expect(draft.status(canLocate: true, fixFailed: true) == .none)
        #expect(draft.status(canLocate: false, fixFailed: false) == .cannotLocate)
        draft.requestFix()
        #expect(draft.status(canLocate: false, fixFailed: true) == .cannotLocate)
        draft.latitude = "10.5"
        draft.longitude = "20"
        #expect(draft.submit() == .write(latitude: "10.5", longitude: "20"))
        draft.finishSave(latitude: "10.5", longitude: "20", success: false)
        #expect(draft.isDirty && draft.saveFailed)
        #expect(draft.status(canLocate: false, fixFailed: true) == .saveFailed)
        draft.longitude = "200"
        #expect(draft.submit() == .invalid)
        #expect(draft.status(canLocate: false, fixFailed: true) == .invalid)
        draft.longitude = "20"
        #expect(draft.submit() == .write(latitude: "10.5", longitude: "20"))
        draft.finishSave(latitude: "10.5", longitude: "20", success: true)
        #expect(!draft.isDirty && draft.status(canLocate: true, fixFailed: false) == .none)
        #expect(draft.submit() == .unchanged)

        draft.latitude = "1"
        draft.removed()
        #expect(draft == PlaceCoordinateDraft())
        #expect(draft.latitude.isEmpty && !draft.isDirty && draft.submit() == .invalid)
    }

    @Test func typedAndMeasuredSpellingsKeepDigitsDropPlusAndWriteSignedZeroAsZero() {
        #expect(PlaceCoordinateInput.spelling(" 41,00820012345 ") == "41.00820012345")
        #expect(PlaceCoordinateInput.spelling("\u{2212}0.50") == "-0.50")
        #expect(PlaceCoordinateInput.spelling("041.5") == "41.5")
        #expect(PlaceCoordinateInput.spelling("00") == "0")
        #expect(PlaceCoordinateInput.spelling("1e5") == nil && PlaceCoordinateInput.spelling(".5") == nil)
        #expect(PlaceCoordinateInput.spelling("+41.5") == "41.5")
        for zero in ["-0", "-0.0", "+0", "+0.000", "\u{2212}00,0"] {
            #expect(PlaceCoordinateInput.spelling(zero) == "0")
        }
        #expect(PlaceCoordinateInput.spelling("-0.001") == "-0.001")
        var draft = PlaceCoordinateDraft()
        draft.latitude = "-0.0"
        draft.longitude = "+28.9"
        #expect(draft.submit() == .write(latitude: "0", longitude: "28.9"))
        #expect(PlaceCoordinateInput.text(-0.0) == "0")
        #expect(PlaceCoordinateInput.text(-0.0000001) == "0")
        let zero = PlaceCoordinate(latitude: -0.0, longitude: 0)
        #expect(PlaceCoordinateInput.literals(zero) == [.number("0"), .number("0")])
    }
}

@MainActor @Suite("Location request state")
struct LocationRequestStateTests {
    @Test func unansweredRequestStopsBlockingAfterTheTimeout() throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let source = SlowLocationSource()
        var date = Date(timeIntervalSince1970: 1000)
        let service = LocationService(source: source, defaults: defaults.defaults, now: { date })
        service.requestLocationIfNeeded(userInitiated: true)
        date.addTimeInterval(LocationService.answerTimeout - 1)
        service.requestLocationIfNeeded(userInitiated: true)
        #expect(source.locationRequests == 1 && service.isLocating)
        date.addTimeInterval(1)
        service.requestLocationIfNeeded(userInitiated: true)
        #expect(source.locationRequests == 2 && service.isLocating)
    }

    @Test func clockSetBackDoesNotKeepTheRequestPending() throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let source = SlowLocationSource()
        var date = Date(timeIntervalSince1970: 100_000)
        let service = LocationService(source: source, defaults: defaults.defaults, now: { date })
        service.requestLocationIfNeeded(userInitiated: true)
        date.addTimeInterval(-3600)
        service.requestLocationIfNeeded(userInitiated: true)
        #expect(source.locationRequests == 2 && service.isLocating)
        // From the new start the usual wait applies again.
        date.addTimeInterval(-1)
        service.requestLocationIfNeeded(userInitiated: true)
        #expect(source.locationRequests == 2)
    }

    @Test func answerWhileDisabledOrUnauthorizedEndsThePendingRequest() throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let source = SlowLocationSource()
        let service = LocationService(source: source, defaults: defaults.defaults)
        let point = PlaceCoordinate(latitude: 10.5, longitude: 20.029)
        service.requestLocationIfNeeded(userInitiated: true)
        service.isEnabled = false
        source.onLocation?(point)
        #expect(!service.isLocating && service.coordinate == nil && !service.lastRequestFailed)

        service.isEnabled = true
        service.requestLocationIfNeeded(userInitiated: true)
        #expect(service.isLocating)
        // The permission went away without the change callback; the answer still ends the wait.
        source.authorization = .denied
        source.onLocation?(point)
        #expect(!service.isLocating)
    }

    @Test func newRequestClearsTheEarlierFailure() throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let source = SlowLocationSource()
        let service = LocationService(source: source, defaults: defaults.defaults)
        service.requestLocationIfNeeded(userInitiated: true)
        source.onLocation?(nil)
        #expect(service.lastRequestFailed && !service.isLocating)
        service.requestLocationIfNeeded(userInitiated: true)
        #expect(!service.lastRequestFailed && service.isLocating && source.locationRequests == 2)
    }

    @Test func systemAnswerIsAFixOnlyWhenMeasuredWithinTheLastMinute() {
        let now = Date(timeIntervalSince1970: 10_000)
        func location(age: TimeInterval, accuracy: Double = 50) -> CLLocation {
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 10.5, longitude: 20.029), altitude: 0,
                horizontalAccuracy: accuracy, verticalAccuracy: 0, timestamp: now.addingTimeInterval(-age))
        }
        let point = PlaceCoordinate(latitude: 10.5, longitude: 20.029)
        #expect(SystemLocationSource.fix(from: location(age: 0), now: now) == point)
        #expect(SystemLocationSource.fix(from: location(age: 59), now: now) == point)
        #expect(SystemLocationSource.fix(from: location(age: 60), now: now) == nil)
        #expect(SystemLocationSource.fix(from: location(age: 3600), now: now) == nil)
        #expect(SystemLocationSource.fix(from: location(age: 0, accuracy: -1), now: now) == nil)
        #expect(SystemLocationSource.fix(from: nil, now: now) == nil)
    }
}

@Suite("Place coordinate length")
struct PlaceCoordinateLengthTests {
    @Test func tooManyFractionDigitsAreRefusedButAnUntouchedFileValueIsKept() {
        let limit = String(repeating: "1", count: PlaceCoordinateInput.maximumFractionDigits)
        #expect(PlaceCoordinateInput.spelling("41." + limit) == "41." + limit)
        #expect(PlaceCoordinateInput.spelling("41." + limit + "1") == nil)
        #expect(PlaceCoordinateInput.spelling("41." + String(repeating: "7", count: 5000)) == nil)
        #expect(PlaceCoordinateInput.coordinate(latitude: "41." + limit + "1", longitude: "28") == nil)
        #expect(PlaceCoordinateInput.coordinate(latitude: String(repeating: "9", count: 5000), longitude: "28") == nil)

        var typed = PlaceCoordinateDraft()
        typed.latitude = "41." + limit + "1"
        typed.longitude = "28.9"
        #expect(typed.submit() == .invalid && typed.invalid)

        // A long value already in the file is not the user's input: editing the other field
        // keeps it byte for byte.
        let long = "41." + String(repeating: "3", count: 40)
        var stored = PlaceCoordinateDraft(spellings: [long, "28.9"])
        #expect(stored.submit() == .unchanged)
        stored.longitude = "29"
        #expect(stored.submit() == .write(latitude: long, longitude: "29"))
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
