import Foundation
import XCTest

/// A step of the screen tour could not be reached; the tour records it and moves on.
struct ScreenTourError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

extension XCUIElement {
    /// One primary activation on either platform: a tap on iOS, a click on macOS.
    @MainActor
    func tourTap() {
        #if os(macOS)
            click()
        #else
            tap()
        #endif
    }

    /// Opens the context menu: a long press on iOS, a secondary click on macOS.
    @MainActor
    func tourContextMenu() {
        #if os(macOS)
            rightClick()
        #else
            press(forDuration: 1.3)
        #endif
    }
}

extension XCUICoordinate {
    @MainActor
    func tourTap() {
        #if os(macOS)
            click()
        #else
            tap()
        #endif
    }
}

/// Drives the app for `ScreenTourUITests` (iPhone) and `ScreenTourMacUITests` (Mac): finds controls by identifier first and by
/// accessibility label second, writes numbered PNGs, and never fails the test for a
/// screen it cannot reach (the step lands in `atlananlar.txt` instead).
@MainActor
final class ScreenTourDriver {
    private(set) var app: XCUIApplication
    private let directory: URL
    private let vaultURL: URL
    private let test: XCTestCase
    private let dumpsTree: Bool
    private var launchArguments: [String]
    private let launchEnvironment: [String: String]
    /// Runs after every launch, before the tour waits for the first screen (Mac sizes its window here).
    var afterLaunch: @MainActor (ScreenTourDriver) -> Void = { _ in }
    /// What a screenshot shows. `nil` is the whole screen (iPhone); Mac names a window so that
    /// nothing else on the desktop gets into the image.
    var captureTarget: (@MainActor (XCUIApplication) -> XCUIElement?)?
    /// Where in the captured window a page scroll happens on Mac (the detail column by default);
    /// unused on iPhone, where a swipe moves the whole screen.
    var scrollAnchor = CGVector(dx: 0.72, dy: 0.6)
    private(set) var written: [String] = []
    private(set) var skipped: [String] = []
    private var lastShot = "-"

    /// Turkish is the development language: the label fallbacks below are Turkish source keys.
    nonisolated static let turkish = ["-AppleLanguages", "(tr)", "-AppleLocale", "tr_TR"]

    init(
        directory: URL, vaultURL: URL, test: XCTestCase, dumpsTree: Bool,
        launchArguments: [String] = ScreenTourDriver.turkish, launchEnvironment: [String: String] = [:]
    ) {
        self.directory = directory
        self.vaultURL = vaultURL
        self.test = test
        self.dumpsTree = dumpsTree
        self.launchArguments = launchArguments
        self.launchEnvironment = launchEnvironment
        app = ScreenTourDriver.launch(vaultURL: vaultURL, arguments: launchArguments, environment: launchEnvironment)
    }

    // MARK: Launch

    private static func launch(
        vaultURL: URL, arguments: [String], environment: [String: String]
    ) -> XCUIApplication {
        UITestSupport.launchApp(
            vaultURL: vaultURL, quickEntryText: nil, extraArguments: arguments, extraEnvironment: environment)
    }

    /// The tour never edits the vault, so a fresh launch is always a safe way back to a known state.
    /// `arguments` replaces the launch arguments from here on (Mac switches appearance this way).
    func relaunch(arguments: [String]? = nil) {
        if let arguments { launchArguments = arguments }
        app.terminate()
        app = ScreenTourDriver.launch(vaultURL: vaultURL, arguments: launchArguments, environment: launchEnvironment)
        afterLaunch(self)
        _ = id("screen.today").waitForExistence(timeout: 30)
    }

    // MARK: Steps

    /// Runs one self-contained part of the tour. A thrown error skips the rest of that part.
    func step(_ name: String, _ body: () throws -> Void) {
        do {
            try body()
        } catch {
            skip(name, reason: "\(error) (son alınan: \(lastShot))")
            dumpTree(named: "atlanan-" + name)
            relaunch()
        }
    }

    /// For a sub-step whose failure leaves the screen as it was (nothing tapped yet).
    func optional(_ name: String, _ body: () throws -> Void) {
        do {
            try body()
        } catch {
            skip(name, reason: "\(error)")
            dumpTree(named: "atlanan-" + name)
        }
    }

