#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    @testable import Journal

    /// The iPad shell drawn by the real `AdaptiveNavigation` on the iPad canvases
    /// (``ShellCanvas``): Today, Görevler with a task open, Kişiler with a person open and
    /// Hedefler, on the 13-inch in landscape (light, plus one AX3 sidebar case), and the 13-inch and 11-inch
    /// in portrait. The shell's task model and the goal page take the wall-clock day, not the
    /// frozen one: Hedefler is drawn without a goal open (the list and the empty column) and
    /// the goal page is drawn on its own with the frozen day (`goalDetail`).
    enum PadShellCase: String, CaseIterable, Sendable {
        /// AX3 keeps the wider accessibility sidebar (docs/design.md: ShellStyle).
        case todayLandscapeLight, todayLandscapeAX3
        case tasksLandscapeLight
        case peopleLandscapeLight
        case goalsLandscapeLight
        case goalDetailLandscapeLight
        case todayPortrait, tasksPortrait
        case todayPad11Portrait, peoplePad11Portrait

        enum Screen: Sendable { case today, tasks, people, goals, goalDetail }

        var screen: Screen {
            switch self {
            case .todayLandscapeLight, .todayLandscapeAX3, .todayPortrait, .todayPad11Portrait:
                .today
            case .tasksLandscapeLight, .tasksPortrait: .tasks
            case .peopleLandscapeLight, .peoplePad11Portrait: .people
            case .goalsLandscapeLight: .goals
            case .goalDetailLandscapeLight: .goalDetail
            }
        }

        var canvas: ShellCanvas {
            switch self {
            case .todayPortrait, .tasksPortrait: .pad13Portrait
            case .todayPad11Portrait, .peoplePad11Portrait: .pad11Portrait
            default: .pad13Landscape
            }
        }

        var colorScheme: SnapshotColorScheme { .light }

        var dynamicType: SnapshotDynamicType { self == .todayLandscapeAX3 ? .accessibility3 : .medium }

        /// The glass controls painted over: the sidebar button, and in the three-column tier the
        /// floating sidebar's trailing edge, whose refraction of the list under it differs
        /// between runs. The 11" canvas is two columns: no sidebar on screen.
        var masks: [CGRect] {
            guard screen != .goalDetail else { return [] }
            guard canvas != .pad11Portrait else { return [PadSnapshotHost.Mask.sidebarButton] }
            return [PadSnapshotHost.Mask.sidebarButton]
                + PadSnapshotHost.Mask.sidebarOutline(on: canvas, dynamicType: dynamicType)
        }
    }

    @MainActor
    @Suite(.serialized, .enabled("iPad simulator only", PadSnapshotHost.isPadSimulator))
    struct PadShellSnapshotTests {
        @Test(arguments: PadShellCase.allCases)
        func shell(_ snapshotCase: PadShellCase) async throws {
            let showsGoals = snapshotCase.screen == .goals || snapshotCase.screen == .goalDetail
            let clock = showsGoals ? goalsSnapshotNow : snapshotNow
            try await PadSnapshotHost.assertWindow(
                named: snapshotCase.rawValue, testName: "shell", canvas: snapshotCase.canvas,
                colorScheme: snapshotCase.colorScheme, dynamicType: snapshotCase.dynamicType, clock: clock,
                shellKind: snapshotCase.screen == .goalDetail ? .split : nil,
                masks: snapshotCase.masks
            ) { scene in
                let store = scene.store
                switch snapshotCase.screen {
                case .goalDetail:
                    let goal = try #require(
                        store.content.goals.first { $0.key == "kitap" } ?? store.content.goals.first)
                    return AnyView(
                        NavigationStack { GoalDetailView(store: store, goal: goal, day: goalsSnapshotDay) }.inkPage())
                case .today, .tasks, .people, .goals:
                    let navigation = ShellNavigationState()
                    switch snapshotCase.screen {
                    case .tasks:
                        let row = try #require(try await store.allTasks().first { !$0.isClosed })
                        navigation.section = .tasks
                        navigation.selectedTask = row.id
                    case .people:
                        let entity = try #require(
                            store.content.entities.first { $0.name == "Deniz Arıkan" } ?? store.content.entities.first)
                        navigation.section = .people
                        navigation.selectedEntityKind = "person"
                        navigation.selectedEntity = entity.id
                        navigation.selectedSummary = entity
                    case .goals:
                        navigation.section = .goals
                    case .today, .goalDetail:
                        break
                    }
                    return AnyView(AdaptiveNavigation(store: store, navigation: navigation))
                }
            }
        }
    }

    /// What a Pad case builds its content from: the sample vault's store and the services the
    /// shell reads from the environment (the notification service routes the close-day sheet).
    @MainActor struct PadSnapshotScene {
        let store: IndexStore
        let defaults: UserDefaults
        let notifications: NotificationService
    }

    /// The capture path of the `Pad…SnapshotTests` suites: the content is hosted in a window of
    /// the canvas size whose size classes and Dynamic Type come from window trait overrides, so
    /// presented sheets take them too, and the window itself is drawn (as in
    /// `ChromeSheetsDuoSnapshotTests`; the library's view strategy corrupts a `UIWindow`).
    @MainActor enum PadSnapshotHost {
        /// The previous case's window, released only once the next case has its own.
        private static var retired: UIWindow?

        /// The suites run on an iPad simulator only; on an iPhone they skip themselves, so the
        /// iOS unit job (which skips only the default snapshot suites) passes over them.
        /// The iOS 26 glass controls blur and shade what is under them differently from run to
        /// run (as in `ChromeSheetsDuoSnapshotTests`); the capture paints their squares over.
        enum Mask {
            /// The split shell's floating sidebar button, top leading.
            static let sidebarButton = CGRect(x: 0, y: 0, width: 100, height: 125)

            /// The floating sidebar's glass outline in the three-column tier: the panel sits
            /// 10 pt in from the leading edge, its border and shadow reach about 40 pt past its
            /// width (`ShellStyle.sidebarWidth`), and the top and bottom edges refract the bars
            /// behind them. Four strips around the panel; its rows stay in the comparison.
            static func sidebarOutline(on canvas: ShellCanvas, dynamicType: SnapshotDynamicType) -> [CGRect] {
                let width = ShellStyle.sidebarWidth(tier: .threeColumns, dynamicTypeSize: dynamicType.size).ideal
                let height = canvas.size.height
                let reach = 10 + width + 40
                return [
                    CGRect(x: 0, y: 0, width: reach, height: 70),
                    CGRect(x: 0, y: height - 40, width: reach, height: 40),
                    CGRect(x: 0, y: 0, width: 16, height: height),
                    CGRect(x: 10 + width - 6, y: 0, width: 46, height: height),
                ]
            }

            /// The tab shell's floating tab bar, along the bottom of the canvas.
            static func tabBar(on canvas: ShellCanvas) -> CGRect {
                CGRect(x: 0, y: canvas.size.height - 110, width: canvas.size.width, height: 110)
            }
        }

        nonisolated static let isPadSimulator: @Sendable () async -> Bool = {
            await MainActor.run { UIDevice.current.userInterfaceIdiom == .pad }
        }

        /// The iPad references are drawn in a portrait simulator scene, as a freshly booted
        /// simulator (CI) has it. The split view picks its columns from the scene's orientation,
        /// not only from the window, and a unit test cannot turn the device (the scene refuses
        /// `requestGeometryUpdate` in the iPadOS windowing mode; `XCUIDevice` needs a UI test).
        /// A turned simulator is reported instead of being compared pixel by pixel.
        static func isPortrait(_ scene: UIWindowScene) -> Bool {
            scene.effectiveGeometry.interfaceOrientation == .portrait
        }

        static func assertWindow(
            named name: String,
            testName: String,
            canvas: ShellCanvas,
            colorScheme: SnapshotColorScheme = .light,
            dynamicType: SnapshotDynamicType = .medium,
            clock: Date = snapshotNow,
            presentsSheet: Bool = false,
            /// Set for a page hosted without the shell; the shell cases get it from `AdaptiveNavigation`.
            shellKind: ShellKind? = nil,
            /// Squares painted over before comparing: the system's glass controls (``Mask``).
            masks: [CGRect] = [],
            /// Checks on the hosted window before the capture; `draws: false` skips the capture.
            inspect: (@MainActor (UIHostingController<AnyView>) -> Void)? = nil,
            draws: Bool = true,
            file: StaticString = #filePath,
            line: UInt = #line,
            content: @MainActor (PadSnapshotScene) async throws -> AnyView
        ) async throws {
            let context = try SnapshotHost.makeContext()
            defer { context.clean() }
            await context.start()
            let store = context.store
            let defaults = context.defaults.defaults
            let location = LocationService(source: FakeLocationSource(), defaults: defaults)
            let notifications = NotificationService(
                center: FakeNotificationCenter(), defaults: defaults,
                now: { clock }, timeZone: { snapshotTimeZone })
            let root = try await content(
                PadSnapshotScene(store: store, defaults: defaults, notifications: notifications))
            let shellRoot = shellKind.map { AnyView(root.environment(\.shellKind, $0)) } ?? root
            let view =
                shellRoot
                .environment(notifications)
                .environment(CalendarService(source: SnapshotCalendarSource()))
                .environment(location)
                .environment(GeofenceService(location: location, center: FakeGeofenceCenter(), defaults: defaults))
                .environment(IntentNavigation())
                .environment(\.clockNow, { clock })
                .environment(\.locale, snapshotLocale)
                .environment(\.timeZone, snapshotTimeZone)
                .environment(\.calendar, makeSnapshotCalendar())
                .environment(\.colorScheme, colorScheme.colorScheme)
                .environment(\.dynamicTypeSize, dynamicType.size)
                .environment(\.openSearch, {})
                .environment(\.openSettings, {})
                .tint(Color.ink.accent)
                .transaction { $0.animation = nil }

            var image: UIImage?
            await SnapshotHostGate.exclusive {
                guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
                else {
                    Issue.record("Pad snapshots need the Journal test host's window scene.")
                    return
                }
                guard isPortrait(scene) else {
                    Issue.record(
                        "Snapshot \(name): the iPad simulator is turned; references are drawn upright (reboot it: record-screen-snapshots.sh --pad does)."
                    )
                    return
                }
                let animated = UIView.areAnimationsEnabled
                UIView.setAnimationsEnabled(false)
                defer { UIView.setAnimationsEnabled(animated) }
                let host = UIHostingController(rootView: AnyView(view))
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(origin: .zero, size: canvas.size)
                window.overrideUserInterfaceStyle = colorScheme.userInterfaceStyle
                // On the window, not the host: a presented sheet inherits from the window.
                if let sizeClasses = canvas.sizeClasses {
                    window.traitOverrides.horizontalSizeClass = sizeClasses.horizontal
                    window.traitOverrides.verticalSizeClass = sizeClasses.vertical
                }
                window.traitOverrides.preferredContentSizeCategory = dynamicType.contentSize
                canvas.applySizeClasses(to: host)
                host.traitOverrides.preferredContentSizeCategory = dynamicType.contentSize
                window.rootViewController = host
                window.makeKeyAndVisible()
                window.layoutIfNeeded()
                // The window covers the simulator screen only in part (a landscape canvas on a
                // portrait screen): the system gives it the status bar inset alone. The rest of
                // the canvas's safe area is added, so every canvas has its device's bars.
                let actual = window.safeAreaInsets
                let wanted = canvas.safeArea
                host.additionalSafeAreaInsets = UIEdgeInsets(
                    top: max(0, wanted.top - actual.top), left: max(0, wanted.left - actual.left),
                    bottom: max(0, wanted.bottom - actual.bottom), right: max(0, wanted.right - actual.right))
                // Wait for the index, the presented content, then several idle frames.
                var idleFrames = 0
                for _ in 0..<100 where idleFrames < 8 {
                    // Frame pump: SwiftUI and UIKit draw on a later run-loop turn and report no event to await.
                    try? await Task.sleep(for: .milliseconds(50))
                    host.view.layoutIfNeeded()
                    host.presentedViewController?.view.layoutIfNeeded()
                    let sheetReady = !presentsSheet || host.presentedViewController?.view.window != nil
                    idleFrames = !store.isProcessing && sheetReady ? idleFrames + 1 : 0
                }
                if presentsSheet && host.presentedViewController == nil {
                    Issue.record("Snapshot \(name): the sheet was never presented.")
                }
                inspect?(host)
                let format = UIGraphicsImageRendererFormat()
                format.scale = 2
                // 8-bit sRGB like the phone references (SnapshotTesting's own strategy). The
                // iPad simulator's default is 16-bit extended range, where a hairline's sub-level
                // coverage difference between machines fails the perceptual comparison.
                format.preferredRange = .standard
                if draws {
                    image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
                        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                        UIColor.gray.setFill()
                        for mask in masks { UIRectFill(mask) }
                    }
                }
                // A column or sheet transition leaves a context that UIKit disposes after the next
                // commit; the window is kept until the next case starts (see ChromeSheetsDuoHost).
                host.presentedViewController?.dismiss(animated: false)
                // Frames for UIKit to dispose the last transition before the window is released; no event marks it.
                for _ in 0..<4 { try? await Task.sleep(for: .milliseconds(50)) }
                window.isHidden = true
                window.rootViewController = nil
                window.windowScene = nil
                retired = window
            }
            guard draws else { return }
            let captured = try #require(image)
            assertSnapshot(
                of: captured,
                as: .image(precision: snapshotPrecision, perceptualPrecision: snapshotPerceptualPrecision),
                named: name,
                record: ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"]
                    .flatMap(SnapshotTestingConfiguration.Record.init(rawValue:)),
                file: file,
                testName: testName,
                line: line)
        }
    }
#endif
