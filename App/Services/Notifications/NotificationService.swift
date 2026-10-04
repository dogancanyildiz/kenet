import Foundation
import Observation

/// A single scheduling writer: canceled debounce tasks never cancel an in-flight center operation.
@MainActor @Observable
final class NotificationService {
    private(set) var authorization = NotificationAuthorization.notDetermined
    private(set) var pending: [NotificationRequest] = []
    private(set) var isRequesting = false
    private(set) var isPlanning = false
    private(set) var errorText: String?
    private(set) var navigationRequest: NotificationNavigationRequest?
    var preferences: NotificationPreferences {
        didSet {
            guard preferences != oldValue else { return }
            preferences.persist(in: defaults)
            queueReplan(after: .zero)
        }
    }
    @ObservationIgnored private let center: any NotificationScheduling
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let timeZone: () -> TimeZone
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var snapshot: VaultReadModel?
    @ObservationIgnored private var vaultID: String?
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var needsReplan = false
    @ObservationIgnored private var active = false

    init(
        center: any NotificationScheduling = SystemNotificationScheduler(), defaults: UserDefaults = .standard,
        now: @escaping () -> Date = { Date() }, timeZone: @escaping () -> TimeZone = { .current },
        debounce: Duration = .seconds(2)
    ) {
        self.center = center
        self.defaults = defaults
        self.now = now
        self.timeZone = timeZone
        self.debounce = debounce
        preferences = NotificationPreferences.read(from: defaults)
    }

    /// Attach before opening the vault, including menu-bar-only startup.
    func attach(to store: IndexStore) {
        store.onSnapshotChange = { [weak self] content, root in self?.update(snapshot: content, vaultID: root?.path) }
        update(snapshot: store.lastUpdated == nil ? nil : store.content, vaultID: store.vaultURL?.path)
    }
    func activateAutomatically(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        guard AppLaunchPolicy.allowsAutomaticStart(environment: environment, arguments: arguments) else { return }
        activate()
        queueReplan(after: .zero)
    }
    private func activate() {
        guard !active else { return }
        active = true
        center.activate { [weak self] destination in
            self?.navigationRequest = NotificationNavigationRequest(destination: destination)
        }
    }
    func update(snapshot: VaultReadModel?, vaultID: String?) {
        let changedVault = self.vaultID != vaultID
        self.snapshot = snapshot
        self.vaultID = vaultID
        queueReplan(after: changedVault ? .zero : debounce)
    }
    func foreground() async { await replanNow() }
    func requestAccess() async {
        guard authorization.canRequest, !isRequesting else { return }
        activate()
        isRequesting = true
        defer { isRequesting = false }
        do {
            _ = try await center.requestAuthorization()
            await replanNow()
        } catch {
            authorization = await center.authorization()
            errorText = String(localized: "Bildirim izni alınamadı. Yeniden deneyebilirsin.")
        }
    }
    private func queueReplan(after delay: Duration) {
        revision += 1
        if isPlanning { needsReplan = true }
        guard active else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.debounceTask = nil
            await self.replanNow()
        }
    }
    func replanNow() async {
        debounceTask?.cancel()
        debounceTask = nil
        revision += 1
        if isPlanning {
            needsReplan = true
            return
        }
        isPlanning = true
        defer { isPlanning = false }
        repeat {
            needsReplan = false
            let current = revision
            let instant = now()
            let zone = timeZone()
            authorization = await center.authorization()
            let existing = await center.pendingRequests()
            let plan =
                authorization.canSchedule
                ? snapshot.map {
                    NotificationPlanner.requests(snapshot: $0, preferences: preferences, now: instant, timeZone: zone)
                } ?? [] : []
            let own = existing.filter { NotificationDestination.from(identifier: $0.id) != nil }
            let identifiers = Set(
                own.map(\.id) + NotificationPlanner.identifiers(on: LocalDay.today(at: instant, timeZone: zone)))
            await center.remove(identifiers: identifiers.sorted())
            guard current == revision else {
                needsReplan = true
                continue
            }
            errorText = nil
            for request in plan {
                guard current == revision else {
                    needsReplan = true
                    break
                }
                do { try await center.add(request) } catch {
                    errorText = String(localized: "Bazı bildirimler planlanamadı. Yeniden planlayabilirsin.")
                }
            }
            pending = await center.pendingRequests().filter { NotificationDestination.from(identifier: $0.id) != nil }
                .sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
            if current != revision { needsReplan = true }
        } while needsReplan
    }
}
