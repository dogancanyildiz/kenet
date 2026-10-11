import Testing

@testable import Journal

#if os(macOS)
    import AppKit
    import SwiftUI
#endif

#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import UIKit

    /// Shell / Settings / onboarding / lock — own case list and host view.
    /// Mac cases omitted: SnapshotTesting host here is UIKit / iOS Simulator only.
    enum ShellSettingsSnapshotCase: String, CaseIterable, Sendable {
        case onboardingLight
        case onboardingDark
        case onboardingAX3
        case onboardingContrast
        case settingsLight
        case settingsDark
        case settingsAX3
        case settingsContrast
        case lockLight
        case lockDark
        case lockAX3
        case lockContrast
        case inaccessibleLight
        case inaccessibleDark
        case inaccessibleAX3
        case inaccessibleContrast
        case privacyLight
        case privacyAX3
        case vaultLight
        case vaultAX3
        case diagnosticsLight
        case diagnosticsAX3
        case entryPointsLight
        case entryPointsDark
        case entryPointsAX3

        var screen: ShellSettingsScreen {
            switch self {
            case .onboardingLight, .onboardingDark, .onboardingAX3, .onboardingContrast: .onboarding
            case .settingsLight, .settingsDark, .settingsAX3, .settingsContrast: .settings
            case .lockLight, .lockDark, .lockAX3, .lockContrast: .lock
            case .inaccessibleLight, .inaccessibleDark, .inaccessibleAX3, .inaccessibleContrast:
                .inaccessible
            case .privacyLight, .privacyAX3: .privacy
            case .vaultLight, .vaultAX3: .vault
            case .diagnosticsLight, .diagnosticsAX3: .diagnostics
            case .entryPointsLight, .entryPointsDark, .entryPointsAX3: .entryPoints
            }
        }

        var colorScheme: SnapshotColorScheme {
            switch self {
            case .onboardingDark, .settingsDark, .lockDark, .inaccessibleDark, .entryPointsDark: .dark
            default: .light
            }
        }

        var dynamicType: SnapshotDynamicType {
            switch self {
            case .onboardingAX3, .settingsAX3, .lockAX3, .inaccessibleAX3, .privacyAX3, .vaultAX3,
                .diagnosticsAX3, .entryPointsAX3:
                .accessibility3
            default: .medium
            }
        }

        var increaseContrast: Bool {
            switch self {
            case .onboardingContrast, .settingsContrast, .lockContrast, .inaccessibleContrast:
                true
            default: false
            }
        }

        /// Opened sample vault (path on screen is overridden to a fictional constant).
        var needsOpenVault: Bool { screen == .settings || screen == .vault }

        /// Light/dark only — smaller bitmaps; run before AX batches to limit host pressure.
        static var lightDarkCases: [ShellSettingsSnapshotCase] {
            [
                .onboardingLight, .onboardingDark, .settingsLight, .settingsDark,
                .lockLight, .lockDark, .inaccessibleLight, .inaccessibleDark,
                .entryPointsLight, .entryPointsDark,
            ]
        }

        static var accessibilityCases: [ShellSettingsSnapshotCase] {
            [
                .onboardingAX3, .onboardingContrast, .settingsAX3, .settingsContrast,
                .lockAX3, .lockContrast, .inaccessibleAX3, .inaccessibleContrast,
                .entryPointsAX3,
            ]
        }

        static var sectionCases: [ShellSettingsSnapshotCase] {
            [
                .privacyLight, .privacyAX3, .vaultLight, .vaultAX3,
                .diagnosticsLight, .diagnosticsAX3,
            ]
        }
    }

    enum ShellSettingsScreen: String, Sendable {
        case onboarding, settings, lock, inaccessible, privacy, vault, diagnostics, entryPoints
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
                case .privacy:
                    AnyView(PrivacySettingsView().navigationTitle("Gizlilik"))
                case .vault:
                    AnyView(VaultSettingsView(store: store).navigationTitle("Kasa"))
                case .diagnostics:
                    AnyView(DiagnosticsView(store: store).navigationTitle("Tanılama"))
                case .entryPoints:
                    AnyView(EntryPointsSettingsView())
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
                .environment(
                    \.vaultPathDisplayOverride,
                    screen == .vault ? VaultPathDisplay.snapshotExample : nil)
        }

        static func assert(
            _ snapshotCase: ShellSettingsSnapshotCase, store: IndexStore, defaults: UserDefaults,
            lock: AppLockService,
            file: StaticString = #filePath, line: UInt = #line
        ) async {
            await SnapshotHostGate.exclusive {
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
                host.traitOverrides.preferredContentSizeCategory =
                    snapshotCase.dynamicType.contentSize
                host.traitOverrides.accessibilityContrast =
                    snapshotCase.increaseContrast ? .high : .normal
                host.view.frame = CGRect(origin: .zero, size: snapshotCanvasSize)

                let scene =
                    UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .first { $0.activationState == .foregroundActive }
                    ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                    .first
                guard let scene else {
                    Issue.record(
                        "Snapshot host needs a UIWindowScene (run under the Journal test host).")
                    return
                }
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(origin: .zero, size: snapshotCanvasSize)
                window.overrideUserInterfaceStyle = snapshotCase.colorScheme.userInterfaceStyle
                window.rootViewController = host
                window.makeKeyAndVisible()
                defer {
                    window.isHidden = true
                    window.rootViewController = nil
                    window.windowScene = nil
                }
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                for _ in 0..<40 {
                    await Task.yield()
                    host.view.setNeedsLayout()
                    host.view.layoutIfNeeded()
                    if !store.isProcessing, host.view.bounds.width > 0 { break }
                    try? await Task.sleep(for: .milliseconds(25))
                }
                for _ in 0..<4 {
                    await Task.yield()
                    try? await Task.sleep(for: .milliseconds(25))
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
            }
        }
    }

    @MainActor
    private enum ShellSettingsSnapshotRunner {
        static func run(_ snapshotCase: ShellSettingsSnapshotCase) async throws {
            let lockFixture = LockFixture(enabled: true)
            defer { lockFixture.clean() }
            lockFixture.context.result = false
            let lock = lockFixture.lock()

            let context = try TaskTestContext(sample: snapshotCase.needsOpenVault)
            defer { context.clean() }
            if snapshotCase.needsOpenVault { await context.start() }
            await ShellSettingsSnapshotHost.assert(
                snapshotCase, store: context.store, defaults: context.defaults.defaults, lock: lock)
        }
    }

    /// Separate suites so each `xcodebuild` run can reclaim memory after AX-sized bitmaps.
    @MainActor @Suite("Shell settings snapshots", .serialized)
    struct ShellSettingsSnapshotTests {
        @Test(arguments: ShellSettingsSnapshotCase.lightDarkCases)
        func shellSettings(_ snapshotCase: ShellSettingsSnapshotCase) async throws {
            try await ShellSettingsSnapshotRunner.run(snapshotCase)
        }
    }

    @MainActor @Suite("Shell settings snapshots AX", .serialized)
    struct ShellSettingsAXSnapshotTests {
        @Test(arguments: ShellSettingsSnapshotCase.accessibilityCases)
        func shellSettings(_ snapshotCase: ShellSettingsSnapshotCase) async throws {
            try await ShellSettingsSnapshotRunner.run(snapshotCase)
        }
    }

    @MainActor @Suite("Shell settings snapshots sections", .serialized)
    struct ShellSettingsSectionsSnapshotTests {
        @Test(arguments: ShellSettingsSnapshotCase.sectionCases)
        func shellSettings(_ snapshotCase: ShellSettingsSnapshotCase) async throws {
            try await ShellSettingsSnapshotRunner.run(snapshotCase)
        }
    }
