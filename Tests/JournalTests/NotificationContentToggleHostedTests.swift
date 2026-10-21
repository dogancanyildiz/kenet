#if os(macOS)
    import AppKit
    import SwiftUI
    import Testing

    @testable import Journal

    /// The settings switch asks to show content: off until the user turns it on, and turning it
    /// on is what stops hiding. Measured on the AppKit control SwiftUI builds (hosted offscreen).
    @MainActor @Suite(.timeLimit(.minutes(1)))
    struct NotificationContentToggleHostedTests {
        private let watchdog = HostedTestWatchdog()

        /// The switch labelled with the catalog word for "show content", read from the
        /// accessibility tree as VoiceOver meets it.
        private static func showContent(in mount: HostedLayout.Mount) -> HostedControls.Node? {
            let word = String(localized: "Bildirimde içeriği göster")
            return HostedControls.nodes(in: mount).first { $0.label == word && $0.role != "AXStaticText" }
        }

        /// Whether the switch reads as on: AppKit reports a checkbox or switch value as a number.
        private static func isOn(_ node: HostedControls.Node) -> Bool? {
            let selector = NSSelectorFromString("accessibilityValue")
            guard node.object.responds(to: selector) else { return nil }
            switch node.object.perform(selector)?.takeUnretainedValue() {
            case let number as NSNumber: return number.boolValue
            case let text as String: return text == "1"
            default: return nil
            }
        }

        @Test func showContentIsOffByDefaultAndTurningItOnStopsHiding() async throws {
            let defaults = try TestDefaults()
            defer { defaults.clean() }
            let service = NotificationService(center: FakeNotificationCenter(), defaults: defaults.defaults)
            let page = NotificationSettingsView().environment(service)
            let mount = HostedLayout.Mount(page, size: CGSize(width: 700, height: 1400))
            defer { mount.close() }
            await mount.settle()
            guard await HostedControls.isAvailable(mount, until: { Self.showContent(in: mount) != nil }) else {
                return
            }
            let toggle = try #require(Self.showContent(in: mount))
            #expect(service.preferences.hideContent)
            #expect(Self.isOn(toggle) == false)

            toggle.press()
            await mount.settle()
            #expect(!service.preferences.hideContent)
            #expect(Self.showContent(in: mount).flatMap(Self.isOn) == true)
            #expect(NotificationPreferences.read(from: defaults.defaults).hideContent == false)

            try #require(Self.showContent(in: mount)).press()
            await mount.settle()
            #expect(service.preferences.hideContent)
            #expect(Self.showContent(in: mount).flatMap(Self.isOn) == false)
        }
    }
#endif
