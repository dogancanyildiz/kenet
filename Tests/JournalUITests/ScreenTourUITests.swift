import XCTest

/// Walks the app with the fictional sample vault and saves one PNG per screen.
///
/// Skipped unless `JOURNAL_SCREEN_TOUR_DIR` names an output folder, so the regular
/// `-only-testing:JournalUITests` run does not pay for it. Run it through
/// `.github/scripts/screen-tour.sh <folder>`; the folder must stay outside the repository.
///
/// Navigation goes by `accessibilityIdentifier` first and by Turkish label second, and each
/// "pick one" control is tried both as tabs and as a menu, so the tour survives control
/// restyling. A screen that cannot be reached is listed in `atlananlar.txt`, never a failure.
final class ScreenTourUITests: XCTestCase {
    static let directoryKey = "JOURNAL_SCREEN_TOUR_DIR"
    static let treeDumpKey = "JOURNAL_SCREEN_TOUR_TREE"

    private var vaultURL: URL?
    private var tour: ScreenTourDriver!

    // Fixture rows the tour opens. Tasks carry no link, so a touch cannot follow one.
    private let cardTask = "Hafta sonu dinlenme planı yap"
    private let pastDay = "27 Eyl"
    private let person = "Deniz Arıkan"
    private let place = "Liman Ofis"
    private let project = "mobil"
    private let numberGoal = "Su"
    private let note = "Okuma Listesi"

    override func setUpWithError() throws {
        let path = ProcessInfo.processInfo.environment[Self.directoryKey] ?? ""
        guard !path.isEmpty, !path.hasPrefix("$(") else {
            throw XCTSkip("Ekran turu yalnız \(Self.directoryKey) verilince koşar (.github/scripts/screen-tour.sh).")
        }
        continueAfterFailure = true
        vaultURL = try UITestSupport.prepareSampleVault()
    }

    override func tearDownWithError() throws {
        if let vaultURL { try? FileManager.default.removeItem(at: vaultURL) }
    }

