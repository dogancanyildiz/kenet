#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    @testable import Journal

    /// Shell / Settings / onboarding / lock — own case list (not ScreenSnapshotCase).
    /// Light + dark only: full AX3/contrast matrix crashed the iOS test host under parallel simulator load.
    enum ShellSettingsSnapshotCase: String, CaseIterable, Sendable {
        case onboardingLight
        case onboardingDark
        case settingsLight
        case settingsDark
        case lockLight
        case lockDark
        case inaccessibleLight
        case inaccessibleDark

        var screen: ShellSettingsScreen {
            switch self {
            case .onboardingLight, .onboardingDark: .onboarding
            case .settingsLight, .settingsDark: .settings
            case .lockLight, .lockDark: .lock
            case .inaccessibleLight, .inaccessibleDark: .inaccessible
            }
        }

        var colorScheme: SnapshotColorScheme {
            switch self {
            case .onboardingDark, .settingsDark, .lockDark, .inaccessibleDark: .dark
            default: .light
            }
        }

        var dynamicType: SnapshotDynamicType { .medium }
        var increaseContrast: Bool { false }
    }

    enum ShellSettingsScreen: String, Sendable {
        case onboarding, settings, lock, inaccessible
    }

    @MainActor
    enum ShellSettingsSnapshotHost {
        static func hostedView(
            screen: ShellSettingsScreen, store: IndexStore, defaults: UserDefaults,
            lock: AppLockService
        ) -> some View {
            let notifications = NotificationService(
                center: FakeNotificationCenter(), defaults: defaults,
                now: { snapshotNow },
                timeZone: { snapshotTimeZone })
            let calendar = CalendarService(source: SnapshotCalendarSource())
            let location = LocationService(source: FakeLocationSource(), defaults: defaults)
            let geofences = GeofenceService(
                location: location, center: FakeGeofenceCenter(), defaults: defaults)
            let root: AnyView =
                switch screen {
                case .onboarding:
                    AnyView(OnboardingView(store: store))
                case .settings:
                    AnyView(PhoneSettingsView(store: store))
                case .lock:
                    AnyView(AppLockCover(lock: lock, allowsBackgroundAuthentication: true))
                case .inaccessible:
                    AnyView(VaultInaccessibleView(store: store))
                }
            return NavigationStack { root }
                .environment(notifications)
                .environment(calendar)
                .environment(location)
                .environment(geofences)
                .environment(lock)
                .environment(\.locale, snapshotLocale)
                .environment(
                    \.calendar,
                    {
                        var calendar = Calendar(identifier: .gregorian)
                        calendar.locale = snapshotLocale
                        calendar.timeZone = snapshotTimeZone
                        return calendar
                    }()
                )
                .environment(\.timeZone, snapshotTimeZone)
                .environment(\.clockNow, { snapshotNow })
                .environment(\.openSearch, {})
        }

        static func assert(
            _ snapshotCase: ShellSettingsSnapshotCase, store: IndexStore, defaults: UserDefaults,
            lock: AppLockService,
            file: StaticString = #filePath, line: UInt = #line
        ) async {
            let view = hostedView(
                screen: snapshotCase.screen, store: store, defaults: defaults, lock: lock
            )
            .environment(\.colorScheme, snapshotCase.colorScheme.colorScheme)
            .environment(\.dynamicTypeSize, snapshotCase.dynamicType.size)
            .environment(\.clockNow, { snapshotNow })
            .transaction { $0.animation = nil }
            .frame(width: snapshotCanvasSize.width, height: snapshotCanvasSize.height)

            let traits = UITraitCollection { mutable in
                mutable.userInterfaceStyle = snapshotCase.colorScheme.userInterfaceStyle
                mutable.preferredContentSizeCategory = snapshotCase.dynamicType.contentSize
                mutable.accessibilityContrast = snapshotCase.increaseContrast ? .high : .normal
                mutable.displayScale = 2
            }

            let previousAnimations = UIView.areAnimationsEnabled
            UIView.setAnimationsEnabled(false)
            defer { UIView.setAnimationsEnabled(previousAnimations) }

            let host = UIHostingController(rootView: view)
            host.overrideUserInterfaceStyle = snapshotCase.colorScheme.userInterfaceStyle
            host.view.frame = CGRect(origin: .zero, size: snapshotCanvasSize)

            let scene =
                UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
                ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            guard let scene else {
                Issue.record("Snapshot host needs a UIWindowScene (run under the Journal test host).")
                return
            }
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: snapshotCanvasSize)
            window.overrideUserInterfaceStyle = snapshotCase.colorScheme.userInterfaceStyle
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            for _ in 0..<20 {
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(40))
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
            }

            let record = ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"]
                .flatMap(SnapshotTestingConfiguration.Record.init(rawValue:))
            assertSnapshot(
                of: host,
                as: .image(
                    on: ViewImageConfig.iPhone13,
                    precision: snapshotPrecision,
                    perceptualPrecision: snapshotPerceptualPrecision,
                    size: snapshotCanvasSize,
                    traits: traits
                ),
                named: snapshotCase.rawValue,
                record: record,
                file: file,
                testName: "shellSettings",
                line: line
            )
            window.isHidden = true
            window.rootViewController = nil
        }
    }

    /// Denied calendar keeps EventKit chrome out of references.
    @MainActor private final class SnapshotCalendarSource: CalendarEventSource {
        var authorization = CalendarAuthorization.denied
        var onChange: (@MainActor @Sendable () -> Void)?
        func requestFullAccess() async throws -> Bool { false }
        func events(from start: Date, to end: Date) async throws -> [CalendarEvent] { [] }
    }

    @MainActor @Suite("Shell settings snapshots", .serialized)
    struct ShellSettingsSnapshotTests {
        @Test(arguments: ShellSettingsSnapshotCase.allCases)
        func shellSettings(_ snapshotCase: ShellSettingsSnapshotCase) async throws {
            let needsVault = snapshotCase.screen == .settings
            let context = try TaskTestContext(sample: needsVault)
            defer { context.clean() }
            if needsVault { await context.start() }
            let lockFixture = LockFixture(enabled: true)
            defer { lockFixture.clean() }
            lockFixture.context.result = false
            let lock = lockFixture.lock()
            await ShellSettingsSnapshotHost.assert(
                snapshotCase, store: context.store, defaults: context.defaults.defaults, lock: lock)
        }
    }
#endif
