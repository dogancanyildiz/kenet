import XCTest

/// Walks the Mac app with the fictional sample vault and saves one PNG of the window per screen.
///
/// The Mac counterpart of `ScreenTourUITests`: a screen that also exists on iPhone keeps the
/// iPhone tour's number and name so the two sets line up side by side; screens only the Mac has
/// are numbered from 30. Skipped unless `JOURNAL_SCREEN_TOUR_DIR` names an output folder; run it
/// through `.github/scripts/screen-tour.sh --mac <folder>`.
///
/// Nothing of the user's is touched. The script builds the app under its own bundle identifier
/// (own UserDefaults domain), and the app is launched with a temporary home folder, so its vault
/// copy, index and caches land there. Appearance is switched with a launch argument, never in
/// System Settings.
final class ScreenTourMacUITests: XCTestCase {
    static let directoryKey = "JOURNAL_SCREEN_TOUR_DIR"
    static let treeDumpKey = "JOURNAL_SCREEN_TOUR_TREE"
    static let onlyKey = "JOURNAL_SCREEN_TOUR_ONLY"

    private var vaultURL: URL?
    private var homeURL: URL?
    private var tour: ScreenTourDriver!

    // Fixture rows the tour opens (the same ones as the iPhone tour).
    private let cardTask = "Hafta sonu dinlenme planı yap"
    private let listTask = "Haftalık sprint hedeflerini belirle"
    // Typed text avoids "i": with a Turkish keyboard layout XCUITest drops it.
    private let typedName = "Baran"
    private let typedPlace = "Kaf"
    private let pastDay = "27 Eyl"
    private let person = "Deniz Arıkan"
    private let place = "Liman Ofis"
    private let project = "mobil"
    private let numberGoal = "Su"
    private let note = "Okuma Listesi"

    // The system appearance stays as it is: the app alone is told which one to draw.
    // "NSRequiresAquaSystemAppearance" keeps the app light on a Mac that is set to dark.
    private let light =
        ScreenTourDriver.turkish + ScreenTourDriver.windowFrameArguments()
        + ["-NSRequiresAquaSystemAppearance", "YES"]
    private let dark =
        ScreenTourDriver.turkish + ScreenTourDriver.windowFrameArguments() + ["-AppleInterfaceStyle", "Dark"]

