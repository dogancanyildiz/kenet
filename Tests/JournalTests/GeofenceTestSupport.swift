import Foundation
import Testing
import VaultFormat

@testable import Journal

@MainActor
final class FakeRegionSource: LocationSource {
    var authorization = LocationAuthorization.always
    var supportsRegions = true
    var maximumRegionRadius = 1000.0
    var onAuthorizationChange: (() -> Void)?
    var onLocation: ((PlaceCoordinate?) -> Void)?
    var onRegionEntry: ((String) -> Void)?
    var onRegionFailure: (() -> Void)?
    var installed: [GeofenceRegion] = []
    var alwaysRequests = 0
    var whenInUseRequests = 0
    func requestWhenInUseAuthorization() { whenInUseRequests += 1 }
    func requestLocation() {}
    func requestAlwaysAuthorization() { alwaysRequests += 1 }
    func replaceRegions(_ regions: [GeofenceRegion]) { installed = regions }
}

@MainActor
final class FakeGeofenceCenter: GeofenceNotificationDelivering {
    var notices: [GeofenceNotice] = []
    var response: (@MainActor @Sendable (GeofenceAction) async -> Void)?
    var canNotify = true
    var fails = false
    var paused: CheckedContinuation<Void, Never>?
    var pauseNext = false
    func activateGeofences(response: @escaping @MainActor @Sendable (GeofenceAction) async -> Void) {
        self.response = response
    }
    func sendGeofence(_ notice: GeofenceNotice) async throws -> Bool {
        if pauseNext {
            pauseNext = false
            await withCheckedContinuation { paused = $0 }
        }
        if fails { throw CocoaError(.fileWriteUnknown) }
        guard canNotify else { return false }
        notices.append(notice)
        return true
    }
}

@MainActor
struct GeofenceTestContext {
    let vault: TaskTestContext
    let source = FakeRegionSource()
    let center = FakeGeofenceCenter()
    let location: LocationService
    let service: GeofenceService
    init(allowed: Bool = true) throws {
        let vault = try TaskTestContext(sample: true)
        self.vault = vault
        location = LocationService(source: source, defaults: vault.defaults.defaults)
        service = GeofenceService(
            location: location, center: center, defaults: vault.defaults.defaults,
            today: { CalendarDate("2026-10-04")! }, allowsBackground: { allowed })
        service.attach(to: vault.store)
    }
    func start() async {
        service.activate()
        await vault.store.select(vault.root)
    }
    var target: GeofenceTarget { get throws { try #require(service.targets.first { $0.goal.key == "spor" }) } }
    func clean() { vault.clean() }
    func bytes(_ day: String = "2026-10-04") throws -> Data {
        try Data(contentsOf: vault.root.appendingPathComponent("journal/\(day).md"))
    }
}