#endif

/// Section order, Siri phrase equality, and the one-time hint. Shared by both platforms.
@Suite("Entry points")
struct EntryPointSettingsTests {
    private static let sectionOrder = [
        "Hızlı giriş|square.and.pencil",
        "Gizlilik|lock",
        "Bildirimler|bell",
        "Takvim ve Konum|calendar",
        "Kasa|folder",
        "Tanılama|wrench.and.screwdriver",
    ]

    @Test func phoneSettingsHasSixSectionsInTheDocumentedOrder() {
        let table = SettingsSection.allCases.map { "\($0.title.key)|\($0.symbol)" }
        #expect(SettingsSection.allCases.count == 6)
        #expect(table == Self.sectionOrder)
    }

    #if os(macOS)
        @Test func macSettingsHasSixTabsInTheDocumentedOrder() {
            let table = MacSettingsTab.allCases.map { "\($0.title.key)|\($0.systemImage)" }
            #expect(MacSettingsTab.allCases.count == 6)
            #expect(table == Self.sectionOrder)
        }
    #endif

    @Test func actionButtonCopyFollowsThePlatform() {
        #if os(iOS)
            #expect(EntryPointPlatform.showsActionButton)
        #else
            #expect(!EntryPointPlatform.showsActionButton)
        #endif
    }