    override func setUpWithError() throws {
        let path = ProcessInfo.processInfo.environment[Self.directoryKey] ?? ""
        guard !path.isEmpty, !path.hasPrefix("$(") else {
            throw XCTSkip(
                "Ekran turu yalnız \(Self.directoryKey) verilince koşar (.github/scripts/screen-tour.sh --mac).")
        }
        continueAfterFailure = true
        vaultURL = try UITestSupport.prepareSampleVault()
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("JournalMacTourHome-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        homeURL = home
    }

    override func tearDownWithError() throws {
        if let vaultURL { try? FileManager.default.removeItem(at: vaultURL) }
        if let homeURL { try? FileManager.default.removeItem(at: homeURL) }
    }

    @MainActor
    func testScreenTour() throws {
        let environment = ProcessInfo.processInfo.environment
        let directory = URL(fileURLWithPath: environment[Self.directoryKey] ?? "", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let vault = try XCTUnwrap(vaultURL)
        let home = try XCTUnwrap(homeURL)

        tour = ScreenTourDriver(
            directory: directory, vaultURL: vault, test: self,
            dumpsTree: !(environment[Self.treeDumpKey] ?? "").isEmpty,
            launchArguments: light,
            launchEnvironment: ["CFFIXED_USER_HOME": home.path])
        tour.afterLaunch = { $0.fitMainWindow() }
        tour.captureMainWindow()
        tour.fitMainWindow()
        _ = tour.id("screen.today").waitForExistence(timeout: 30)

        // `JOURNAL_SCREEN_TOUR_ONLY=ayarlar,koyu` runs only the named parts (while working on the tour).
        let only = Set((environment[Self.onlyKey] ?? "").split(separator: ",").map(String.init))
        let parts: [(String, @MainActor () -> Void)] = [
            ("gunluk", todayAndDays), ("gorevler", tasks), ("gorev-sheet", taskSheets),
            ("varliklar", entities), ("varlik-sayfalari", entityPages), ("hedefler", goals),
            ("arama", { self.search(prefix: "13-arama") }), ("ayarlar", settings),
            ("hizli-giris", { self.quickEntry(prefix: "15-hizli-giris", withTaskMode: true) }),
            ("mac", macOnly), ("koyu", darkPass),
        ]
        for (name, run) in parts where only.isEmpty || only.contains(name) { run() }

        let fixture = UITestSupport.repositoryRoot().appendingPathComponent("Fixtures/vaults/sample")
        // The app copies the vault into its caches folder when it can (`openUITestVault`) and
        // works on the folder it was given otherwise; check the one it really used.
        let copy = home.appendingPathComponent("Library/Caches/UITestVault", isDirectory: true)
        let used = FileManager.default.fileExists(atPath: copy.path) ? copy : vault
        let changed = tour.changedVaultFiles(fixture: fixture, copy: used)
        if !changed.isEmpty { tour.skip("UYARI kasa değişti", reason: changed.joined(separator: ", ")) }
        tour.app.terminate()
        tour.writeSkipped()
    }

    // MARK: Today, days, summaries

    @MainActor private func todayAndDays() {
        tour.step("01-bugun") {
            try tour.sidebar("Bugün")
            try tour.waitFor(ids: ["screen.today"])
            tour.shot("01-bugun")
            tour.scrolledShot("01-bugun-asagi")
        }
        tour.step("03-gunluk") {
            try tour.sidebar("Günlük")
            tour.shot("03-gunluk")
        }
        tour.step("02-gun-gecmis") {
            try tour.sidebar("Günlük")
            try tour.macRow(pastDay, in: tour.mainWindow, scrolls: 0).click()
            try tour.waitFor(ids: ["screen.day"])
            tour.shot("02-gun-gecmis")
            tour.scrolledShot("02-gun-gecmis-asagi")
            tour.scrollToTop()
            try tour.macClick(["Günlük yazısını düzenle"])
            _ = try tour.macRequire(["Vazgeç", "Kapat"])
            tour.shot("04-gunluk-duzenleyici")
            try tour.macClick(["Vazgeç", "Kapat"])
        }
        tour.step("05-ozetler") {
            try tour.sidebar("Özetler")
            _ = try tour.macRequire(["Önceki dönem"])
            tour.scrollAnchor = CGVector(dx: 0.6, dy: 0.6)
            tour.shot("05-ozetler-hafta")
            try tour.macChoose("Ay", openers: ["Özet dönemi", "Dönem", "Hafta"], ids: ["summaries.period"])
            tour.shot("05-ozetler-ay")
            try tour.macClick(["Önceki dönem"])
            tour.shot("05-ozetler-ay-onceki", settle: 1.5)
            tour.scrolledShot("05-ozetler-ay-onceki-asagi")
        }
    }

    // MARK: Tasks

    private let taskViewIDs = ["tasks.menu", "tasks.section", "tasks.view", "tasks.listSection"]
    private let taskViewOpeners = [
        "Görev bölümü", "Bölüm", "Görünüm", "Yaklaşan", "Tarihsiz", "Tamamlanan", "Projeler",
    ]

    @MainActor private func openTaskList(_ section: String) throws {
        try tour.sidebar("Görevler")
        _ = try tour.macRequire(["Liste"], in: tour.mainWindow)
        if section != "Yaklaşan" { try tour.macChoose(section, openers: taskViewOpeners, ids: taskViewIDs) }
    }

    @MainActor private func tasks() {
        let lists = [
            ("Yaklaşan", "yaklasan"), ("Tarihsiz", "tarihsiz"), ("Tamamlanan", "tamamlanan"), ("Projeler", "projeler"),
        ]
        for (label, name) in lists {
            tour.step("06-gorevler-\(name)") {
                try openTaskList(label)
                tour.shot("06-gorevler-\(name)")
            }
        }
        tour.step("06-gorevler-gorunum-secici-acik") {
            try openTaskList("Yaklaşan")
            try tour.macOpenMenu(openers: taskViewOpeners, ids: taskViewIDs, expecting: ["Tarihsiz", "Tamamlanan"])
            tour.shot("06-gorevler-gorunum-secici-acik", settle: 1.2)
            tour.escape()
        }
        tour.step("06-gorevler-filtre-menu-acik") {
            try openTaskList("Yaklaşan")
            try tour.macOpenMenu(
                openers: ["Filtre", "Filtrele"], ids: ["tasks.filter", "button.filter"],
                expecting: ["Projeler", "Konumlar", "Kişiler"])
            tour.shot("06-gorevler-filtre-menu-acik", settle: 1.2)
            tour.escape()
        }
        tour.step("07-proje-sayfasi") {
            // The sidebar lists every project under "Görevler".
            try tour.sidebar(project)
            _ = try tour.macRequire(["Açık görevler"])
            tour.shot("07-proje-sayfasi")
        }
        tour.step("06-gorevler-kanban") {
            try tour.sidebar("Kanban")
            tour.scrollAnchor = CGVector(dx: 0.6, dy: 0.6)
            tour.shot("06-gorevler-kanban")
            tour.optional("06-gorevler-kanban-gruplama-acik") {
                try tour.macOpenMenu(
                    openers: ["Gruplama", "Grupla", "Durum"], ids: ["tasks.menu", "kanban.grouping"],
                    expecting: ["Proje", "Kişi"])
                tour.shot("06-gorevler-kanban-gruplama-acik", settle: 1.2)
                tour.escape()
            }
            tour.optional("06-gorevler-kanban-pano-secenekleri") {
                try tour.macOpenMenu(
                    openers: ["Pano seçenekleri"], ids: ["tasks.kanban.options", "kanban.options"],
                    expecting: ["İptal edilenleri göster"])
                tour.shot("06-gorevler-kanban-pano-secenekleri", settle: 1.2)
                tour.escape()
            }
        }
        tour.step("06-gorevler-zaman-cizelgesi") {
            try tour.sidebar("Zaman çizelgesi")
            tour.shot("06-gorevler-zaman-cizelgesi")
            tour.optional("06-gorevler-zaman-olcek-acik") {
                try tour.macOpenMenu(
                    openers: ["Ölçek", "Çeyrek"], ids: ["tasks.menu", "timeline.scale"], expecting: ["Hafta", "Ay"])
                tour.shot("06-gorevler-zaman-olcek-acik", settle: 1.2)
                tour.escape()
            }
        }
        taskDetail(name: "08-gorev-ayrintisi")
    }

    /// On Mac the detail is the third column; clicking the row selects it without toggling the box.
    @MainActor private func taskDetail(name: String) {
        tour.step(name) {
            try openTaskList("Yaklaşan")
            try tour.macRow(listTask, in: tour.mainWindow, scrolls: 0).click()
            _ = try tour.macRequire(["Kaynak güne git"])
            tour.shot(name)
        }
    }

    /// The row's context menu (secondary click) leads to its sheets without toggling the task.
    @MainActor private func taskSheets() {
        tour.step("08-gorev-kanban-karti") {
            try tour.sidebar("Kanban")
            // The card is below the fold of the first column.
            tour.scrollAnchor = CGVector(dx: 0.24, dy: 0.6)
            try tour.macRow(cardTask, in: tour.mainWindow).click()
            // On Mac a card opens the task beside the board, not in a sheet.
            _ = try tour.macRequire(["Kaynak güne git"])
            tour.shot("08-gorev-ayrintisi-kanban")
        }
        tour.step("08-gorev-satir-menusu") {
            try openTaskList("Yaklaşan")
            try tour.macRow(listTask, in: tour.mainWindow, scrolls: 0).rightClick()
            guard tour.menuItem("Tarih ver / değiştir") != nil else { throw ScreenTourError("satır menüsü açılmadı") }
            tour.shot("08-gorev-satir-menusu", settle: 1.2)
            tour.escape()
        }
        let sheets = [
            ("Tarih ver / değiştir", "08-gorev-tarih-sheet"), ("Tekrar", "08-gorev-tekrar-sheet"),
            ("Metni düzenle", "08-gorev-metin-sheet"),
        ]
        for (item, name) in sheets {
            tour.step(name) {
                try openTaskList("Yaklaşan")
                try tour.macRow(listTask, in: tour.mainWindow, scrolls: 0).rightClick()
                try tour.chooseMenuItem(item)
                try tour.waitForSheet()
                tour.shot(name)
            }
        }
    }

    // MARK: People and places

    private let kinds = ["Kişiler", "Konumlar"]
    private let orders = ["Ada göre", "Son geçişe göre"]

    @MainActor private func entities() {
        tour.step("09-kisiler-liste") {
            try tour.sidebar("Kişiler")
            tour.shot("09-kisiler-liste")
            // The kind control is a row of tabs on Mac: it has no open-menu state.
        }
        tour.step("09-konumlar-liste") {
            try tour.sidebar("Konumlar")
            tour.shot("09-konumlar-liste")
            tour.optional("09-konumlar-siralama-acik") {
                try tour.macOpenMenu(
                    openers: ["Sıralama", "Sırala"] + orders,
                    ids: ["button.entities.sort", "entities.sort", "button.sort"],
                    expecting: orders)
                tour.shot("09-konumlar-siralama-acik", settle: 1.2)
                tour.escape()
            }
        }
        tour.step("09-konumlar-suzgec-dolu") {
            try tour.sidebar("Konumlar")
            let field = try tour.field(
                ids: ["field.entities.filter", "field.entityFilter"], placeholders: ["Kişi veya konum ara"])
            tour.type(typedPlace, into: field)
            tour.shot("09-konumlar-suzgec-dolu")
            tour.erase(typedPlace.count)
        }
        tour.step("11-graph") {
            try tour.sidebar("Graph")
            _ = try tour.macRequire(["Yakınlaştır"])
            tour.shot("11-graph", settle: 3)
        }
        tour.step("11-harita") {
            try tour.sidebar("Harita")
            tour.shot("11-harita", settle: 4)
        }
    }

    @MainActor private func entityPages() {
        tour.step("10-kisi-sayfasi") {
            try openEntity(root: "Kişiler", name: person)
            tour.shot("10-kisi-sayfasi")
            tour.scrolledShot("10-kisi-sayfasi-asagi")
            tour.scrollToTop()
            try openEntityEditor()
            tour.shot("10-kisi-duzenleme-sheet")
            tour.scrollAnchor = CGVector(dx: 0.5, dy: 0.5)
            tour.scrolledShot("10-kisi-duzenleme-sheet-asagi")
            tour.scrollToTop()
            tour.optional("10-kisi-ad-degistir-sheet") {
                try tour.macClick(["Adı değiştir"], in: tour.app.sheets.firstMatch)
                tour.shot("10-kisi-ad-degistir-sheet")
            }
        }
        tour.step("10-konum-sayfasi") {
            try openEntity(root: "Konumlar", name: place)
            tour.shot("10-konum-sayfasi")
            tour.scrolledShot("10-konum-sayfasi-asagi")
            tour.scrollToTop()
            try openEntityEditor()
            tour.shot("10-konum-duzenleme-sheet")
        }
    }

    @MainActor private func openEntity(root: String, name: String) throws {
        try tour.sidebar(root)
        try tour.macRow(name, in: tour.mainWindow, scrolls: 0).click()
        _ = try tour.macRequire(["Düzenle"], ids: ["button.entity.edit"])
    }

    @MainActor private func openEntityEditor() throws {
        try tour.macClick(["Düzenle"], ids: ["button.entity.edit"])
        try tour.waitForSheet()
    }

    // MARK: Goals

    @MainActor private func goals() {
        tour.step("12-hedefler") {
            try tour.sidebar("Hedefler")
            tour.shot("12-hedefler")
        }
        tour.step("12-hedef-ayrintisi") {
            try openGoal()
            tour.shot("12-hedef-ayrintisi")
            tour.scrolledShot("12-hedef-ayrintisi-asagi")
            try tour.macRow("Hedef miktar").click()
            try tour.waitForSheet()
            tour.shot("12-hedef-alan-duzenleme-sheet")
        }
        tour.step("12-hedef-olusturma-sheet") {
            try tour.sidebar("Hedefler")
            try tour.macClick(["Yeni hedef"], ids: ["button.goal.new", "button.newGoal"])
            try tour.waitForSheet()
            tour.shot("12-hedef-olusturma-sheet")
        }
        tour.step("12-hedef-miktar-sheet") {
            // Secondary click: the row's plus button would add to today's value.
            try tour.sidebar("Bugün")
            try tour.macRow(numberGoal, in: tour.mainWindow).rightClick()
            try tour.chooseMenuItem("Miktar gir")
            try tour.waitForSheet()
            tour.shot("12-hedef-miktar-sheet")
        }
    }

    @MainActor private func openGoal() throws {
        try tour.sidebar("Hedefler")
        try tour.macRow(numberGoal, in: tour.mainWindow, scrolls: 0).click()
        _ = try tour.macRequire(["Isı haritası"])
    }

    // MARK: Search, settings, quick entry

    @MainActor private func search(prefix: String) {
        tour.step(prefix) {
            try tour.sidebar("Bugün")
            try tour.macClick(["Ara"], ids: ["button.search"], in: tour.mainWindow)
            try tour.waitForSheet()
            let field = try tour.field(ids: ["field.search"], placeholders: ["Kişi, konum veya metin ara"])
            tour.shot(prefix + "-bos")
            tour.type(typedName, into: field)
            tour.shot(prefix + "-sorgu", settle: 1.5)
            tour.erase(typedName.count)
            tour.type("Okuma", into: field)
            try tour.macRow(note, in: tour.app.sheets.firstMatch, scrolls: 0).click()
            tour.shot(prefix + "-not", settle: 1.5)
        }
    }

    @MainActor private func openSettings() throws {
        tour.closeOverlays()
        try tour.menuBar("Kenet", item: "Ayarlar…")
        tour.pause(1)
        guard tour.settingsWindow != nil else { throw ScreenTourError("Ayarlar penceresi açılmadı") }
        tour.captureTarget = { [unowned self] _ in self.tour.settingsWindow }
        tour.scrollAnchor = CGVector(dx: 0.5, dy: 0.6)
    }

    @MainActor private func settings() {
        let pages = [
            ("Gizlilik", "14-ayarlar-gizlilik"), ("Bildirimler", "14-ayarlar-bildirimler"),
            ("Takvim ve Konum", "14-ayarlar-takvim-konum"), ("Kasa", "14-ayarlar-kasa"),
            ("Tanılama", "14-ayarlar-tanilama"), ("Hızlı giriş", "30-mac-ayarlar-hizli-giris"),
        ]
        for (title, name) in pages {
            tour.step(name) {
                try openSettings()
                try tour.settingsTab(title)
                tour.shot(name)
                tour.scrolledShot(name + "-asagi")
            }
        }
        tour.step("14-ayarlar-varlik-tipleri") {
            try openSettings()
            try tour.settingsTab("Kasa")
            try tour.macRow("Varlık tipleri", in: tour.settingsWindow).click()
            _ = try tour.macRequire(["Yeni varlık tipi"])
            tour.shot("14-ayarlar-varlik-tipleri")
            try tour.macClick(["Yeni varlık tipi"])
            try tour.waitForSheet()
            tour.shot("14-ayarlar-varlik-tipi-duzenleyici")
            // The editor is a long list in a short sheet: "Alan ekle" is below the fold.
            _ = try tour.macRow("Alan ekle", in: tour.app.sheets.firstMatch)
            tour.shot("14-ayarlar-varlik-tipi-duzenleyici-asagi")
        }
        tour.closeOverlays()
    }

    /// Text is typed but never sent, and erased again.
    @MainActor private func quickEntry(prefix: String, withTaskMode: Bool) {
        tour.step(prefix) {
            try tour.sidebar("Bugün")
            let field = UITestSupport.quickEntryField(in: tour.app)
            guard field.waitForExistence(timeout: 10) else { throw ScreenTourError("hızlı giriş alanı yok") }
            field.click()
            tour.shot(prefix + "-odak", settle: 1.2)
            if withTaskMode {
                tour.app.typeText(typedName)
                tour.shot(prefix + "-yazi", settle: 1.2)
                tour.erase(typedName.count)
                tour.optional(prefix + "-gorev") {
                    // The mode buttons are smaller than their hit area and report as not hittable.
                    let mode = tour.mainWindow.buttons["Görev"]
                    guard mode.exists else { throw ScreenTourError("görev kipi düğmesi yok") }
                    mode.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
                    tour.shot(prefix + "-gorev")
                }
            }
            tour.relaunch()
        }
    }

    // MARK: Screens only the Mac has (numbered from 30)

    @MainActor private func macOnly() {
        tour.step("31-mac-notlar") {
            try tour.sidebar("Notlar")
            tour.shot("31-mac-notlar")
        }
        tour.step("32-mac-bos-ayrinti") {
            try tour.sidebar("Görevler")
            tour.shot("32-mac-gorevler-secim-yok")
            try tour.sidebar("Hedefler")
            tour.shot("32-mac-hedefler-secim-yok")
        }
        tour.step("33-mac-menu-cubugu") {
            // The journal window shows no quick entry here, so the panel's field is the only one.
            try tour.sidebar("Notlar")
            let item = tour.app.menuBars.statusItems.firstMatch
            guard item.waitForExistence(timeout: 5) else { throw ScreenTourError("menü çubuğu simgesi yok") }
            item.click()
            tour.pause(0.8)
            let menu = item.menus.firstMatch
            guard menu.exists, !menu.frame.isEmpty else { throw ScreenTourError("menü çubuğu menüsü açılmadı") }
            tour.captureTarget = { $0.menuBars.statusItems.firstMatch.menus.firstMatch }
            tour.shot("33-mac-menu-cubugu")
            tour.captureMainWindow()
            let open = menu.menuItems.matching(NSPredicate(format: "title BEGINSWITH %@", "Hızlı giriş"))
                .firstMatch
            guard open.exists else { throw ScreenTourError("menüde hızlı giriş yok") }
            open.click()
            tour.pause(1.2)
            guard tour.quickEntryPanel != nil else { throw ScreenTourError("hızlı giriş paneli açılmadı") }
            tour.captureTarget = { [unowned self] _ in self.tour.quickEntryPanel }
            tour.shot("34-mac-hizli-giris-paneli")
            tour.app.typeText(typedName)
            tour.shot("34-mac-hizli-giris-paneli-yazi", settle: 1.2)
            tour.erase(typedName.count)
            tour.escape()
            tour.captureMainWindow()
        }
    }

    // MARK: Dark appearance (selected base screens)

    @MainActor private func darkPass() {
        tour.relaunch(arguments: dark)
        tour.step("20-koyu-bugun") {
            try tour.sidebar("Bugün")
            tour.shot("20-koyu-bugun")
        }
        tour.step("20-koyu-gunluk") {
            try tour.sidebar("Günlük")
            tour.shot("20-koyu-gunluk")
            try tour.macRow(pastDay, in: tour.mainWindow, scrolls: 0).click()
            try tour.waitFor(ids: ["screen.day"])
            tour.shot("20-koyu-gun-gecmis")
        }
        tour.step("20-koyu-gorevler") {
            try openTaskList("Yaklaşan")
            tour.shot("20-koyu-gorevler")
        }
        tour.step("20-koyu-kanban") {
            try tour.sidebar("Kanban")
            tour.shot("20-koyu-kanban")
        }
        taskDetail(name: "20-koyu-gorev-ayrintisi")
        tour.step("20-koyu-kisiler") {
            try tour.sidebar("Kişiler")
            tour.shot("20-koyu-kisiler")
        }
        tour.step("20-koyu-kisi-sayfasi") {
            try openEntity(root: "Kişiler", name: person)
            tour.shot("20-koyu-kisi-sayfasi")
            try openEntityEditor()
            tour.shot("20-koyu-kisi-duzenleme-sheet")
        }
        tour.step("20-koyu-hedefler") {
            try tour.sidebar("Hedefler")
            tour.shot("20-koyu-hedefler")
        }
        tour.step("20-koyu-hedef-ayrintisi") {
            try openGoal()
            tour.shot("20-koyu-hedef-ayrintisi")
        }
        tour.step("20-koyu-hedef-olusturma-sheet") {
            try tour.sidebar("Hedefler")
            try tour.macClick(["Yeni hedef"], ids: ["button.goal.new", "button.newGoal"])
            try tour.waitForSheet()
            tour.shot("20-koyu-hedef-olusturma-sheet")
        }
        search(prefix: "20-koyu-arama")
        tour.step("20-koyu-ayarlar") {
            try openSettings()
            try tour.settingsTab("Bildirimler")
            tour.shot("20-koyu-ayarlar-bildirimler")
        }
        tour.step("20-koyu-ozetler") {
            try tour.sidebar("Özetler")
            tour.shot("20-koyu-ozetler")
        }
        tour.step("20-koyu-zaman-cizelgesi") {
            try tour.sidebar("Zaman çizelgesi")
            tour.shot("20-koyu-zaman-cizelgesi")
        }
        tour.step("20-koyu-graph") {
            try tour.sidebar("Graph")
            tour.shot("20-koyu-graph", settle: 3)
        }
        quickEntry(prefix: "20-koyu-hizli-giris", withTaskMode: false)
    }
}
