import UIKit
import XCTest

/// Settings hub (iPhone and iPad): every section row opens its own page. The six rows once sat in
/// one list row, and a tap on any of them opened the last one (Tanılama).
final class SettingsHubUITests: XCTestCase {
    private var vaultURL: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        UITestSupport.installSystemAlertMonitor(on: self)
        vaultURL = try UITestSupport.prepareSampleVault()
    }

    override func tearDownWithError() throws {
        if let vaultURL { try? FileManager.default.removeItem(at: vaultURL) }
    }

    /// `SettingsSection` raw values, in the hub's order.
    private let sections = [
        "quickEntry", "privacy", "notifications", "calendarAndLocation", "vault", "diagnostics", "about",
    ]

    @MainActor
    func testEverySectionRowOpensItsOwnPage() throws {
        let app = UITestSupport.launchApp(vaultURL: vaultURL, quickEntryText: nil)
        UITestSupport.activateSystemAlertMonitor(in: app)
        UITestSupport.waitForExistence(UITestSupport.element(in: app, identifier: "screen.today"), timeout: 30)

        let settings = UITestSupport.element(in: app, identifier: "button.settings")
        UITestSupport.waitForExistence(settings)
        settings.tap()
        let hub = UITestSupport.element(in: app, identifier: "screen.settings")
        UITestSupport.waitForExistence(hub)

        for section in sections {
            let row = UITestSupport.element(in: app, identifier: "settings.section.\(section)")
            UITestSupport.waitForExistence(row)
            for _ in 0..<4 where !row.isHittable {
                hub.swipeUp(velocity: .slow)
            }
            XCTAssertTrue(row.isHittable, "row \(section) is not reachable")
            row.tap()

            let page = UITestSupport.element(in: app, identifier: "screen.settings.\(section)")
            XCTAssertTrue(page.waitForExistence(timeout: 10), "row \(section) did not open its page")
            goBack(in: app)
            XCTAssertTrue(page.waitForNonExistence(timeout: 10), "page \(section) did not close")
            UITestSupport.waitForExistence(hub)
        }
    }

    /// A scrolled page goes under an opaque bar (iPhone and iPad): the band of the bar beside the
    /// round back button shows no text. Under a clear bar the page title and rows read through
    /// ("Sayılar" under the back button on the iPad form sheet).
    @MainActor
    func testScrolledPageStaysUnderAnOpaqueBar() throws {
        // The band is read in the screenshot's pixels; those follow the screen only upright.
        XCUIDevice.shared.orientation = .portrait
        let app = UITestSupport.launchApp(vaultURL: vaultURL, quickEntryText: nil)
        UITestSupport.activateSystemAlertMonitor(in: app)
        UITestSupport.waitForExistence(UITestSupport.element(in: app, identifier: "screen.today"), timeout: 30)
        UITestSupport.element(in: app, identifier: "button.settings").tap()
        let hub = UITestSupport.element(in: app, identifier: "screen.settings")
        UITestSupport.waitForExistence(hub)
        let row = UITestSupport.element(in: app, identifier: "settings.section.diagnostics")
        UITestSupport.waitForExistence(row)
        for _ in 0..<4 where !row.isHittable {
            hub.swipeUp(velocity: .slow)
        }
        row.tap()
        let page = UITestSupport.element(in: app, identifier: "screen.settings.diagnostics")
        UITestSupport.waitForExistence(page)

        // The sheet's bar: as wide as the page at most (iPad: the shell's bars lie behind the sheet).
        let pageFrame = page.frame
        let bar = try XCTUnwrap(
            app.navigationBars.allElementsBoundByIndex.first {
                $0.frame.minX >= pageFrame.minX - 1 && $0.frame.maxX <= pageFrame.maxX + 1
                    && $0.buttons.firstMatch.exists
            }, "no bar over the page \(pageFrame)")
        let back = bar.buttons.firstMatch
        // Slow, held drag: the page stops where it was let go, its title and rows under the bar.
        let start = page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        start.press(
            forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -140)), withVelocity: 300,
            thenHoldForDuration: 0.3)
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))

        let band = CGRect(
            x: back.frame.maxX + 12, y: bar.frame.minY + 4,
            width: bar.frame.maxX - back.frame.maxX - 24, height: bar.frame.height - 8)
        let screenshot = app.screenshot()
        let dark = try Self.darkPixelShare(in: band, of: screenshot.image)
        if dark > 0.002 {
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertLessThan(dark, 0.002, "text shows through the bar beside the back button (\(dark))")
    }

    /// Share of pixels in `rect` (points) much darker than the band's own paper.
    private static func darkPixelShare(in rect: CGRect, of image: UIImage) throws -> Double {
        let cgImage = try XCTUnwrap(image.cgImage)
        let scale = CGFloat(cgImage.width) / image.size.width
        let pixels = CGRect(
            x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale
        ).integral
        let crop = try XCTUnwrap(cgImage.cropping(to: pixels))
        let width = crop.width
        let height = crop.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        XCTAssertTrue(drawn, "could not read the screenshot")
        var lumas: [Double] = []
        lumas.reserveCapacity(width * height)
        for index in stride(from: 0, to: data.count, by: 4) {
            let red = Double(data[index])
            let green = Double(data[index + 1])
            let blue = Double(data[index + 2])
            lumas.append((0.299 * red + 0.587 * green + 0.114 * blue) / 255)
        }
        let paper = lumas.sorted()[lumas.count / 2]
        let darkCount = lumas.filter { paper - $0 > 0.35 }.count
        return Double(darkCount) / Double(max(lumas.count, 1))
    }

    /// The page's back item: Kenet's own (`button.back`) where it draws one, else the bar's.
    @MainActor
    private func goBack(in app: XCUIApplication) {
        let inkBack = app.buttons.matching(identifier: "button.back").firstMatch
        if inkBack.exists && inkBack.isHittable {
            inkBack.tap()
            return
        }
        let barBack = app.navigationBars.buttons.firstMatch
        UITestSupport.waitForExistence(barBack)
        barBack.tap()
    }
}
