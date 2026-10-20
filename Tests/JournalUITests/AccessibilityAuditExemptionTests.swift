import XCTest

/// The exemption table names elements the way the audit reports them, in both test languages.
/// No app is launched; labels are matched as the audit's handler matches them.
final class AccessibilityAuditExemptionTests: XCTestCase {
    private func isExempt(_ type: XCUIAccessibilityAuditType, identifier: String = "", label: String) -> Bool {
        AccessibilityAuditExemption.all.contains {
            $0.type == type && $0.matches(identifier: identifier, label: label)
        }
    }

    func testCatalogKeyMatchesEveryLanguage() {
        XCTAssertTrue(isExempt(.dynamicType, label: "Bölüm"))
        XCTAssertTrue(isExempt(.dynamicType, label: "Section"))
        XCTAssertFalse(isExempt(.dynamicType, label: "Sections"))
    }

    func testFormatArgumentMatchesAnyText() {
        XCTAssertTrue(isExempt(.dynamicType, label: "Show all (13)"))
        XCTAssertTrue(isExempt(.dynamicType, label: "Tümünü göster (2)"))
        XCTAssertTrue(isExempt(.dynamicType, label: "Person · Lale, Ortak · Last seen: Oct 10, 2026"))
    }

    func testCalendarWeekdayLettersInBothLanguages() {
        for letter in ["S", "M", "T", "W", "F", "P", "Ç", "C"] {
            XCTAssertTrue(isExempt(.dynamicType, label: letter), letter)
        }
        XCTAssertFalse(isExempt(.dynamicType, label: "Ş"))
        XCTAssertFalse(isExempt(.dynamicType, label: "SM"))
        // The letter rule is for dynamicType only.
        XCTAssertFalse(isExempt(.contrast, label: "S"))
    }

    func testUnlistedElementIsNotExempt() {
        XCTAssertFalse(isExempt(.dynamicType, label: "Günü kapat"))
        XCTAssertFalse(isExempt(.textClipped, identifier: "button.closeDay", label: "Close the day"))
    }
}
