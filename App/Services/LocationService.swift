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
    /// A fix was asked for and the system has not answered yet.
    private(set) var isLocating = false
    /// The last answer carried no usable fix.
    private(set) var lastRequestFailed = false
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
    /// A source that never answers must not block the button for good.
    static let answerTimeout: TimeInterval = 30
    /// Changes with every fix, also when the measured coordinate is the same as before.
    private(set) var lastFix: Date?

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
            guard let self else { return }
            self.isLocating = false
            guard self.isEnabled, self.authorization.canLocate else { return }
            self.coordinate = value?.isValid == true ? value : nil
            self.lastFix = self.coordinate == nil ? nil : self.now()
            self.lastRequestFailed = self.coordinate == nil
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
        if !authorization.canLocate {
            coordinate = nil
            isLocating = false
        }
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
    ///
    /// The automatic request (quick entry focus) is limited to one a minute. A button the user
    /// taps (`userInitiated`) is not: it asks again unless a request is pending or a fresh fix
    /// is already there, so a failed or slow first answer does not leave the button dead.
    /// A request unanswered for `answerTimeout` no longer counts as pending.
    func requestLocationIfNeeded(userInitiated: Bool = false) {
        guard isEnabled else { return }
        refreshAuthorization()
        guard authorization.canLocate else { return }
        let date = now()
        if userInitiated {
            let pending = isLocating && date.timeIntervalSince(lastAttempt ?? date) < Self.answerTimeout
            guard !pending, currentCoordinate == nil else { return }
        } else if let lastAttempt, date.timeIntervalSince(lastAttempt) < 60 {
            return
        }
        lastAttempt = date
        isLocating = true
        lastRequestFailed = false
        source.requestLocation()
    }
}
