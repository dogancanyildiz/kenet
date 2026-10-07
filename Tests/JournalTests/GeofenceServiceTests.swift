import Foundation
import GoalTracking
import Testing
import VaultFormat

@testable import Journal

@MainActor @Suite("Geofence regions")
struct GeofenceRegionTests {
    @Test func eligibleTargetsAndExplicitPermission() async throws {
        let context = try GeofenceTestContext()
        defer { context.clean() }
        context.source.authorization = .authorized
        await context.start()
        #expect(context.service.targets.count == 1)
        #expect(try context.target.place.entity.name == "Tepe Spor Salonu")
        #expect(context.service.regions.isEmpty)
        #expect(context.source.alwaysRequests == 0)
        context.service.requestAlwaysAccess()
        #expect(context.source.alwaysRequests == 1)
        context.source.authorization = .always
        context.source.onAuthorizationChange?()
        #expect(context.service.regions.count == 1)
        #expect(context.source.installed.first?.radius == 80)
        context.source.authorization = .denied
        context.source.onAuthorizationChange?()
        #expect(context.source.installed.isEmpty)
    }

    @Test(arguments: [LocationAuthorization.notDetermined, .authorized, .denied, .restricted])
    func noAlwaysPermissionHasNoRegions(_ authorization: LocationAuthorization) async throws {
        let context = try GeofenceTestContext()
        defer { context.clean() }
        context.source.authorization = authorization
        await context.start()
        #expect(context.source.installed.isEmpty)
        #expect(context.source.alwaysRequests == 0)
        #expect(context.source.whenInUseRequests == 0)
    }

    @Test func twentyLimitModesAndIndexRefresh() async throws {
        let context = try GeofenceTestContext()
        defer { context.clean() }
        await context.start()
        for index in 0..<22 {
            let text =
                "---\ntype: goal\nname: Goal \(index)\nkey: g-\(index)\nperiod: day\nkind: boolean\ntarget: 1\nplace: \"[[Tepe Spor Salonu]]\"\n---\n"
            try Data(text.utf8).write(to: context.vault.root.appendingPathComponent("goals/Extra \(index).md"))
        }
        await context.vault.store.refresh()
        #expect(context.service.targets.count == 23)
        #expect(context.service.regions.count == 20)
        #expect(context.service.overflowCount == 3)
        let target = try #require(context.service.regions.first)
        context.service.setMode(.off, for: target)
        #expect(context.service.regions.count == 20)
        #expect(context.service.overflowCount == 2)
        #expect(!context.source.installed.contains { $0.id == target.id })
        let newService = GeofenceService(
            location: context.location, center: context.center,
            defaults: context.vault.defaults.defaults)
        newService.attach(to: context.vault.store)
        newService.activate()
        #expect(newService.mode(for: target) == .off)
    }

    @Test func missingOrUnresolvedPlaceAndNumericGoalSkipped() async throws {
        let context = try GeofenceTestContext()
        defer { context.clean() }
        await context.start()
        let file = context.vault.root.appendingPathComponent("goals/Spor.md")
        let original = try String(contentsOf: file, encoding: .utf8)
        for text in [
            original.replacingOccurrences(of: "kind: boolean", with: "kind: number"),
            original.replacingOccurrences(of: "[[Tepe Spor Salonu]]", with: "[[Missing]]"),
            original.replacingOccurrences(of: "place: \"[[Tepe Spor Salonu]]\"", with: ""),
        ] {
            try Data(text.utf8).write(to: file)
            await context.vault.store.refresh()
            #expect(context.service.targets.isEmpty)
            #expect(context.source.installed.isEmpty)
        }
    }

    @Test func missingCoordinatesOrExplicitRadiusHasNoRegion() async throws {
        let context = try GeofenceTestContext()
        defer { context.clean() }
        await context.start()
        let file = context.vault.root.appendingPathComponent("places/Tepe Spor Salonu.md")
        let original = try String(contentsOf: file, encoding: .utf8)
        for text in [
            original.replacingOccurrences(of: "radius: 80\n", with: ""),
            original.replacingOccurrences(of: "coordinates: [10.5210, 20.0415]\n", with: ""),
        ] {
            try Data(text.utf8).write(to: file)
            await context.vault.store.refresh()
            #expect(context.service.targets.isEmpty)
            #expect(context.source.installed.isEmpty)
        }
    }

    @Test func alwaysAuthorizationStillAllowsQuickEntryFixes() throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let source = FakeLocationSource()
        source.authorization = .always
        let location = LocationService(source: source, defaults: defaults.defaults)
        location.requestLocationIfNeeded()
        #expect(source.locationRequests == 1)
        #expect(location.currentCoordinate == source.fix)
    }

    @Test func coordinateChangeReplacesRegionAndClampsRadius() async throws {
        let context = try GeofenceTestContext()
        defer { context.clean() }
        await context.start()
        let previous = try context.target.id
        let file = context.vault.root.appendingPathComponent("places/Tepe Spor Salonu.md")
        let text = try String(contentsOf: file, encoding: .utf8)
            .replacingOccurrences(of: "10.5210", with: "10.5310").replacingOccurrences(
                of: "radius: 80", with: "radius: 2000")
        try Data(text.utf8).write(to: file)
        await context.vault.store.refresh()
        #expect(try context.target.id != previous)
        #expect(try context.target.region.radius == 1000)
        #expect(context.source.installed.count == 1)
        #expect(!context.source.installed.contains { $0.id == previous })
    }
}
