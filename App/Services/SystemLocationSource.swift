import CoreLocation
import Foundation

@MainActor
final class SystemLocationSource: NSObject, LocationSource, CLLocationManagerDelegate {
    var onAuthorizationChange: (() -> Void)?
    var onRegionEntry: ((String) -> Void)?
    var onRegionFailure: (() -> Void)?
    var onLocation: ((PlaceCoordinate?) -> Void)?
    private lazy var manager: CLLocationManager = {
        let manager = CLLocationManager()
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.delegate = self
        return manager
    }()

    var authorization: LocationAuthorization {
        switch manager.authorizationStatus {
        case .notDetermined: .notDetermined
        case .authorizedAlways: .always
        case .authorizedWhenInUse: .authorized
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .restricted
        }
    }

    func requestWhenInUseAuthorization() { manager.requestWhenInUseAuthorization() }
    func requestLocation() { manager.requestLocation() }

    var supportsRegions: Bool {
        #if os(iOS)
            CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self)
        #else
            false
        #endif
    }
    var maximumRegionRadius: Double {
        #if os(iOS)
            let radius = manager.maximumRegionMonitoringDistance
            return radius > 0 ? radius : .infinity
        #else
            .infinity
        #endif
    }
    func requestAlwaysAuthorization() {
        #if os(iOS)
            manager.requestAlwaysAuthorization()
        #endif
    }
    func replaceRegions(_ regions: [GeofenceRegion]) {
        #if os(iOS)
            let existing = manager.monitoredRegions.filter { $0.identifier.hasPrefix(GeofenceRegion.prefix) }
            let identifiers = Set(regions.map(\.id))
            for region in existing where !identifiers.contains(region.identifier) {
                manager.stopMonitoring(for: region)
            }
            for value in regions where !existing.contains(where: { $0.identifier == value.id }) {
                let region = CLCircularRegion(
                    center: CLLocationCoordinate2D(
                        latitude: value.coordinate.latitude,
                        longitude: value.coordinate.longitude), radius: value.radius, identifier: value.id)
                region.notifyOnEntry = true
                region.notifyOnExit = false
                manager.startMonitoring(for: region)
            }
        #endif
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        let identifier = region.identifier
        Task { @MainActor [weak self] in self?.onRegionEntry?(identifier) }
    }
    nonisolated func locationManager(
        _ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: any Error
    ) {
        Task { @MainActor [weak self] in self?.onRegionFailure?() }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in self?.onAuthorizationChange?() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0,
            abs(location.timestamp.timeIntervalSinceNow) < 60
        else { return }
        let coordinate = PlaceCoordinate(
            latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        Task { @MainActor [weak self] in self?.onLocation?(coordinate) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        Task { @MainActor [weak self] in self?.onLocation?(nil) }
    }
}