    func skip(_ name: String, reason: String) {
        let line = "\(name): \(reason)"
        skipped.append(line)
        log("ATLANDI \(line)")
    }

    func log(_ message: String) {
        print("[ekran-turu] \(message)")
    }

    // MARK: Screenshots

    func shot(_ name: String, settle: TimeInterval = 0.8) {
        pause(settle)
        let file = name + ".png"
        let data = (captureTarget?(app)?.screenshot() ?? XCUIScreen.main.screenshot()).pngRepresentation
        do {
            try data.write(to: directory.appendingPathComponent(file), options: .atomic)
        } catch {
            // The simulator could not write to the host path: keep the image in the result
            // bundle so the script can export it (`xcresulttool export attachments`).
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
            attachment.name = file
            attachment.lifetime = .keepAlways
            test.add(attachment)
        }
        written.append(file)
        lastShot = name
        log("görüntü \(file)")
        dumpTree(named: name)
    }

    /// Scrolls the visible page once and takes a second image of the same screen.
    func scrolledShot(_ name: String) {
        scrollPage()
        shot(name, settle: 1.5)
    }

    /// One page towards the end of the content (or back towards its start).
    func scrollPage(back: Bool = false) {
        #if os(macOS)
            let target = captureTarget?(app) ?? app.windows.firstMatch
            guard target.exists else { return }
            let point = target.coordinate(withNormalizedOffset: scrollAnchor)
            point.hover()
            point.scroll(byDeltaX: 0, deltaY: back ? 4000 : -420)
        #else
            if back { app.swipeDown() } else { app.swipeUp() }
        #endif
    }

    private func dumpTree(named name: String) {
        guard dumpsTree else { return }
        let folder = directory.appendingPathComponent("agac", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var text = app.debugDescription
        #if os(macOS)
            // Windows only: the menu bar that follows lists the system menus (recent documents,
            // the account name), which have no place in a dump.
            if let menuBar = text.range(of: "\n    MenuBar,") { text = String(text[..<menuBar.lowerBound]) }
        #endif
        do {
            try text.write(to: folder.appendingPathComponent(name + ".txt"), atomically: true, encoding: .utf8)
        } catch {
            // Same fallback as the images; the script puts "agac-" attachments back under agac/.
            let attachment = XCTAttachment(string: text)
            attachment.name = "agac-" + name + ".txt"
            attachment.lifetime = .keepAlways
            test.add(attachment)
        }
    }

    func writeSkipped() {
        let text = skipped.isEmpty ? "" : skipped.joined(separator: "\n") + "\n"
        do {
            try text.write(
                to: directory.appendingPathComponent("atlananlar.txt"), atomically: true, encoding: .utf8)
        } catch {
            let attachment = XCTAttachment(string: text)
            attachment.name = "atlananlar.txt"
            attachment.lifetime = .keepAlways
            test.add(attachment)
        }
        log("bitti: \(written.count) görüntü, \(skipped.count) atlanan")
    }

    func pause(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    // MARK: Finding

    func id(_ identifier: String) -> XCUIElement {
        UITestSupport.element(in: app, identifier: identifier)
    }

    func firstHittable(_ query: XCUIElementQuery, limit: Int = 8) -> XCUIElement? {
        let count = min(query.count, limit)
        for index in 0..<count {
            let element = query.element(boundBy: index)
            if element.exists, element.isHittable { return element }
        }
        return nil
    }

    static func exact(_ label: String) -> NSPredicate {
        NSPredicate(format: "label ==[c] %@", label)
    }

    /// Matches "Ad", "Ad, değer" and "Etiket, Ad": a menu picker reads its title with its value.
    static func loose(_ label: String) -> NSPredicate {
        NSPredicate(
            format: "label ==[c] %@ OR label BEGINSWITH[c] %@ OR label ENDSWITH[c] %@",
            label, label + ",", ", " + label)
    }

    /// A hittable button with exactly this label.
    func button(_ label: String) -> XCUIElement? {
        firstHittable(app.buttons.matching(ScreenTourDriver.exact(label)))
    }

    /// An item of an open menu with exactly this title (Mac menus are not buttons).
    func menuItem(_ label: String) -> XCUIElement? {
        firstHittable(app.menuItems.matching(NSPredicate(format: "title ==[c] %@ OR label ==[c] %@", label, label)))
    }

    /// Identifier first, then label: buttons before any other element type.
    func find(ids: [String] = [], labels: [String] = [], timeout: TimeInterval = 4) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for identifier in ids {
                if let match = firstHittable(app.descendants(matching: .any).matching(identifier: identifier)) {
                    return match
                }
            }
            for label in labels {
                if let match = firstHittable(app.buttons.matching(ScreenTourDriver.loose(label))) { return match }
            }
            for label in labels {
                let others = app.descendants(matching: .any).matching(ScreenTourDriver.exact(label))
                if let match = firstHittable(others) { return match }
            }
            pause(0.3)
        } while Date() < deadline
        return nil
    }

