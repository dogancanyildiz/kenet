import UIKit
import XCTest

/// The audit every accessibility UI test runs: all audit types, nothing left out as a whole.
///
/// An issue fails the test unless one of these holds, each logged with its reason:
/// - The issue names no element. The audit cannot say what it measured, so there is nothing to fix or
///   to exempt by element. Touch targets are measured again by ``assertTouchTargets(in:screen:)``,
///   which names every element it checks.
/// - A contrast issue whose element, measured on screen, reaches 4.5:1, or that sits under a system bar.
/// - One entry of ``exemptions``: one audit type, one element (identifier or catalog text), one reason.
enum AccessibilityAuditPolicy {
    static let types: XCUIAccessibilityAuditType = .all

    /// The types whose findings are confirmed by a second pass (see ``audit(_:screen:secondTimeout:)``).
    static let confirmedTypes: XCUIAccessibilityAuditType = [.dynamicType, .hitRegion]

    /// What the second "Audit failed to complete in time" (code -56) does.
    enum SecondTimeout {
        case skip
        case fail
    }

    /// Settles the screen, runs the audit (once more after a -56 timeout), then measures touch targets.
    @MainActor
    static func audit(_ app: XCUIApplication, screen: String, secondTimeout: SecondTimeout = .fail) throws {
        // Every query is a round trip to the app (seconds each on a CI runner): the bars are read once
        // from the settled tree, and each issue's element once (``Seen``).
        let chrome = Chrome(settle(app))
        // The audit's Dynamic Type check is not deterministic: its live size change reaches text in one
        // run and not in the next, so one run names one of several identical elements (run 39848679358:
        // the "Geri" text button, which grows at AX3 and passed on the rerun). A Dynamic Type or hit region
        // issue (run 39848679358; locally a 371 × 19 pt summary label as 'too small') therefore fails only
        // when a second pass over those types names the same element again.
        let pending = DynamicTypeIssues()
        let handler: (XCUIAccessibilityAuditIssue) -> Bool = { issue in
            MainActor.assumeIsolated {
                if confirmedTypes.contains(issue.auditType) {
                    return handleDynamicType(issue, screen: screen, chrome: chrome, pending: pending, confirming: false)
                }
                return handle(issue, screen: screen, chrome: chrome)
            }
        }
        try run(app, types: types, screen: screen, secondTimeout: secondTimeout, handler)
        if !pending.keys.isEmpty {
            AccessibilityAuditPolicy.settle(app)
            let confirm: (XCUIAccessibilityAuditIssue) -> Bool = { issue in
                MainActor.assumeIsolated {
                    handleDynamicType(issue, screen: screen, chrome: chrome, pending: pending, confirming: true)
                }
            }
            try run(app, types: confirmedTypes, screen: screen, secondTimeout: secondTimeout, confirm)
            for key in pending.keys.subtracting(pending.confirmed) {
                print("A11Y UNCONFIRMED (\(screen)): \(key) — not named again by the second pass")
            }
        }
        assertTouchTargets(in: app, screen: screen)
    }

    /// Runs one audit, once more after a -56 timeout.
    ///
    /// CI simulators occasionally report "Audit failed to complete in time" (code -56): the audit's
    /// own time limit ran out on a slow runner, not a finding.
    @MainActor
    private static func run(
        _ app: XCUIApplication, types: XCUIAccessibilityAuditType, screen: String, secondTimeout: SecondTimeout,
        _ handler: @escaping (XCUIAccessibilityAuditIssue) -> Bool
    ) throws {
        do {
            try app.performAccessibilityAudit(for: types, handler)
        } catch let error as NSError where error.code == -56 {
            do {
                try app.performAccessibilityAudit(for: types, handler)
            } catch let error as NSError where error.code == -56 && secondTimeout == .skip {
                throw XCTSkip("A11Y audit timed out twice on \(screen) (code -56, runner too slow)")
            }
        }
    }

    /// Dynamic Type issues of the first pass, and those the second pass named again.
    final class DynamicTypeIssues {
        var keys: Set<String> = []
        var confirmed: Set<String> = []
    }

    /// First pass: an issue no exemption covers is remembered and let through. Second pass: it fails
    /// only if it is named again.
    @MainActor
    static func handleDynamicType(
        _ issue: XCUIAccessibilityAuditIssue, screen: String, chrome: Chrome, pending: DynamicTypeIssues,
        confirming: Bool
    ) -> Bool {
        let seen = issue.element.map(Seen.init)
        guard exemptionReason(for: issue, seen: seen, chrome: chrome) == nil, let seen else {
            return handle(issue, screen: screen, chrome: chrome)
        }
        let key = "\(name(of: issue.auditType)) '\(seen.identifier)' '\(seen.label)'"
        if !confirming {
            pending.keys.insert(key)
            return true
        }
        guard pending.keys.contains(key) else { return true }
        pending.confirmed.insert(key)
        return handle(issue, screen: screen, chrome: chrome)
    }

