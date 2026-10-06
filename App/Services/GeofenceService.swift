import Foundation
import Observation
import VaultFormat
import VaultStore

@MainActor @Observable
final class GeofenceService {
    private(set) var targets: [GeofenceTarget] = []
    private(set) var regions: [GeofenceTarget] = []
    private(set) var overflowCount = 0
    private(set) var errorText: String?
    /// Shown on Today's goal strip only; other region errors stay in Settings via `errorText`.
    private(set) var lockedMarkNotice: String?
    private(set) var modes: [String: String]
    private(set) var isActive = false
    let location: LocationService
    @ObservationIgnored private let center: any GeofenceNotificationDelivering
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let today: () -> CalendarDate
    @ObservationIgnored private let allowsBackground: () -> Bool
    @ObservationIgnored private weak var store: IndexStore?
    @ObservationIgnored private var handling: Set<String> = []
    @ObservationIgnored private var isLocked: () -> Bool = { false }
    @ObservationIgnored private var isLockEnabled: () -> Bool = { false }
    @ObservationIgnored private var lockCoverID: UUID?
    /// Called when a mark action is blocked by app lock so the UI can open goals with an explanation.
    @ObservationIgnored var onLockedMarkBlocked: (() -> Void)?
    private static let modesKey = "journal.geofence.modes"
    private static let handledKey = "journal.geofence.handled"

    init(
        location: LocationService, center: any GeofenceNotificationDelivering,
        defaults: UserDefaults = .standard, today: @escaping () -> CalendarDate = { LocalDay.today() },
        allowsBackground: @escaping () -> Bool = { AppLaunchPolicy.allowsAutomaticStart() },
        isLocked: @escaping () -> Bool = { false },
        isLockEnabled: @escaping () -> Bool = { false }
    ) {
        self.location = location
        self.center = center
        self.defaults = defaults
        self.today = today
        self.allowsBackground = allowsBackground
        self.isLocked = isLocked
        self.isLockEnabled = isLockEnabled
        modes = defaults.dictionary(forKey: Self.modesKey) as? [String: String] ?? [:]
    }

    func attach(to store: IndexStore) {
        self.store = store
        store.onGeofenceSnapshotChange = { [weak self] in self?.rebuild() }
        location.onAuthorizationRefresh = { [weak self] in self?.rebuild() }
    }

    func attach(lock: AppLockService) {
        isLocked = { [weak lock] in
            guard let lock else {
                return UserDefaults.standard.bool(forKey: AppLockService.enabledKey)
            }
            return lock.isLockedNow()
        }
        isLockEnabled = { [weak lock] in
            lock?.isEnabled ?? UserDefaults.standard.bool(forKey: AppLockService.enabledKey)
        }
        if let lockCoverID { lock.unregisterCover(lockCoverID) }
        lockCoverID = lock.registerCover { [weak self, weak lock] in
            guard let self, let lock, !lock.isLockedNow() else { return }
            self.clearLockedMarkNotice()
        }
        refreshMarkActionAvailability()
    }

    func clearLockedMarkNotice() { lockedMarkNotice = nil }

    func refreshMarkActionAvailability() {
        if let scheduler = center as? SystemNotificationScheduler {
            scheduler.refreshGeofenceCategory(lockEnabled: isLockEnabled())
        }
    }

    func activateAutomatically() {
        #if os(iOS)
            guard allowsBackground() else { return }
            activate()
        #endif
    }

    func activate() {
        guard !isActive else { return }
        isActive = true
        center.activateGeofences { [weak self] action in await self?.respond(to: action) }
        location.source.onRegionEntry = { [weak self] identifier in
            Task { @MainActor [weak self] in await self?.enter(identifier) }
        }
        location.source.onRegionFailure = { [weak self] in
            self?.errorText = String(
                localized: "Konum bölgesi izlenemedi. Konum iznini ve sistem ayarlarını kontrol et.")
        }
        location.refreshAuthorization()
        rebuild()
    }

    func requestAlwaysAccess() {
        guard location.source.supportsRegions else { return }
        location.source.requestAlwaysAuthorization()
        location.refreshAuthorization()
    }

    private var vaultID: String? { store?.vaultURL.map(GeofencePlan.vaultID) }
    private func key(for target: GeofenceTarget, vaultID: String) -> String { vaultID + ":" + target.goal.key }
    func mode(for target: GeofenceTarget) -> GeofenceMode {
        guard let vaultID else { return .off }
        return modes[key(for: target, vaultID: vaultID)].flatMap(GeofenceMode.init(rawValue:)) ?? .notify
    }
    func setMode(_ mode: GeofenceMode, for target: GeofenceTarget) {
        guard let vaultID else { return }
        modes[key(for: target, vaultID: vaultID)] = mode.rawValue
        defaults.set(modes, forKey: Self.modesKey)
        rebuild()
    }