    @MainActor
    func testScreenTour() throws {
        let environment = ProcessInfo.processInfo.environment
        let directory = URL(fileURLWithPath: environment[Self.directoryKey] ?? "", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let vault = try XCTUnwrap(vaultURL)
        XCUIDevice.shared.appearance = .light
        defer { XCUIDevice.shared.appearance = .light }

        tour = ScreenTourDriver(
            directory: directory, vaultURL: vault, test: self,
            dumpsTree: !(environment[Self.treeDumpKey] ?? "").isEmpty)
        _ = tour.id("screen.today").waitForExistence(timeout: 30)

        todayAndDays()
        tasks()
        taskSheets()
        entities()
        entityPages()
        goals()
        search(prefix: "13-arama")
        settings()
        quickEntry(prefix: "15-hizli-giris", withTaskMode: true)
        darkPass()

        let fixture = UITestSupport.repositoryRoot().appendingPathComponent("Fixtures/vaults/sample")
        let changed = tour.changedVaultFiles(fixture: fixture)
        if !changed.isEmpty {
            tour.skip("UYARI kasa değişti", reason: changed.joined(separator: ", "))
        }
        tour.writeSkipped()
    }

    // MARK: Roots

    @MainActor private func openToday() throws { try tour.home("tab.today", marker: "screen.today", title: nil) }
    @MainActor private func openDays() throws { try tour.home("tab.days", marker: "screen.days", title: "Günlük") }
    @MainActor private func openTasks() throws {
        try tour.home("tab.tasks", marker: "screen.tasks", title: "Görevler")
    }
    @MainActor private func openEntities() throws {
        try tour.home("tab.entities", marker: "screen.entities", title: "Kişiler ve Konumlar")
    }
    @MainActor private func openGoals() throws {
        try tour.home("tab.goals", marker: nil, title: "Hedefler")
    }

    // MARK: "Pick one" controls

    private let taskViews = ["Yaklaşan", "Tarihsiz", "Tamamlanan", "Projeler", "Kanban", "Zaman çizelgesi", "Liste"]
    private let taskViewIDs = ["tasks.section", "tasks.view", "tasks.listSection"]
    private let taskViewLabels = ["Görev bölümü", "Bölüm", "Görünüm"]
    private let kinds = ["Kişiler", "Konumlar"]
    private let kindIDs = ["entities.kind", "entities.type"]
    private let kindLabels = ["Varlık türü", "Tür"]
    private let orders = ["Ada göre", "Son geçişe göre"]
    private let orderIDs = ["entities.sort", "entities.order", "button.sort"]
    private let orderLabels = ["Sıralama", "Sırala"]

    @MainActor private func openTasks(_ view: String) throws {
        try openTasks()
        try tour.choose(
            view, among: taskViews, listTab: "Liste", openerIDs: taskViewIDs, openerLabels: taskViewLabels)
    }

    @MainActor private func openEntities(_ kind: String) throws {
        try openEntities()
        try tour.choose(kind, among: kinds, openerIDs: kindIDs, openerLabels: kindLabels)
    }

    // MARK: Today, days, summaries

    @MainActor private func todayAndDays() {
        tour.step("01-bugun") {
            try openToday()
            tour.shot("01-bugun")
            tour.scrolledShot("01-bugun-asagi")
        }
        tour.step("03-gunluk") {
            try openDays()
            tour.shot("03-gunluk")
            tour.scrolledShot("03-gunluk-asagi")
        }
        tour.step("02-gun-gecmis") {
            try openDays()
            try tour.row(pastDay).tap()
            try tour.waitFor(ids: ["screen.day"])
            tour.shot("02-gun-gecmis")
            tour.scrolledShot("02-gun-gecmis-asagi")
            try tour.reach(labels: ["Günlük yazısını düzenle"]).tap()
            try tour.waitFor(labels: ["Vazgeç", "Kapat"])
            tour.shot("04-gunluk-duzenleyici")
            try tour.tap(labels: ["Vazgeç", "Kapat"])
        }
        tour.step("05-ozetler") {
            try openDays()
            try tour.tap(ids: ["button.summaries"], labels: ["Özetler"])
            try tour.waitFor(labels: ["Önceki dönem"])
            tour.shot("05-ozetler-hafta")
            try tour.choose(
                "Ay", among: ["Hafta", "Ay"], openerIDs: ["summaries.period"],
                openerLabels: ["Özet dönemi", "Dönem"])
            tour.shot("05-ozetler-ay")
            try tour.tap(labels: ["Önceki dönem"])
            tour.shot("05-ozetler-ay-onceki", settle: 1.5)
            tour.scrolledShot("05-ozetler-ay-onceki-asagi")
        }
    }

    // MARK: Tasks

    @MainActor private func tasks() {
        let lists = [
            ("Yaklaşan", "yaklasan"), ("Tarihsiz", "tarihsiz"), ("Tamamlanan", "tamamlanan"), ("Projeler", "projeler"),
        ]
        for (label, name) in lists {
            tour.step("06-gorevler-\(name)") {
                try openTasks(label)
                tour.shot("06-gorevler-\(name)")
                if name == "yaklasan" { tour.scrolledShot("06-gorevler-yaklasan-asagi") }
            }
        }
        tour.step("06-gorevler-gorunum-secici-acik") {
            try openTasks("Yaklaşan")
            try tour.openChooser(options: taskViews, openerIDs: taskViewIDs, openerLabels: taskViewLabels)
            tour.shot("06-gorevler-gorunum-secici-acik", settle: 1.2)
            tour.closeMenu(items: taskViews)
        }
        tour.step("06-gorevler-filtre-menu-acik") {
            try openTasks("Yaklaşan")
            try tour.openMenu(
                ids: ["tasks.filter", "button.filter"], labels: ["Filtre", "Filtrele"],
                expecting: ["Projeler", "Konumlar"])
            tour.shot("06-gorevler-filtre-menu-acik", settle: 1.2)
            tour.closeMenu(items: ["Projeler", "Konumlar", "Kişiler"])
        }
        tour.step("07-proje-sayfasi") {
            try openTasks("Projeler")
            try tour.row(project).tap()
            try tour.waitFor(labels: ["Açık görevler"])
            tour.shot("07-proje-sayfasi")
        }
        tour.step("06-gorevler-kanban") {
            try openTasks("Kanban")
            tour.shot("06-gorevler-kanban")
            tour.optional("06-gorevler-kanban-gruplama-acik") {
                try tour.openChooser(
                    options: ["Durum", "Proje", "Kişi"], openerIDs: ["kanban.grouping"],
                    openerLabels: ["Gruplama", "Grupla"])
                tour.shot("06-gorevler-kanban-gruplama-acik", settle: 1.2)
                tour.closeMenu(items: ["Durum", "Proje", "Kişi"])
            }
            tour.optional("06-gorevler-kanban-pano-secenekleri") {
                try tour.openMenu(
                    ids: ["kanban.options"], labels: ["Pano seçenekleri"], expecting: ["İptal edilenleri göster"])
                tour.shot("06-gorevler-kanban-pano-secenekleri", settle: 1.2)
                tour.closeMenu(items: ["İptal edilenleri göster"])
            }
        }
        tour.step("06-gorevler-zaman-cizelgesi") {
            try openTasks("Zaman çizelgesi")
            tour.shot("06-gorevler-zaman-cizelgesi")
            tour.optional("06-gorevler-zaman-olcek-acik") {
                try tour.openChooser(
                    options: ["Hafta", "Ay", "Çeyrek"], openerIDs: ["timeline.scale"], openerLabels: ["Ölçek"])
                tour.shot("06-gorevler-zaman-olcek-acik", settle: 1.2)
                tour.closeMenu(items: ["Hafta", "Ay", "Çeyrek"])
            }
        }
        taskDetail(name: "08-gorev-ayrintisi", expanded: true)
    }

    /// Detail opens from a Kanban card: a touch on a list row would complete the task.
    @MainActor private func taskDetail(name: String, expanded: Bool) {
        tour.step(name) {
            try openTasks("Kanban")
            try tour.row(cardTask).tap()
            try tour.waitFor(labels: ["Kaynak güne git"])
            tour.shot(name)
            if expanded { tour.scrolledShot(name + "-buyuk") }
            try tour.tap(labels: ["Kapat"])
        }
    }

    /// The row's context menu (long press) is the only way to its sheets that does not toggle it.
    @MainActor private func taskSheets() {
        tour.step("08-gorev-satir-menusu") {
            try openTasks("Yaklaşan")
            try tour.row(cardTask).press(forDuration: 1.3)
            try tour.waitFor(labels: ["Tarih ver / değiştir"])
            tour.shot("08-gorev-satir-menusu", settle: 1.2)
            tour.closeMenu(items: ["Tarih ver / değiştir", "Metni düzenle", "Sil"])
        }
        let sheets = [
            ("Tarih ver / değiştir", "08-gorev-tarih-sheet"), ("Tekrar", "08-gorev-tekrar-sheet"),
            ("Metni düzenle", "08-gorev-metin-sheet"),
        ]
        for (item, name) in sheets {
            tour.step(name) {
                try openTasks("Yaklaşan")
                try tour.row(cardTask).press(forDuration: 1.3)
                try tour.tap(labels: [item])
                try tour.waitFor(labels: ["Vazgeç", "Kapat"])
                tour.shot(name)
                try tour.tap(labels: ["Vazgeç", "Kapat"])
            }
        }
    }

    // MARK: People and places

    @MainActor private func entities() {
        tour.step("09-kisiler-liste") {
            try openEntities("Kişiler")
            tour.shot("09-kisiler-liste")
            tour.optional("09-kisiler-tur-secici-acik") {
                try tour.openChooser(options: kinds, openerIDs: kindIDs, openerLabels: kindLabels)
                tour.shot("09-kisiler-tur-secici-acik", settle: 1.2)
                tour.closeMenu(items: kinds)
            }
        }
        tour.step("09-konumlar-liste") {
            try openEntities("Konumlar")
            tour.shot("09-konumlar-liste")
            tour.optional("09-konumlar-siralama-acik") {
                try tour.openChooser(options: orders, openerIDs: orderIDs, openerLabels: orderLabels)
                tour.shot("09-konumlar-siralama-acik", settle: 1.2)
                tour.closeMenu(items: orders)
            }
        }
        tour.step("09-konumlar-suzgec-dolu") {
            try openEntities("Konumlar")
            let field = try tour.field(
                ids: ["field.entityFilter", "field.entitySearch"], placeholders: ["Kişi veya konum ara"])
            tour.type("Li", into: field)
            tour.shot("09-konumlar-suzgec-dolu")
            tour.erase(2)
            // The software keyboard may cover the tab bar; a fresh launch is the safe way out.
            tour.relaunch()
        }
        tour.step("11-graph") {
            try openEntities()
            try tour.tap(ids: ["button.graph"], labels: ["Graph"])
            try tour.waitFor(labels: ["Yakınlaştır"])
            tour.shot("11-graph", settle: 3)
        }
        tour.step("11-harita") {
            try openEntities()
            try tour.tap(ids: ["button.map"], labels: ["Harita"])
            try tour.waitFor(labels: ["Beni göster"])
            tour.shot("11-harita", settle: 3)
        }
    }

    @MainActor private func entityPages() {
        tour.step("10-kisi-sayfasi") {
            try openEntity(kind: "Kişiler", name: person)
            tour.shot("10-kisi-sayfasi")
            tour.scrolledShot("10-kisi-sayfasi-asagi")
            tour.scrollToTop()
            try openEntityEditor()
            tour.shot("10-kisi-duzenleme-sheet")
            try tour.tap(labels: ["Adı değiştir"])
            try tour.waitFor(labels: ["Vazgeç"])
            tour.shot("10-kisi-ad-degistir-sheet")
            try tour.tap(labels: ["Vazgeç"])
            tour.pause(0.6)
            tour.scrolledShot("10-kisi-duzenleme-sheet-asagi")
        }
        tour.step("10-konum-sayfasi") {
            try openEntity(kind: "Konumlar", name: place)
            tour.shot("10-konum-sayfasi")
            tour.scrolledShot("10-konum-sayfasi-asagi")
            tour.scrollToTop()
            try openEntityEditor()
            tour.shot("10-konum-duzenleme-sheet")
        }
    }

    @MainActor private func openEntity(kind: String, name: String) throws {
        try openEntities(kind)
        try tour.row(name).tap()
        try tour.waitFor(ids: ["button.entity.edit"], labels: ["Düzenle"])
    }

    @MainActor private func openEntityEditor() throws {
        try tour.tap(ids: ["button.entity.edit"], labels: ["Düzenle"])
        try tour.waitFor(labels: ["Adı değiştir"])
    }

    // MARK: Goals

    @MainActor private func goals() {
        tour.step("12-hedefler") {
            try openGoals()
            tour.shot("12-hedefler")
        }
        tour.step("12-hedef-ayrintisi") {
            try openGoal()
            tour.shot("12-hedef-ayrintisi")
            tour.scrolledShot("12-hedef-ayrintisi-asagi")
            try tour.reach(containing: "Hedef miktar").tap()
            try tour.waitFor(labels: ["Kaydet"])
            tour.shot("12-hedef-alan-duzenleme-sheet")
            try tour.tap(labels: ["Vazgeç", "Kapat"])
        }
        tour.step("12-hedef-olusturma-sheet") {
            try openGoals()
            try tour.tap(ids: ["button.goal.new", "button.newGoal"], labels: ["Yeni hedef"])
            try tour.waitFor(labels: ["Oluştur"])
            tour.shot("12-hedef-olusturma-sheet")
            try tour.tap(labels: ["Vazgeç", "Kapat"])
        }
        tour.step("12-hedef-miktar-sheet") {
            // Long press: the row's plus button would add to today's value.
            try openToday()
            try tour.require(labels: [numberGoal]).press(forDuration: 1.3)
            try tour.tap(labels: ["Miktar gir"])
            try tour.waitFor(labels: ["Kaydet"])
            tour.shot("12-hedef-miktar-sheet")
            try tour.tap(labels: ["Vazgeç", "Kapat"])
        }
    }

    @MainActor private func openGoal() throws {
        try openGoals()
        try tour.require(labels: [numberGoal]).tap()
        try tour.waitFor(labels: ["Isı haritası"])
    }

    // MARK: Search, settings, quick entry

    @MainActor private func search(prefix: String) {
        tour.step(prefix) {
            try openToday()
            try tour.tap(ids: ["button.search"], labels: ["Ara"])
            let field = try tour.field(ids: ["field.search"], placeholders: ["Kişi, konum veya metin ara"])
            tour.shot(prefix + "-bos")
            tour.type("Deniz", into: field)
            tour.shot(prefix + "-sorgu", settle: 1.5)
            tour.erase(5)
            tour.type("Okuma", into: field)
            try tour.row(note, swipes: 0).tap()
            tour.shot(prefix + "-not", settle: 1.5)
            tour.relaunch()
        }
    }

    @MainActor private func openSettings() throws {
        try openToday()
        try tour.tap(ids: ["button.settings"], labels: ["Ayarlar"])
        try tour.waitFor(ids: ["screen.settings"], labels: ["Gizlilik"])
    }

    @MainActor private func settings() {
        tour.step("14-ayarlar") {
            try openSettings()
            tour.shot("14-ayarlar")
        }
        let pages = [
            ("Gizlilik", "gizlilik"), ("Bildirimler", "bildirimler"), ("Takvim ve Konum", "takvim-konum"),
            ("Kasa", "kasa"), ("Tanılama", "tanilama"),
        ]
        for (title, name) in pages {
            tour.step("14-ayarlar-\(name)") {
                try openSettings()
                try tour.tap(labels: [title])
                tour.pause(0.6)
                tour.shot("14-ayarlar-\(name)")
                tour.scrolledShot("14-ayarlar-\(name)-asagi")
            }
        }
        tour.step("14-ayarlar-gizlilik-bildirim-icerigi") {
            try openSettings()
            try tour.tap(labels: ["Gizlilik"])
            try tour.reach(labels: ["Bildirimlerde içeriği gizle"]).tap()
            tour.shot("14-ayarlar-gizlilik-bildirim-icerigi")
        }
        tour.step("14-ayarlar-varlik-tipleri") {
            try openSettings()
            try tour.tap(labels: ["Kasa"])
            try tour.reach(labels: ["Varlık tipleri"]).tap()
            try tour.waitFor(labels: ["Yeni varlık tipi"])
            tour.shot("14-ayarlar-varlik-tipleri")
            try tour.tap(labels: ["Yeni varlık tipi"])
            try tour.waitFor(labels: ["Alan ekle"])
            tour.shot("14-ayarlar-varlik-tipi-duzenleyici")
        }
    }

    /// Text is typed but never sent; the app is relaunched so nothing stays in the field.
    @MainActor private func quickEntry(prefix: String, withTaskMode: Bool) {
        tour.step(prefix) {
            try openToday()
            let field = UITestSupport.quickEntryField(in: tour.app)
            guard field.waitForExistence(timeout: 10) else { throw ScreenTourError("hızlı giriş alanı yok") }
            field.tap()
            tour.shot(prefix + "-odak", settle: 1.2)
            if withTaskMode {
                tour.app.typeText("Deniz")
                tour.shot(prefix + "-yazi", settle: 1.2)
                tour.erase(5)
                tour.optional(prefix + "-gorev") {
                    try tour.tap(ids: ["quickEntry.mode.task"], labels: ["Görev"])
                    tour.shot(prefix + "-gorev")
                }
            }
            tour.relaunch()
        }
    }

    // MARK: Dark appearance (selected base screens)

    @MainActor private func darkPass() {
        XCUIDevice.shared.appearance = .dark
        tour.pause(1.5)
        tour.step("20-koyu-bugun") {
            try openToday()
            tour.shot("20-koyu-bugun")
        }
        tour.step("20-koyu-gunluk") {
            try openDays()
            tour.shot("20-koyu-gunluk")
        }
        tour.step("20-koyu-gorevler") {
            try openTasks("Yaklaşan")
            tour.shot("20-koyu-gorevler")
        }
        tour.step("20-koyu-kanban") {
            try openTasks("Kanban")
            tour.shot("20-koyu-kanban")
        }
        taskDetail(name: "20-koyu-gorev-ayrintisi", expanded: false)
        tour.step("20-koyu-kisiler") {
            try openEntities("Kişiler")
            tour.shot("20-koyu-kisiler")
        }
        tour.step("20-koyu-kisi-sayfasi") {
            try openEntity(kind: "Kişiler", name: person)
            tour.shot("20-koyu-kisi-sayfasi")
            try openEntityEditor()
            tour.shot("20-koyu-kisi-duzenleme-sheet")
        }
        tour.step("20-koyu-hedefler") {
            try openGoals()
            tour.shot("20-koyu-hedefler")
        }
        tour.step("20-koyu-hedef-ayrintisi") {
            try openGoal()
            tour.shot("20-koyu-hedef-ayrintisi")
        }
        tour.step("20-koyu-hedef-olusturma-sheet") {
            try openGoals()
            try tour.tap(ids: ["button.goal.new", "button.newGoal"], labels: ["Yeni hedef"])
            try tour.waitFor(labels: ["Oluştur"])
            tour.shot("20-koyu-hedef-olusturma-sheet")
        }
        search(prefix: "20-koyu-arama")
        tour.step("20-koyu-ayarlar") {
            try openSettings()
            tour.shot("20-koyu-ayarlar")
            try tour.tap(labels: ["Bildirimler"])
            tour.shot("20-koyu-ayarlar-bildirimler")
        }
        quickEntry(prefix: "20-koyu-hizli-giris", withTaskMode: false)
        XCUIDevice.shared.appearance = .light
    }
}
