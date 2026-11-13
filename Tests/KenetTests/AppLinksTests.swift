import Foundation
import Testing

@testable import Kenet

/// Hakkında links: the addresses decided on 2026-10-21, the page language following the app's.
struct AppLinksTests {
    @Test func turkishAppOpensTheTurkishPages() {
        let tr = Locale(identifier: "tr_TR")
        #expect(AppLinks.privacyPolicy(locale: tr).absoluteString == "https://kenet.app/gizlilik")
        #expect(AppLinks.support(locale: tr).absoluteString == "https://kenet.app/destek")
    }

    @Test func englishAppOpensTheEnglishPages() {
        let en = Locale(identifier: "en_US")
        #expect(AppLinks.privacyPolicy(locale: en).absoluteString == "https://kenet.app/en/privacy")
        #expect(AppLinks.support(locale: en).absoluteString == "https://kenet.app/en/support")
    }

    @Test func versionTextJoinsVersionAndBuild() {
        let text = AppVersionText.text()
        #expect(!text.isEmpty)
    }
}