    func require(ids: [String] = [], labels: [String] = [], timeout: TimeInterval = 6) throws -> XCUIElement {
        if let element = find(ids: ids, labels: labels, timeout: timeout) { return element }
        throw ScreenTourError("bulunamadı: kimlik \(ids), etiket \(labels)")
    }

    func tap(ids: [String] = [], labels: [String] = [], timeout: TimeInterval = 6) throws {
        try require(ids: ids, labels: labels, timeout: timeout).tourTap()
    }

    /// Any hittable element whose label contains the text (rows, cards, links).
    func containing(_ text: String, timeout: TimeInterval = 4) -> XCUIElement? {
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", text)
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for query in [app.staticTexts, app.buttons, app.cells, app.descendants(matching: .any)] {
                if let match = firstHittable(query.matching(predicate), limit: 4) { return match }
            }
            pause(0.3)
        } while Date() < deadline
        return nil
    }

    /// Finds a row by its text, scrolling the page a few times when it is below the fold.
    func row(_ text: String, swipes: Int = 4) throws -> XCUIElement {
        for attempt in 0...swipes {
            if let match = containing(text, timeout: attempt == 0 ? 4 : 1) { return match }
            scrollPage()
            pause(0.6)
        }
        throw ScreenTourError("satır bulunamadı: \(text)")
    }

    /// Scrolls until a control with one of these labels can be touched.
    func reach(labels: [String], swipes: Int = 5) throws -> XCUIElement {
        for attempt in 0...swipes {
            if let match = find(labels: labels, timeout: attempt == 0 ? 3 : 0.5) { return match }
            scrollPage()
            pause(0.6)
        }
        throw ScreenTourError("bulunamadı (kaydırarak): \(labels)")
    }

    func reach(containing text: String, swipes: Int = 5) throws -> XCUIElement {
        try row(text, swipes: swipes)
    }

    /// A text field by identifier, then by placeholder or label.
    func field(ids: [String], placeholders: [String], timeout: TimeInterval = 6) throws -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for identifier in ids {
                if let match = firstHittable(app.descendants(matching: .any).matching(identifier: identifier)) {
                    return match
                }
            }
            for text in placeholders {
                let predicate = NSPredicate(format: "placeholderValue ==[c] %@ OR label ==[c] %@", text, text)
                for query in [app.textFields, app.searchFields] {
                    if let match = firstHittable(query.matching(predicate)) { return match }
                }
            }
            pause(0.3)
        } while Date() < deadline
        throw ScreenTourError("alan bulunamadı: kimlik \(ids), yer tutucu \(placeholders)")
    }

    func scrollToTop() {
        scrollPage(back: true)
        scrollPage(back: true)
        pause(0.6)
    }

    func waitFor(ids: [String] = [], labels: [String] = [], timeout: TimeInterval = 8) throws {
        _ = try require(ids: ids, labels: labels, timeout: timeout)
    }

    // MARK: Getting back to a root screen

    private var tabBarIsReachable: Bool {
        let first = app.tabBars.buttons.firstMatch
        return first.exists && first.isHittable
    }

    /// Closes menus, sheets and pushed sheet pages with actions that never save anything.
    func dismissOverlays() {
        for _ in 0..<8 {
            if tabBarIsReachable { return }
            if let close = find(labels: ["Kapat", "Vazgeç"], timeout: 0) {
                close.tourTap()
            } else if let discard = button("At") {
                discard.tourTap()
            } else if let back = backButton() {
                back.tourTap()
            } else if let done = firstHittable(app.navigationBars.buttons.matching(ScreenTourDriver.exact("Bitti"))) {
                // Only reached on an untouched editor: "Bitti" there closes without writing.
                done.tourTap()
            } else {
                // Unknown cover (keyboard, menu without a known item): no blind taps.
                break
            }
            pause(0.6)
        }
        if !tabBarIsReachable {
            log("kök ekrana dönülemedi; uygulama yeniden başlatılıyor")
            relaunch()
        }
    }

    func backButton() -> XCUIElement? {
        if let byId = firstHittable(app.navigationBars.buttons.matching(identifier: "BackButton")) { return byId }
        for label in ["Geri", "Back"] {
            if let match = firstHittable(app.navigationBars.buttons.matching(ScreenTourDriver.exact(label))) {
                return match
            }
        }
        return nil
    }

    func goBack() throws {
        guard let back = backButton() ?? firstHittable(app.navigationBars.buttons, limit: 1) else {
            throw ScreenTourError("geri düğmesi bulunamadı")
        }
        back.tourTap()
        pause(0.5)
    }

    /// Closes an open system menu by touching the dimmed area far from its items.
    /// Does nothing when none of `items` is showing, so it never touches page content.
    func closeMenu(items: [String]) {
        #if os(macOS)
            // A Mac menu closes with Escape; a click beside it could land on another window.
            if items.contains(where: { menuItem($0) != nil }) {
                app.typeKey(.escape, modifierFlags: [])
                pause(0.6)
            }
        #else
            closeTouchMenu(items: items)
        #endif
    }

    private func closeTouchMenu(items: [String]) {
        let screen = app.frame
        var points = [(0.5, 0.93), (0.5, 0.08), (0.93, 0.5), (0.07, 0.5)]
        for _ in 0..<points.count {
            let frames = items.compactMap { button($0)?.frame }
            guard let first = frames.first else { return }
            let menu = frames.dropFirst().reduce(first) { $0.union($1) }
            let center = CGPoint(x: menu.midX, y: menu.midY)
            func distance(_ point: (Double, Double)) -> Double {
                hypot(point.0 * screen.width - center.x, point.1 * screen.height - center.y)
            }
            points.sort { distance($0) > distance($1) }
            let point = points.removeFirst()
            app.coordinate(withNormalizedOffset: CGVector(dx: point.0, dy: point.1)).tourTap()
            pause(0.6)
        }
    }

    /// Opens a tab at its root. `marker` is the root screen identifier, `title` its headline.
    func home(_ tab: String, marker: String?, title: String?) throws {
        dismissOverlays()
        let button = UITestSupport.tab(in: app, identifier: tab)
        guard button.waitForExistence(timeout: 10) else { throw ScreenTourError("sekme yok: \(tab)") }
        button.tourTap()
        if !UITestSupport.waitUntilSelected(button, timeout: 3) {
            button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tourTap()
            _ = UITestSupport.waitUntilSelected(button, timeout: 3)
        }
        if isAtRoot(marker: marker, title: title, timeout: 3) { return }
        // A second tap on the selected tab pops its navigation stack.
        button.tourTap()
        if isAtRoot(marker: marker, title: title, timeout: 5) { return }
        while let back = backButton() {
            back.tourTap()
            pause(0.5)
            if isAtRoot(marker: marker, title: title, timeout: 1) { return }
        }
        throw ScreenTourError("kök ekran açılmadı: \(tab)")
    }

    private func isAtRoot(marker: String?, title: String?, timeout: TimeInterval) -> Bool {
        if let marker, id(marker).waitForExistence(timeout: timeout) { return true }
        // Not every root has an identifier (and older simulators hide container identifiers):
        // accept the headline when no back button is showing.
        guard let title else { return false }
        return app.staticTexts.matching(ScreenTourDriver.exact(title)).firstMatch.waitForExistence(timeout: timeout)
            && backButton() == nil
    }

    // MARK: "Pick one" controls (menu today, tabs after the control patterns work)

    private func visibleCount(_ options: [String]) -> Int {
        #if os(macOS)
            options.filter { button($0) != nil || menuItem($0) != nil }.count
        #else
            options.filter { button($0) != nil }.count
        #endif
    }

    /// Selects `option` in a control that is either a row of tabs or a menu.
    /// - Parameters:
    ///   - options: every label the control can show; two or more visible means tabs (or an open menu).
    ///   - listTab: tab to select first when the option lives in a menu under that tab.
    ///   - openers: identifiers and labels of the menu button, tried in order.
    func choose(
        _ option: String, among options: [String], listTab: String? = nil,
        openerIDs: [String], openerLabels: [String]
    ) throws {
        let before = visibleCount(options)
        if let direct = button(option) {
            direct.tourTap()
            pause(0.5)
            // The button was the closed menu showing the current value: pick the same value to close it.
            if before < 2, visibleCount(options) >= 2, let again = button(option) { again.tourTap() }
            pause(0.5)
            return
        }
        if let listTab, let tab = button(listTab) {
            tab.tourTap()
            pause(0.5)
            if let direct = button(option) {
                direct.tourTap()
                pause(0.5)
                return
            }
        }
        for opener in openerCandidates(ids: openerIDs, labels: openerLabels + options) {
            opener.tourTap()
            pause(0.5)
            if let item = find(labels: [option], timeout: 2) {
                item.tourTap()
                pause(0.6)
                return
            }
            closeMenu(items: options)
        }
        throw ScreenTourError("seçenek seçilemedi: \(option)")
    }

    /// Opens the menu form of a "pick one" control and leaves it open for a screenshot.
    func openChooser(options: [String], openerIDs: [String], openerLabels: [String]) throws {
        if visibleCount(options) >= 2 {
            throw ScreenTourError("denetim sekme biçiminde; açık menü durumu yok")
        }
        for opener in openerCandidates(ids: openerIDs, labels: openerLabels + options) {
            opener.tourTap()
            pause(0.6)
            if visibleCount(options) >= 2 { return }
            closeMenu(items: options)
        }
        throw ScreenTourError("menü açılamadı: \(openerIDs) \(openerLabels)")
    }

    /// Opens a plain menu (filter, board options) and waits for one of its items.
    func openMenu(ids: [String], labels: [String], expecting items: [String]) throws {
        for opener in openerCandidates(ids: ids, labels: labels) {
            opener.tourTap()
            pause(0.6)
            if find(labels: items, timeout: 2) != nil { return }
        }
        throw ScreenTourError("menü açılamadı: \(ids) \(labels)")
    }

    private func openerCandidates(ids: [String], labels: [String]) -> [XCUIElement] {
        var result: [XCUIElement] = []
        for identifier in ids {
            if let match = find(ids: [identifier], timeout: 0) { result.append(match) }
        }
        for label in labels {
            if let match = firstHittable(app.buttons.matching(ScreenTourDriver.loose(label))) {
                result.append(match)
            }
        }
        return result
    }

    // MARK: Text

    /// Types into a field and returns a closure-free way to clear it: the same number of deletes.
    func type(_ text: String, into field: XCUIElement) {
        field.tourTap()
        pause(0.4)
        app.typeText(text)
        pause(0.8)
    }

    func erase(_ count: Int) {
        app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count))
        pause(0.4)
    }

    // MARK: Vault integrity

    /// The tour must leave the vault copy byte-identical to the fixture.
    /// `copy` is the folder the app really worked on, when the test can see it (Mac).
    func changedVaultFiles(fixture: URL, copy: URL? = nil) -> [String] {
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(at: fixture, includingPropertiesForKeys: nil) else { return [] }
        var changed: [String] = []
        for case let file as URL in enumerator where file.pathExtension == "md" {
            let relative = String(file.path.dropFirst(fixture.path.count + 1))
            let other = (copy ?? vaultURL).appendingPathComponent(relative)
            if manager.contents(atPath: file.path) != manager.contents(atPath: other.path) {
                changed.append(relative)
            }
        }
        return changed.sorted()
    }
}
