import Foundation
import Observation

enum LocationAuthorization {
    case notDetermined, authorized, always, denied, restricted
    var canLocate: Bool { self == .authorized || self == .always }
}

@MainActor
protocol LocationSource: AnyObject {
    var authorization: LocationAuthorization { get }
    var onAuthorizationChange: (() -> Void)? { get set }
    var onLocation: ((PlaceCoordinate?) -> Void)? { get set }
    func requestWhenInUseAuthorization()
    func requestLocation()
    var supportsRegions: Bool { get }
    var maximumRegionRadius: Double { get }
    var onRegionEntry: ((String) -> Void)? { get set }
    var onRegionFailure: (() -> Void)? { get set }
    func requestAlwaysAuthorization()
    func replaceRegions(_ regions: [GeofenceRegion])
}

extension LocationSource {
    var supportsRegions: Bool { false }
    var maximumRegionRadius: Double { .infinity }
    var onRegionEntry: ((String) -> Void)? {
        get { nil }
        set {}
    }
    var onRegionFailure: (() -> Void)? {
        get { nil }
        set {}
    }
    func requestAlwaysAuthorization() {}
    func replaceRegions(_ regions: [GeofenceRegion]) {}
}

@MainActor @Observable
final class LocationService {
    private(set) var authorization = LocationAuthorization.notDetermined
    private(set) var isRequesting = false
    @ObservationIgnored var onAuthorizationRefresh: (() -> Void)?
    private(set) var coordinate: PlaceCoordinate?
    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.preferenceKey)
            if !isEnabled { coordinate = nil }
        }
    }
    static let preferenceKey = "journal.locationSuggestions.enabled"
    @ObservationIgnored let source: any LocationSource
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var lastAttempt: Date?
    private var lastFix: Date?

    init(
        source: any LocationSource = SystemLocationSource(), defaults: UserDefaults = .standard,
        now: @escaping () -> Date = { Date() }
    ) {
        self.source = source
        self.defaults = defaults
        self.now = now
        isEnabled = defaults.object(forKey: Self.preferenceKey) as? Bool ?? true
        source.onAuthorizationChange = { [weak self] in self?.refreshAuthorization() }
        source.onLocation = { [weak self] value in
            guard let self, self.isEnabled, self.authorization.canLocate else { return }
            self.coordinate = value?.isValid == true ? value : nil
            self.lastFix = self.coordinate == nil ? nil : self.now()
        }
    }

    var currentCoordinate: PlaceCoordinate? {
        guard isEnabled, authorization.canLocate, let lastFix,
            (0..<60).contains(now().timeIntervalSince(lastFix))
        else { return nil }
        return coordinate
    }

    func refreshAuthorization() {
        authorization = source.authorization
        if authorization != .notDetermined { isRequesting = false }
        if !authorization.canLocate { coordinate = nil }
        onAuthorizationRefresh?()
    }

    /// Called only by the explicit Settings permission button.
    func requestAccess() {
        refreshAuthorization()
        guard authorization == .notDetermined, !isRequesting else { return }
        isRequesting = true
        source.requestWhenInUseAuthorization()
        refreshAuthorization()
    }

    /// Starts a single fix without delaying entry submission or asking for permission.
    func requestLocationIfNeeded() {
        guard isEnabled else { return }
        refreshAuthorization()
        guard authorization.canLocate else { return }
        let date = now()
        if let lastAttempt, date.timeIntervalSince(lastAttempt) < 60 { return }
        lastAttempt = date
        source.requestLocation()
    }
}
