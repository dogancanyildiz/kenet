import Foundation
import Observation
import VaultFormat

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
            if preferences.hideContent && !oldValue.hideContent {
                Task { await center.removeAllDeliveredNotifications() }
            }
            queueReplan(after: .zero)
        }
    }
    @ObservationIgnored private let center: any NotificationScheduling
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let timeZone: () -> TimeZone
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private var cadencePeople: (CalendarDate) async -> [CadenceReminderPerson]? = { _ in [] }
    /// Tasks and written days of the planned week; nil stands for a failed read. Without a store
    /// the week is empty, as an empty vault's.
    @ObservationIgnored private var vaultDays: (CalendarDate, CalendarDate) async -> NotificationVaultDays? = { _, _ in
        NotificationVaultDays()
    }
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var snapshot: VaultReadModel?
    @ObservationIgnored private var vaultID: String?
    /// Last vault that was open; an unreadable vault reopening as itself is not a switch.
    @ObservationIgnored private var lastOpenVaultID: String?
    /// Delivered notifications name the previous vault's tasks and people; the next plan clears them.
    @ObservationIgnored private var clearsDelivered = false
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
        cadencePeople = { [weak store] today in
            guard let store else { return nil }
            // A plan already under way finishes: queries answer a cancelled caller with
            // `CancellationError`, which would read as a failed read and drop people reminders.
            // Only the query is shielded, still on the main actor; the plan stays the one writer.
            return try? await Task { try await store.cadenceReminderPeople(today: today) }.value
        }
        vaultDays = { [weak store] first, last in
            guard let store else { return nil }
            // Shielded like the people read: a cancelled plan would read as a failed read.
            return try? await Task { try await store.computeNotificationDays(from: first, through: last) }.value
        }
        store.onSnapshotChange = { [weak self] content, root in self?.update(snapshot: content, vaultID: root?.path) }
        update(snapshot: store.lastUpdated == nil ? nil : store.content, vaultID: store.vaultURL?.path)
    }

    /// Tests inject people without an open vault; nil stands for a failed read. A later `attach` replaces this.
    func useCadencePeople(_ people: [CadenceReminderPerson]?) {
        cadencePeople = { _ in people }
    }

    /// Tests inject the planned week without an open vault; nil stands for a failed read.
    func useVaultDays(_ days: NotificationVaultDays?) {
        vaultDays = { _, _ in days }
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
        if let vaultID {
            if let lastOpenVaultID, lastOpenVaultID != vaultID { clearsDelivered = true }
            lastOpenVaultID = vaultID
        }
        self.snapshot = snapshot
        self.vaultID = vaultID
        queueReplan(after: changedVault ? .zero : debounce)
    }
    func clearNavigationRequest() { navigationRequest = nil }
    func open(_ destination: NotificationDestination) {
        navigationRequest = NotificationNavigationRequest(destination: destination)
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
            if clearsDelivered {
                clearsDelivered = false
                await center.removeAllDeliveredNotifications()
            }
            let current = revision
            let instant = now()
            let zone = timeZone()
            authorization = await center.authorization()
            let existing = await center.pendingRequests()
            let anchor = LocalDay.today(at: instant, timeZone: zone)
            let vault = vaultID
            var history = CadenceReminderHistory(from: defaults)
            history.settle(at: instant)
            // Nil when the people could not be read: no reminder is planned and no record is dropped.
            var people: [CadenceReminderPerson]?
            var schedule = NotificationSchedule(requests: [], assignments: [])
            if authorization.canSchedule, let snapshot {
                if preferences.peopleEnabled { people = await cadencePeople(anchor) }
                // Nil when the week could not be read: no task or journal reminder is planned.
                var days: NotificationVaultDays? = NotificationVaultDays()
                if preferences.tasksEnabled || preferences.journalEnabled {
                    days = await vaultDays(anchor, anchor.addingDays(6) ?? anchor)
                }
                schedule = NotificationPlanner.schedule(
                    snapshot: snapshot, days: days, preferences: preferences, now: instant, timeZone: zone,
                    people: people ?? [], lastNotified: history.memory(vaultID: vault).fired)
            }
            let plan = schedule.requests
            let own = existing.filter { NotificationDestination.from(identifier: $0.id) != nil }
            let identifiers = Set(
                own.map(\.id) + NotificationPlanner.identifiers(on: anchor)
                    + NotificationPlanner.peopleIdentifiers(on: anchor))
            await center.remove(identifiers: identifiers.sorted())
            history.persist(in: defaults)
            guard current == revision else {
                needsReplan = true
                continue
            }
            errorText = nil
            var addedPeople = Set<String>()
            for request in plan {
                guard current == revision else {
                    needsReplan = true
                    break
                }
                do {
                    try await center.add(request)
                    if request.destination == .people { addedPeople.insert(request.id) }
                } catch {
                    errorText = String(localized: "Bazı bildirimler planlanamadı. Yeniden planlayabilirsin.")
                }
            }
            history.record(
                schedule.assignments.filter { addedPeople.contains("people-\($0.day)") },
                known: people.map { Set($0.filter { $0.cadence.days != nil }.map(\.id)) }, vaultID: vault)
            history.persist(in: defaults)
            pending = await center.pendingRequests().filter { NotificationDestination.from(identifier: $0.id) != nil }
                .sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
            if current != revision { needsReplan = true }
        } while needsReplan
    }
}
