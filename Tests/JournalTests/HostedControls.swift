#if os(macOS)
    import AppKit
    import SwiftUI
    import Testing

    @testable import Journal

    /// The controls a mounted view really shows, read from the accessibility tree SwiftUI builds
    /// for it: label, value, identifier, whether it takes presses, and where it sits. A test reads
    /// what a user (or VoiceOver) meets instead of the source that builds it.
    @MainActor
    enum HostedControls {
        struct Node {
            let object: NSObject
            let label: String
            let title: String
            let value: String
            let identifier: String
            let help: String
            let role: String
            let isEnabled: Bool
            /// Screen coordinates; only the order of frames in one window is compared.
            let frame: CGRect

            func press() { _ = object.perform(Selectors.press) }
        }

        private enum Selectors {
            static let label = NSSelectorFromString("accessibilityLabel")
            static let title = NSSelectorFromString("accessibilityTitle")
            static let value = NSSelectorFromString("accessibilityValue")
            static let identifier = NSSelectorFromString("accessibilityIdentifier")
            static let help = NSSelectorFromString("accessibilityHelp")
            static let role = NSSelectorFromString("accessibilityRole")
            static let children = NSSelectorFromString("accessibilityChildren")
            static let enabled = NSSelectorFromString("isAccessibilityEnabled")
            static let frame = NSSelectorFromString("accessibilityFrame")
            static let press = NSSelectorFromString("accessibilityPerformPress")
            static let parent = NSSelectorFromString("accessibilityParent")
        }

        /// SwiftUI builds the tree only once an assistive client has asked the process something.
        static func enableTree() {
            _ = AXUIElementSetAttributeValue(
                AXUIElementCreateApplication(getpid()), "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }

        /// Waits until `ready` holds on the mounted tree. A machine that gives no tree at all has
        /// nothing to measure: the caller returns with a note instead of failing on the environment.
        static func isAvailable(
            _ mount: HostedLayout.Mount, until ready: () -> Bool, test: String = #function
        ) async -> Bool {
            enableTree()
            for _ in 0..<60 where !ready() { await mount.settle(rounds: 1) }
            if ready() { return true }
            if nodes(in: mount).allSatisfy({ $0.label.isEmpty && $0.value.isEmpty }) {
                if requiresTree {
                    Issue.record("No accessibility tree, and KENET_REQUIRE_AX asks for one: \(test)")
                } else {
                    FileHandle.standardError.write(
                        Data("ATLANDI (ortam erişilebilirlik ağacı vermiyor): \(test)\n".utf8))
                }
                return false
            }
            Issue.record("The mounted view never showed what the test waits for")
            return false
        }

        /// CI sets `TEST_RUNNER_KENET_REQUIRE_AX=1` (the test runner passes it on as
        /// `KENET_REQUIRE_AX`): a machine without a tree then fails these tests instead of
        /// skipping them unseen.
        static var requiresTree: Bool {
            let environment = ProcessInfo.processInfo.environment
            return environment["KENET_REQUIRE_AX"] == "1" || environment["TEST_RUNNER_KENET_REQUIRE_AX"] == "1"
        }

        /// Every node under the window's content, in tree order.
        static func nodes(in mount: HostedLayout.Mount) -> [Node] {
            nodes(under: mount.window.contentView as Any)
        }

        static func nodes(under root: Any) -> [Node] {
            var found: [Node] = []
            var seen = Set<ObjectIdentifier>()
            func step(_ item: Any) {
                guard let object = item as? NSObject, seen.insert(ObjectIdentifier(object)).inserted else { return }
                // SwiftUI's link rotor elements throw on their label when the text has no links yet;
                // they only mirror the text's own node.
                found.append(node(object))
                if object.responds(to: Selectors.children),
                    let children = object.perform(Selectors.children)?.takeUnretainedValue() as? [Any]
                {
                    children.forEach(step)
                }
                (object as? NSView)?.subviews.forEach(step)
            }
            step(root)
            return found
        }

        /// The node with this accessibility identifier.
        static func node(_ identifier: String, in mount: HostedLayout.Mount) -> Node? {
            nodes(in: mount).first { $0.identifier == identifier }
        }

        /// Every label and value under the mount, in tree order.
        static func texts(in mount: HostedLayout.Mount) -> [String] {
            nodes(in: mount).flatMap { [$0.label, $0.value] }.filter { !$0.isEmpty }
        }

        /// The localized word the user sees for a catalog key, in the test process's language.
        static func word(_ key: String) -> String {
            String(localized: String.LocalizationValue(key))
        }

        private static func node(_ object: NSObject) -> Node {
            let role = string(object, Selectors.role)
            // A link inside a text is read through the text's own value. Its element only mirrors
            // a range of that text, and asking it for its label throws while the text is still
            // empty (`accessibilityStringForRange` out of bounds), which would end the test process.
            if role == "AXLink", let parent = parent(of: object), string(parent, Selectors.role) == "AXStaticText" {
                return Node(
                    object: object, label: "", title: "", value: "", identifier: "", help: "", role: role,
                    isEnabled: true, frame: .null)
            }
            return Node(
                object: object, label: string(object, Selectors.label), title: string(object, Selectors.title),
                value: string(object, Selectors.value),
                identifier: string(object, Selectors.identifier), help: string(object, Selectors.help),
                role: role, isEnabled: isEnabled(object), frame: frame(object))
        }

        private static func parent(of object: NSObject) -> NSObject? {
            guard object.responds(to: Selectors.parent) else { return nil }
            return object.perform(Selectors.parent)?.takeUnretainedValue() as? NSObject
        }

        private static func string(_ object: NSObject, _ selector: Selector) -> String {
            guard object.responds(to: selector) else { return "" }
            return object.perform(selector)?.takeUnretainedValue() as? String ?? ""
        }

        private static func isEnabled(_ object: NSObject) -> Bool {
            guard object.responds(to: Selectors.enabled), let method = object.method(for: Selectors.enabled)
            else { return true }
            typealias Getter = @convention(c) (NSObject, Selector) -> Bool
            return unsafeBitCast(method, to: Getter.self)(object, Selectors.enabled)
        }

        private static func frame(_ object: NSObject) -> CGRect {
            guard object.responds(to: Selectors.frame), let method = object.method(for: Selectors.frame)
            else { return .null }
            typealias Getter = @convention(c) (NSObject, Selector) -> CGRect
            return unsafeBitCast(method, to: Getter.self)(object, Selectors.frame)
        }
    }
#endif