    // MARK: - Issues

    @MainActor
    static func handle(_ issue: XCUIAccessibilityAuditIssue, screen: String, chrome: Chrome) -> Bool {
        let type = name(of: issue.auditType)
        let seen = issue.element.map(Seen.init)
        let described = seen?.described ?? "(no element)"
        if let reason = exemptionReason(for: issue, seen: seen, chrome: chrome) {
            print("A11Y EXEMPT (\(screen)): type=\(type) \(described) — \(reason)")
            return true
        }
        print("A11Y ISSUE (\(screen)): type=\(type) \(described) — \(issue.compactDescription)")
        XCTContext.runActivity(named: "A11Y issue (\(screen)): \(type) — \(described)") { _ in }
        return false
    }

    @MainActor
    static func exemptionReason(for issue: XCUIAccessibilityAuditIssue, seen: Seen?, chrome: Chrome) -> String? {
        guard let element = issue.element, let seen else {
            return "names no element: nothing to fix or exempt by element"
                + (issue.auditType == .hitRegion ? " (touch targets measured by assertTouchTargets)" : "")
        }
        if issue.auditType == .contrast, let reason = contrastReason(for: element, frame: seen.frame, chrome: chrome) {
            return reason
        }
        if issue.auditType == .hitRegion, seen.frame.width >= minimumTarget - 0.5,
            seen.frame.height >= minimumTarget - 0.5
        {
            return "measured \(seen.frame.size) on screen, at least 44 × 44 pt (the audit's estimate disagrees)"
        }
        let exemption = (AccessibilityAuditExemption.all + AccessibilityAuditExemption.touchTargets).first {
            $0.type == issue.auditType && $0.matches(identifier: seen.identifier, label: seen.label)
        }
        return exemption?.logged
    }

    /// An issue's element, each property read once. Not `snapshot()`: that copies the element's whole
    /// subtree, seconds for a list row on a CI runner.
    struct Seen {
        let identifier: String
        let label: String
        let frame: CGRect

        @MainActor
        init(_ element: XCUIElement) {
            identifier = element.identifier
            label = element.label
            frame = element.frame
        }

        var described: String { "'\(identifier)' '\(label)' \(frame)" }
    }

    /// The window and the system bars, read from one snapshot of the application.
    struct Chrome {
        var window = CGRect.infinite
        var tabBar: CGRect?
        /// The first navigation bar in tree order with a height.
        var navigationBar: CGRect?
        /// Every navigation bar and toolbar.
        var bars: [CGRect] = []

        @MainActor
        init(_ root: XCUIElementSnapshot?) {
            guard let root else { return }
            var windowFound = false
            var stack = [root]
            while let node = stack.popLast() {
                switch node.elementType {
                case .window where !windowFound:
                    window = node.frame
                    windowFound = true
                case .tabBar where tabBar == nil:
                    tabBar = node.frame
                case .navigationBar:
                    if navigationBar == nil, node.frame.height > 0 { navigationBar = node.frame }
                    bars.append(node.frame)
                case .toolbar:
                    bars.append(node.frame)
                default:
                    break
                }
                stack.append(contentsOf: node.children.reversed())
            }
        }
    }

    // MARK: - Contrast

    /// The audit samples pixels around the element; the palette's text tokens are all at least 4.5:1 on
    /// every page ground (`PaletteContrastTests`). The element's own rendering is measured instead: the
    /// ground is the median luminance, the ink the 0.2 % at the far end.
    @MainActor
    static func contrastReason(for element: XCUIElement, frame: CGRect, chrome: Chrome) -> String? {
        if let bar = coveringBar(of: frame, chrome: chrome) {
            return "under the \(bar): the system bar's glass and scroll edge draw over the text"
        }
        guard let ratio = measuredContrast(of: element, frame: frame), ratio >= minimumContrast else { return nil }
        return String(format: "measured %.2f:1 on screen (the audit's estimate disagrees)", ratio)
    }

    static let minimumContrast = 4.5

    /// The tab bar or the navigation bar when it overlaps the frame (content scrolled under it).
    static func coveringBar(of frame: CGRect, chrome: Chrome) -> String? {
        if let tabBar = chrome.tabBar, tabBar.intersects(frame) { return "tab bar" }
        if let navigationBar = chrome.navigationBar, frame.minY < navigationBar.maxY { return "navigation bar" }
        return nil
    }

