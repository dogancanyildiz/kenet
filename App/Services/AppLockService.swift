import Foundation
import LocalAuthentication
import Observation

/// A fresh context is used for each attempt; device credentials are always allowed.
@MainActor protocol AppLockAuthenticating: AnyObject {
    func authenticate(reason: String) async throws -> Bool
    func invalidate()
}

@MainActor final class SystemAppLockContext: AppLockAuthenticating {
    private let context = LAContext()

    func authenticate(reason: String) async throws -> Bool {
        try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
    }

    func invalidate() { context.invalidate() }
}

enum AppLockDelay: Int, CaseIterable {
    case immediately = 0
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900
}

/// Device-local UI protection. Vault writers and App Intents deliberately do not depend on this service.
@MainActor @Observable final class AppLockService {
    static let enabledKey = "appLock.enabled"
    static let delayKey = "appLock.delay"
    private(set) var isEnabled: Bool
    private(set) var isLocked: Bool
    private(set) var isForeground = false
    private(set) var isAuthenticating = false
    private(set) var authenticationFailed = false
    var delay: AppLockDelay {
        didSet { defaults.set(delay.rawValue, forKey: Self.delayKey) }
    }
    var shouldCover: Bool { isEnabled && (isLocked || !isForeground) }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let makeContext: () -> any AppLockAuthenticating
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var suspendedAt: Date?
    @ObservationIgnored private var context: (any AppLockAuthenticating)?
    @ObservationIgnored private var attempt = UUID()
    @ObservationIgnored private var covers: [UUID: () -> Void] = [:]

    init(
        defaults: UserDefaults = .standard,
        makeContext: @escaping () -> any AppLockAuthenticating = { SystemAppLockContext() },
        now: @escaping () -> Date = { Date() }
    ) {
        self.defaults = defaults
        self.makeContext = makeContext
        self.now = now
        let enabled = defaults.bool(forKey: Self.enabledKey)
        isEnabled = enabled
        isLocked = enabled
        delay = AppLockDelay(rawValue: defaults.integer(forKey: Self.delayKey)) ?? .immediately
    }

    func setEnabled(_ enabled: Bool) async {
        guard enabled != isEnabled, !isAuthenticating else { return }
        if enabled {
            guard await authenticate() else { return }
        }
        isEnabled = enabled
        isLocked = false
        suspendedAt = enabled && !isForeground ? now() : nil
        authenticationFailed = false
        defaults.set(enabled, forKey: Self.enabledKey)
        refreshCovers()
    }

    /// Inactive covers immediately, but only background starts the iOS timeout.
    /// On macOS resignation of application activity is the equivalent of background.
    func resignActive(startTimeout: Bool) {
        isForeground = false
        if startTimeout { cancelAuthentication() }
        if isEnabled && startTimeout {
            if suspendedAt == nil { suspendedAt = now() }
            updateLockForElapsedTime()
        }
        refreshCovers()
    }

    /// Lifecycle state changes synchronously, before a snapshot or another phase transition.
    func activate() {
        prepareForeground()
        Task { [weak self] in
            guard let self, self.isForeground else { return }
            await self.authenticateOnForeground()
        }
    }

    func becomeActive() async {
        prepareForeground()
        await authenticateOnForeground()
    }

    private func prepareForeground() {
        isForeground = true
        updateLockForElapsedTime()
        suspendedAt = nil
        refreshCovers()
    }

    private func authenticateOnForeground() async {
        if isEnabled && isLocked && !authenticationFailed { _ = await unlock() }
    }

    @discardableResult func unlock() async -> Bool {
        guard isEnabled else { return true }
        guard isLocked else { return true }
        guard await authenticate() else { return false }
        isLocked = false
        suspendedAt = isForeground ? nil : now()
        refreshCovers()
        return true
    }

    /// Nonactivating Mac panels can be used while the main windows stay covered.
    func authorizeQuickEntry() async -> Bool {
        updateLockForElapsedTime()
        refreshCovers()
        return await unlock()
    }

    func quickEntryClosed() {
        if isEnabled && !isForeground {
            suspendedAt = now()
            updateLockForElapsedTime()
            refreshCovers()
        }
    }

    func registerCover(_ update: @escaping () -> Void) -> UUID {
        let id = UUID()
        covers[id] = update
        update()
        return id
    }

    func unregisterCover(_ id: UUID) { covers[id] = nil }

    private func updateLockForElapsedTime() {
        guard isEnabled, let suspendedAt else { return }
        let elapsed = now().timeIntervalSince(suspendedAt)
        // Moving the clock backwards must not extend the grace period.
        if elapsed < 0 || elapsed >= Double(delay.rawValue) { isLocked = true }
    }

    private func authenticate() async -> Bool {
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        authenticationFailed = false
        let token = UUID()
        attempt = token
        let context = makeContext()
        self.context = context
        let success: Bool
        do {
            success = try await context.authenticate(
                reason: String(localized: "Günlüğünün kilidini açmak için kimliğini doğrula."))
        } catch {
            success = false
        }
        guard token == attempt else { return false }
        self.context = nil
        isAuthenticating = false
        authenticationFailed = !success
        return success
    }

    private func cancelAuthentication() {
        guard isAuthenticating else { return }
        attempt = UUID()
        context?.invalidate()
        context = nil
        isAuthenticating = false
        authenticationFailed = true
    }

    private func refreshCovers() {
        for update in covers.values { update() }
    }
}
