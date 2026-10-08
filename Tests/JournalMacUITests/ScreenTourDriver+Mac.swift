import AppKit
import XCTest

/// Mac side of the screen tour: one fixed-size window, a sidebar instead of tabs, sheets that
/// close with Escape, and a Settings window and a quick-entry panel of their own.
extension ScreenTourDriver {
    /// Every image of the main window has this size (points), whatever the last run left behind.
    nonisolated static let windowSize = CGSize(width: 1280, height: 800)
    /// Top-left corner on the main display; XCUITest cannot capture a window on a second display.
    nonisolated static let windowOrigin = CGPoint(x: 120, y: 60)

    // MARK: Windows

    /// Launch arguments that make AppKit restore the journal window at the tour's frame on the
    /// main display (the argument domain wins over the saved frame and is never written back).
    nonisolated static func windowFrameArguments() -> [String] {
        guard let screen = NSScreen.screens.first else { return [] }
        let visible = screen.visibleFrame
        let x = Int(screen.frame.minX + windowOrigin.x)
        let y = Int(screen.frame.maxY - windowOrigin.y - windowSize.height)
        let frame =
            "\(x) \(y) \(Int(windowSize.width)) \(Int(windowSize.height)) "
            + "\(Int(visible.minX)) \(Int(visible.minY)) \(Int(visible.width)) \(Int(visible.height)) "
        return ["-NSWindow Frame main-AppWindow-1", frame, "-ApplePersistenceIgnoreState", "YES"]
    }

    /// The journal window (SwiftUI names it after the scene; `MainWindowMarker` may rename it).
    var mainWindow: XCUIElement {
        for identifier in ["main-AppWindow-1", "journal-main"] {
            let window = app.windows.matching(identifier: identifier).firstMatch
            if window.exists { return window }
        }
        return app.windows.firstMatch
    }

    /// The Settings scene (SwiftUI gives its window a fixed identifier).
    var settingsWindow: XCUIElement? {
        let window = app.windows.matching(identifier: "com_apple_SwiftUI_Settings_window").firstMatch
        return window.exists ? window : nil
    }

    /// The floating quick-entry panel: a borderless panel, which the tree reports as a dialog.
    var quickEntryPanel: XCUIElement? {
        for query in [app.dialogs, app.windows] {
            let panel = query.containing(.textField, identifier: "field.quickEntry").firstMatch
            if panel.exists, !panel.identifier.hasPrefix("main-") { return panel }
        }
        return nil
    }

    /// Selects a tab of the Settings window and checks that it took: the window is titled
    /// after its tab, and an image of the wrong tab under the right name would mislead.
    func settingsTab(_ title: String) throws {
        guard let window = settingsWindow else { throw ScreenTourError("Ayarlar penceresi yok") }
        for _ in 0..<2 {
            let tab = window.toolbars.buttons[title]
            guard tab.waitForExistence(timeout: 3) else { break }
            tab.click()
            pause(0.8)
            if window.title == title { return }
        }
        throw ScreenTourError("Ayarlar sekmesi açılmadı: \(title) (pencere başlığı: \(window.title))")
    }

    /// Waits for the journal window and reports when it did not come up at the tour's size.
    func fitMainWindow() {
        let window = mainWindow
        guard window.waitForExistence(timeout: 30) else { return }
        let size = window.frame.size
        log("pencere \(window.frame)")
        if abs(size.width - ScreenTourDriver.windowSize.width) > 1
            || abs(size.height - ScreenTourDriver.windowSize.height) > 1
        {
            skip("UYARI pencere boyutu", reason: "\(Int(size.width))x\(Int(size.height)), beklenen 1280x800")
        }
    }

    func captureMainWindow() {
        captureTarget = { [unowned self] _ in self.mainWindow }
        scrollAnchor = CGVector(dx: 0.72, dy: 0.6)
    }

    // MARK: Finding (Mac texts carry their string in `value`, menus are menu items)

    /// A control named by its label or, as Mac menu buttons and menu items are, by its title.
    private static func control(_ text: String) -> NSPredicate {
        NSPredicate(
            format: "label ==[c] %@ OR title ==[c] %@ OR label BEGINSWITH[c] %@ OR label ENDSWITH[c] %@",
            text, text, text + ",", ", " + text)
    }

    private static func text(_ text: String) -> NSPredicate {
        NSPredicate(format: "label ==[c] %@ OR value ==[c] %@ OR title ==[c] %@", text, text, text)
    }