    /// Contrast of the element as drawn: ground is the median relative luminance of its pixels, ink the
    /// darkest 0.2 % on a light ground, the farther end on a dark one. Nil when it cannot be captured.
    @MainActor
    static func measuredContrast(of element: XCUIElement, frame: CGRect) -> Double? {
        guard frame.width >= 1, frame.height >= 1 else { return nil }
        guard let luminances = relativeLuminances(of: element.screenshot().image), luminances.count > 16
        else { return nil }
        let sorted = luminances.sorted()
        let ground = sorted[sorted.count / 2]
        // A short word in a full-width row covers little of it: the ink is the 0.2 % at either end.
        let darkInk = sorted[sorted.count / 500]
        let lightInk = sorted[sorted.count - 1 - sorted.count / 500]
        let ink = ground > 0.5 || ground - darkInk > lightInk - ground ? darkInk : lightInk
        return (max(ground, ink) + 0.05) / (min(ground, ink) + 0.05)
    }

    static func relativeLuminances(of image: UIImage) -> [Double]? {
        guard let cgImage = image.cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        func linear(_ value: UInt8) -> Double {
            let channel = Double(value) / 255
            return channel <= 0.039_28 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return stride(from: 0, to: pixels.count, by: 4).map { index in
            0.2126 * linear(pixels[index]) + 0.7152 * linear(pixels[index + 1])
                + 0.0722 * linear(pixels[index + 2])
        }
    }

    // MARK: - Touch targets

    /// Every hittable button, link, switch and slider on screen is at least 44 × 44 pt, except text links
    /// inside running text (vault mentions; WCAG 2.5.8 exempts inline targets), system bar items (the
    /// bar widens their hit area), the system switch inside a toggle row and the entries of ``AccessibilityAuditExemption/touchTargets``.
    @MainActor
    static func assertTouchTargets(in app: XCUIApplication, screen: String) {
        guard let root = try? app.snapshot() else { return }
        let chrome = Chrome(root)
        let window = chrome.window
        let bars = chrome.bars
        var stack: [(node: XCUIElementSnapshot, parent: XCUIElement.ElementType)] = [(root, .any)]
        while let (node, parent) = stack.popLast() {
            stack.append(contentsOf: node.children.map { ($0, node.elementType) })
            guard [.button, .link, .switch, .slider].contains(node.elementType), node.isEnabled else { continue }
            let frame = node.frame
            guard frame.width > 0, frame.height > 0, window.contains(frame) else { continue }
            // Layout lands on fractions of a point (43.99…); half a point is below what a finger feels.
            guard frame.width < minimumTarget - 0.5 || frame.height < minimumTarget - 0.5 else { continue }
            let described = "\(node.elementType.rawValue) '\(node.identifier)' '\(node.label)' \(frame)"
            let reason: String?
            if node.elementType == .link, node.identifier.hasPrefix("journal-entity://") {
                reason = "text link inside running text"
            } else if node.elementType == .switch, parent == .switch {
                reason = "the system switch inside its toggle row; the row is measured"
            } else if bars.contains(where: { $0.intersects(frame) }) {
                reason = "system bar item"
            } else {
                reason =
                    AccessibilityAuditExemption.touchTargets.first {
                        $0.matches(identifier: node.identifier, label: node.label)
                    }?.logged
            }
            if let reason {
                print("A11Y EXEMPT (\(screen)): type=target \(described) — \(reason)")
            } else {
                print("A11Y ISSUE (\(screen)): type=target \(described) — smaller than 44 × 44 pt")
                XCTFail("A11Y (\(screen)): touch target smaller than 44 × 44 pt: \(described)")
            }
        }
    }

    static let minimumTarget: CGFloat = 44

    // MARK: - Settling

    /// Waits until the element tree stops moving (a sheet rising, the iPad turning): an audit taken
    /// mid-animation measures frames and pixels on their way somewhere else. Returns the settled tree.
    @MainActor
    @discardableResult
    static func settle(_ app: XCUIApplication, timeout: TimeInterval = 6) -> XCUIElementSnapshot? {
        var last: XCUIElementSnapshot?
        func frames() -> [CGRect] {
            last = try? app.snapshot()
            guard let root = last else { return [] }
            var result: [CGRect] = []
            var stack = [root]
            while let node = stack.popLast() {
                result.append(node.frame)
                stack.append(contentsOf: node.children)
            }
            return result
        }
        let deadline = Date().addingTimeInterval(timeout)
        var previous = frames()
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            let current = frames()
            if current == previous { return last }
            previous = current
        }
        return last
    }

    static func name(of type: XCUIAccessibilityAuditType) -> String {
        let names: [(XCUIAccessibilityAuditType, String)] = [
            (.contrast, "contrast"), (.elementDetection, "elementDetection"), (.hitRegion, "hitRegion"),
            (.sufficientElementDescription, "sufficientElementDescription"), (.dynamicType, "dynamicType"),
            (.textClipped, "textClipped"), (.trait, "trait"),
        ]
        return names.first { $0.0 == type }?.1 ?? "\(type.rawValue)"
    }
}
