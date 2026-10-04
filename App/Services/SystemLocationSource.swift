import CoreLocation
import Foundation

@MainActor
final class SystemLocationSource: NSObject, LocationSource, CLLocationManagerDelegate {
    var onAuthorizationChange: (() -> Void)?
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
        case .authorizedAlways, .authorizedWhenInUse: .authorized
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .restricted
        }
    }

    func requestWhenInUseAuthorization() { manager.requestWhenInUseAuthorization() }
    func requestLocation() { manager.requestLocation() }

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