    /// Identifier first; then a control with this label; then a text showing it.
    func macFind(
        _ texts: [String], ids: [String] = [], in root: XCUIElement? = nil, timeout: TimeInterval = 4
    ) -> XCUIElement? {
        let root = root ?? app
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for identifier in ids {
                if let match = firstHittable(root.descendants(matching: .any).matching(identifier: identifier)) {
                    return match
                }
            }
            for text in texts {
                let controls = [
                    root.menuItems, root.buttons, root.radioButtons, root.popUpButtons, root.menuButtons,
                    root.checkBoxes, root.switches, root.links,
                ]
                for query in controls {
                    if let match = firstHittable(query.matching(ScreenTourDriver.control(text))) { return match }
                }
                for query in [root.staticTexts, root.cells, root.descendants(matching: .any)] {
                    if let match = firstHittable(query.matching(ScreenTourDriver.text(text)), limit: 4) {
                        return match
                    }
                }
            }
            pause(0.3)
        } while Date() < deadline
        return nil
    }

    func macRequire(
        _ texts: [String], ids: [String] = [], in root: XCUIElement? = nil, timeout: TimeInterval = 6
    ) throws -> XCUIElement {
        if let element = macFind(texts, ids: ids, in: root, timeout: timeout) { return element }
        throw ScreenTourError("bulunamadı: kimlik \(ids), metin \(texts)")
    }

    func macClick(
        _ texts: [String], ids: [String] = [], in root: XCUIElement? = nil, timeout: TimeInterval = 6
    ) throws {
        try macRequire(texts, ids: ids, in: root, timeout: timeout).click()
        pause(0.5)
    }

    /// A text (or a control) that contains the string; scrolls the detail column when it is below the fold.
    func macRow(_ text: String, in root: XCUIElement? = nil, scrolls: Int = 3) throws -> XCUIElement {
        let root = root ?? app
        let predicate = NSPredicate(format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@", text, text)
        for attempt in 0...scrolls {
            let deadline = Date().addingTimeInterval(attempt == 0 ? 4 : 1)
            repeat {
                for query in [root.buttons, root.cells, root.staticTexts] {
                    if let match = firstHittable(query.matching(predicate), limit: 4) { return match }
                }
                let labelled = NSPredicate(format: "label CONTAINS[c] %@", text)
                if let match = firstHittable(root.descendants(matching: .any).matching(labelled), limit: 4) {
                    return match
                }
                pause(0.3)
            } while Date() < deadline
            if scrolls > 0 { scrollPage() }
        }
        throw ScreenTourError("satır bulunamadı: \(text)")
    }

    // MARK: Getting back to a known state

    /// Closes sheets, popovers and the Settings window with actions that never save anything.
    /// A step that opens a menu closes it itself (`escape()`): the menu bar's own menus are
    /// always in the tree, so an open menu cannot be told apart cheaply.
    func closeOverlays() {
        captureMainWindow()
        if let settings = settingsWindow {
            settings.buttons["_XCUI:CloseWindow"].click()
            pause(0.5)
        }
        for _ in 0..<6 {
            guard app.sheets.count > 0 || app.popovers.count > 0 else { return }
            if let discard = macFind(["At", "Değişiklikleri at"], timeout: 0) {
                discard.click()
            } else if let close = macFind(["Vazgeç", "Kapat"], in: app.sheets.firstMatch, timeout: 0) {
                close.click()
            } else {
                app.typeKey(.escape, modifierFlags: [])
            }
            pause(0.6)
        }
        if app.sheets.count > 0 || app.popovers.count > 0 {
            log("açık katman kapatılamadı; uygulama yeniden başlatılıyor")
            relaunch()
        }
    }

    /// Selects an entry of the sidebar (a root, a board or a project).
    func sidebar(_ label: String) throws {
        closeOverlays()
        let outline = mainWindow.outlines.firstMatch
        guard outline.waitForExistence(timeout: 10) else { throw ScreenTourError("kenar çubuğu yok") }
        guard let entry = macFind([label], in: outline, timeout: 4) else {
            throw ScreenTourError("kenar çubuğunda yok: \(label)")
        }
        entry.click()
        pause(0.8)
    }

    /// Picks an option of a control that is a row of tabs or a pop-up menu.
    func macChoose(_ option: String, openers: [String], ids: [String] = []) throws {
        if let direct = macFind([option], in: mainWindow, timeout: 0.5), direct.elementType != .staticText {
            direct.click()
            pause(0.5)
            if let item = firstHittable(app.menuItems.matching(ScreenTourDriver.exact(option))) { item.click() }
            pause(0.5)
            return
        }
        try macOpenMenu(openers: openers, ids: ids, expecting: [option])
        guard let item = menuItem(option) else { throw ScreenTourError("menüde yok: \(option)") }
        item.click()
        pause(0.6)
    }

    /// Opens a pop-up menu and leaves it open (for a screenshot).
    func macOpenMenu(openers: [String], ids: [String] = [], expecting items: [String]) throws {
        for opener in openers.isEmpty ? [""] : openers {
            guard let control = macFind(opener.isEmpty ? [] : [opener], ids: ids, in: mainWindow, timeout: 1) else {
                continue
            }
            control.click()
            pause(0.6)
            if items.contains(where: { menuItem($0) != nil }) { return }
            app.typeKey(.escape, modifierFlags: [])
            pause(0.3)
        }
        throw ScreenTourError("menü açılamadı: \(ids) \(openers)")
    }

    /// Waits for a sheet, whatever it shows: a sheet that comes up broken is still worth an image.
    func waitForSheet(timeout: TimeInterval = 6) throws {
        guard app.sheets.firstMatch.waitForExistence(timeout: timeout) else {
            throw ScreenTourError("sheet açılmadı")
        }
        pause(0.6)
    }

    /// Clicks an item of the menu that is open (a context menu or a pop-up).
    func chooseMenuItem(_ title: String) throws {
        let deadline = Date().addingTimeInterval(4)
        repeat {
            if let item = menuItem(title) {
                item.click()
                pause(0.6)
                return
            }
            pause(0.3)
        } while Date() < deadline
        throw ScreenTourError("menüde yok: \(title)")
    }

    /// Opens a menu of the app's menu bar and clicks one of its items.
    func menuBar(_ menu: String, item: String) throws {
        let title = app.menuBars.menuBarItems[menu]
        guard title.waitForExistence(timeout: 5) else { throw ScreenTourError("menü yok: \(menu)") }
        title.click()
        try chooseMenuItem(item)
    }

    func escape() {
        app.typeKey(.escape, modifierFlags: [])
        pause(0.6)
    }
}