    func rebuild() {
        guard let store, let vaultID, store.lastUpdated != nil else {
            targets = []
            regions = []
            overflowCount = 0
            // Preserve OS registrations while a cold background launch opens its vault.
            if isActive && location.authorization != .always { location.source.replaceRegions([]) }
            return
        }
        targets = GeofencePlan.targets(
            snapshot: store.content, places: store.nearbyPlaces,
            vaultID: vaultID, maximumRadius: location.source.maximumRegionRadius)
        let enabled = targets.filter { mode(for: $0) != .off }
        overflowCount = max(0, enabled.count - 20)
        regions =
            isActive && location.authorization == .always && location.source.supportsRegions
            ? Array(enabled.prefix(20)) : []
        if isActive { location.source.replaceRegions(regions.map(\.region)) }
    }

    func enter(_ identifier: String) async {
        guard isActive, allowsBackground(), location.source.authorization == .always, let store else { return }
        #if os(iOS)
            let execution = GeofenceBackgroundExecution()
            defer { execution.end() }
        #endif
        do {
            try await store.prepareForBackground()
            location.refreshAuthorization()
            guard let vaultID, let target = regions.first(where: { $0.id == identifier }) else { return }
            let day = today()
            let token = key(for: target, vaultID: vaultID)
            guard !handling.contains(token), !hasHandled(token, on: day), !isMarked(target, on: day) else { return }
            handling.insert(token)
            defer { handling.remove(token) }
            errorText = nil
            let automatic = mode(for: target) == .automatic
            let action = GeofenceAction(regionID: identifier, vaultID: vaultID, day: day, mark: true)
            let hideContent = NotificationPreferences.read(from: defaults).hideContent
            if automatic {
                try await mark(target, on: day, vaultID: vaultID)
                remember(token, on: day)
                _ = try await center.sendGeofence(
                    GeofenceNotice(
                        action: action, goalName: target.goal.name,
                        placeName: target.place.entity.name, automatic: true, hideContent: hideContent))
            } else {
                let sent = try await center.sendGeofence(
                    GeofenceNotice(
                        action: action, goalName: target.goal.name,
                        placeName: target.place.entity.name, automatic: false, hideContent: hideContent))
                if sent { remember(token, on: day) }
            }
        } catch {
            errorText = String(localized: "Konum hedefi işlenemedi. Kasayı ve bildirim izinlerini kontrol et.")
        }
    }

    func respond(to action: GeofenceAction) async {
        guard action.mark, isActive, allowsBackground(), action.day == today(), let store else { return }
        if isLocked() {
            lockedMarkNotice = String(
                localized: "Günlük kilitliydi. Kilidi açtıktan sonra hedefi kendin işaretle.")
            onLockedMarkBlocked?()
            return
        }
        #if os(iOS)
            let execution = GeofenceBackgroundExecution()
            defer { execution.end() }
        #endif
        do {
            try await store.prepareForBackground()
            location.refreshAuthorization()
            guard vaultID == action.vaultID, location.authorization == .always,
                let target = regions.first(where: { $0.id == action.regionID }), mode(for: target) != .off,
                !isMarked(target, on: action.day)
            else { return }
            try await mark(target, on: action.day, vaultID: action.vaultID)
        } catch {
            errorText = String(localized: "Konum hedefi işlenemedi. Kasayı ve bildirim izinlerini kontrol et.")
        }
    }

    private func isMarked(_ target: GeofenceTarget, on day: CalendarDate) -> Bool {
        store?.content.goalLogs[target.goal.key]?.contains { $0.day == day && $0.value == .boolean(true) } == true
    }
    private func hasHandled(_ token: String, on day: CalendarDate) -> Bool {
        (defaults.dictionary(forKey: Self.handledKey) as? [String: String])?[token] == day.description
    }
    private func remember(_ token: String, on day: CalendarDate) {
        var values = defaults.dictionary(forKey: Self.handledKey) as? [String: String] ?? [:]
        values[token] = day.description
        defaults.set(values, forKey: Self.handledKey)
    }
    private func mark(_ target: GeofenceTarget, on day: CalendarDate, vaultID: String) async throws {
        guard self.vaultID == vaultID, let store, store.canAddEvent else { throw VaultStoreError.staleTarget }
        do { try await store.setGoal(on: day, key: target.goal.key, value: .boolean(true)) } catch VaultStoreError
            .indexUpdateFailed
        {
            // Bytes were saved; never repeat the operation.
        }
    }
}
