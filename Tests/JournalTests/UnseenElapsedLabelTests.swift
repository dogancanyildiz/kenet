import Foundation
import Testing

@testable import Journal

struct UnseenElapsedLabelTests {
    private func text(_ days: Int, _ code: String) throws -> String {
        let path = try #require(Bundle.main.path(forResource: code, ofType: "lproj"))
        return String(
            localized: UnseenElapsedLabel.resource(
                days: days, locale: Locale(identifier: code), bundle: .atURL(URL(fileURLWithPath: path))))
    }

    @Test func englishPluralizesDaysAndWeeks() throws {
        #expect(try text(1, "en") == "1 day ago")
        #expect(try text(3, "en") == "3 days ago")
        #expect(try text(7, "en") == "1 week ago")
        #expect(try text(20, "en") == "2 weeks ago")
    }

    @Test func turkishKeepsTheDurativeSuffix() throws {
        #expect(try text(1, "tr") == "1 gündür")
        #expect(try text(14, "tr") == "2 haftadır")
    }
}