    /// Displayed sentences are the shortcut templates with the app name filled in. A catalog
    /// translation that drifts from `JournalShortcuts` fails this.
    @Test func shownPhrasesMatchJournalShortcuts() {
        let name = "Uygulama"
        let locale = Locale(identifier: "tr")
        let shown = EntryPointPhrases.displayed(applicationName: name, locale: locale)
        let expected = EntryPointPhrases.templates.map {
            $0.replacingOccurrences(of: EntryPointPhrases.applicationNameToken, with: name)
        }
        #expect(!shown.isEmpty)
        #expect(shown.count == JournalShortcuts.appShortcuts.count)
        #expect(shown == expected)
    }

    /// The page's own list is the one `JournalShortcuts` registers. `AppShortcut` keeps its
    /// phrases internal, so the test reads them by reflection; the app itself does not.
    @Test func phraseTemplatesAreTheRegisteredOnes() throws {
        let registered = JournalShortcuts.appShortcuts.flatMap { shortcut -> [String] in
            for child in Mirror(reflecting: shortcut).children where child.label == "basePhraseTemplates" {
                if let templates = child.value as? [String] { return templates }
            }
            return []
        }
        try #require(!registered.isEmpty, "AppShortcut no longer exposes basePhraseTemplates to reflection")
        #expect(EntryPointPhrases.templates == registered)
    }

    @Test func dismissedTipStaysDismissedAndStaysHiddenWithoutAutomaticStart() throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        #expect(!EntryPointsTipPreference.isDismissed(in: defaults.defaults))
        #expect(
            EntryPointsTipPreference.shouldPresent(
                dismissed: false, environment: [:], arguments: []))
        #expect(
            !EntryPointsTipPreference.shouldPresent(
                dismissed: false, environment: ["JOURNAL_UITEST_VAULT": "/tmp/vault"], arguments: []))
        #expect(
            !EntryPointsTipPreference.shouldPresent(
                dismissed: false, environment: ["JOURNAL_NO_AUTOSTART": "1"], arguments: []))
        #expect(
            !EntryPointsTipPreference.shouldPresent(
                dismissed: false, environment: ["XCTestConfigurationFilePath": "/tmp/xctest.xctestconfiguration"],
                arguments: []))
        #expect(
            !EntryPointsTipPreference.shouldPresent(
                dismissed: false, environment: [:], arguments: ["JOURNAL_NO_AUTOSTART"]))

        EntryPointsTipPreference.dismiss(in: defaults.defaults)
        let dismissed = EntryPointsTipPreference.isDismissed(in: defaults.defaults)
        #expect(dismissed)
        #expect(
            !EntryPointsTipPreference.shouldPresent(
                dismissed: dismissed, environment: [:], arguments: []))
    }
}

#if os(macOS)
    /// The shortcut tab renders the shared rows and leaves the Action Button unmentioned.
    @MainActor @Suite("Entry points Mac", .timeLimit(.minutes(1)))
    struct MacEntryPointSettingsTests {
        private let watchdog = HostedTestWatchdog()

        @Test func shortcutTabOmitsTheActionButton() async throws {
            let defaults = try TestDefaults()
            defer { defaults.clean() }
            let model = HotKeySettingsModel(defaults: defaults.defaults, register: { _ in true })
            let mount = HostedLayout.Mount(
                HotKeySettingsView(model: model)
                    .environment(\.locale, Locale(identifier: "tr_TR"))
                    .frame(width: 560, height: 720),
                size: CGSize(width: 560, height: 720))
            defer { mount.close() }
            await mount.settle()
            let text = Self.renderedText(mount.window.contentView).joined(separator: "\n")
            #expect(text.contains("günlüğe olay ekle"))
            #expect(!text.contains("Eylem düğmesi"))
            #expect(!text.contains("Action Button"))
        }

        private static func renderedText(_ view: NSView?) -> [String] {
            guard let view else { return [] }
            var found: [String] = []
            func walk(_ view: NSView) {
                let value = (view.accessibilityValue() as? String) ?? ""
                let label = view.accessibilityLabel() ?? ""
                let field = (view as? NSTextField)?.stringValue ?? ""
                for piece in [field, label, value] where !piece.isEmpty {
                    found.append(piece)
                }
                view.subviews.forEach(walk)
            }
            walk(view)
            return found
        }
    }
#endif
