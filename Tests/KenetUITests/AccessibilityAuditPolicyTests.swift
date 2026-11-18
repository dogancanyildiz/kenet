import XCTest

/// Which system bar the contrast policy says covers a frame. No app is launched; the window and the
/// bars are the iPhone 17e portrait frames the audit reads.
@MainActor
final class AccessibilityAuditPolicyTests: XCTestCase {
    private let window = CGRect(x: 0, y: 0, width: 390, height: 844)

    private func chrome(tabBar: CGRect? = nil, navigationBar: CGRect? = nil) -> AccessibilityAuditPolicy.Chrome {
        var chrome = AccessibilityAuditPolicy.Chrome(nil)
        chrome.window = window
        chrome.tabBar = tabBar
        chrome.navigationBar = navigationBar
        return chrome
    }

    /// The entity page has no navigation bar: a row cut by the window's top edge is under the status bar.
    func testRowCutByTheTopEdgeIsUnderTheStatusBar() {
        let row = CGRect(x: 32, y: -18.5, width: 326, height: 44)
        XCTAssertEqual(AccessibilityAuditPolicy.coveringBar(of: row, chrome: chrome()), "status bar")
    }

    /// A row wholly inside the window is measured, including one that touches the top edge.
    func testRowInsideTheWindowIsNotCovered() {
        XCTAssertNil(
            AccessibilityAuditPolicy.coveringBar(of: CGRect(x: 32, y: 300, width: 326, height: 44), chrome: chrome()))
        XCTAssertNil(
            AccessibilityAuditPolicy.coveringBar(of: CGRect(x: 32, y: 0, width: 326, height: 44), chrome: chrome()))
        XCTAssertNil(
            AccessibilityAuditPolicy.coveringBar(of: CGRect(x: 32, y: 62, width: 326, height: 44), chrome: chrome()))
    }

    /// A frame wholly above the window is not drawn at all; the rule is for cut rows only.
    func testFrameWhollyAboveTheWindowIsNotCovered() {
        XCTAssertNil(
            AccessibilityAuditPolicy.coveringBar(of: CGRect(x: 32, y: -60, width: 326, height: 44), chrome: chrome()))
    }

    /// The bars keep their own rules and names.
    func testTabBarAndNavigationBarStillCover() {
        let bars = chrome(
            tabBar: CGRect(x: 0, y: 760, width: 390, height: 84),
            navigationBar: CGRect(x: 0, y: 62, width: 390, height: 54))
        XCTAssertEqual(
            AccessibilityAuditPolicy.coveringBar(of: CGRect(x: 16, y: 767, width: 175, height: 24), chrome: bars),
            "tab bar")
        XCTAssertEqual(
            AccessibilityAuditPolicy.coveringBar(of: CGRect(x: 16, y: 80, width: 175, height: 24), chrome: bars),
            "navigation bar")
        XCTAssertNil(
            AccessibilityAuditPolicy.coveringBar(of: CGRect(x: 16, y: 300, width: 175, height: 24), chrome: bars))
    }
}
