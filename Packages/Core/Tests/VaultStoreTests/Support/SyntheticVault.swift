import Foundation
import VaultFormat

/// Deterministic fictional vault for scale budgets. Lives only under Tests; never under Fixtures/.
enum SyntheticVault {
    struct Configuration: Sendable {
        var days: Int
        var eventsPerDay: Int
        var peopleCount: Int
        var placesCount: Int
        var notesCount: Int
        var seed: UInt64
        /// Inclusive end date of the generated journal range.
        var endDate: CalendarDate
        /// When set, this person is linked on a subset of journal days (rename / link-count scenarios).
        var linkedPerson: String?
        /// Link `linkedPerson` on every Nth day (1 = every day). Five-year runs use ~100 inbound links.
        var linkedPersonInterval: Int

        static let compact = Configuration(
            days: 21, eventsPerDay: 4, peopleCount: 24, placesCount: 12, notesCount: 8,
            seed: 20_261_005, endDate: CalendarDate("2026-10-05")!, linkedPerson: "Zora Example",
            linkedPersonInterval: 1)

        static let fiveYears = Configuration(
            days: 365 * 5, eventsPerDay: 6, peopleCount: 210, placesCount: 80, notesCount: 150,
            seed: 20_261_005, endDate: CalendarDate("2026-10-05")!, linkedPerson: "Zora Example",
            linkedPersonInterval: 18)
    }

    struct Manifest: Sendable {
        var markdownFileCount: Int
        var people: [String]
        var places: [String]
        var endDate: CalendarDate
        var linkedPersonPath: String?
    }

    @discardableResult
    static func generate(at root: URL, configuration: Configuration) throws -> Manifest {
        var random = SeededRNG(seed: configuration.seed)
        var people = uniqueNames(
            count: configuration.peopleCount, first: firstNames, second: lastNames, using: &random)
        if let linked = configuration.linkedPerson, !people.contains(linked) {
            people.insert(linked, at: 0)
            if people.count > configuration.peopleCount { people.removeLast() }
        }
        let places = uniqueNames(
            count: configuration.placesCount, first: placeA, second: placeB, using: &random)

        try write(root, ".app/vault.json", "{ \"formatVersion\": 1 }\n")
        try write(root, "templates/person.md", "---\ntype: person\nTanışma:\n---\n")
        try write(root, "templates/place.md", "---\ntype: place\nAdres:\n---\n")

        var markdownCount = 0
        for (index, name) in people.enumerated() {
            let alias = index.isMultiple(of: 3) ? name.split(separator: " ").first.map(String.init) ?? "" : ""
            try write(
                root, "people/\(name).md",
                """
                ---
                type: person
                name: \(name)
                aliases: [\(alias)]
                tanışma: Kurgusal grup \(index % 17)
                ---

                Kurgusal kişi notu \(index).

                """)
            markdownCount += 1
        }
        for (index, name) in places.enumerated() {
            var extra = ""
            if index.isMultiple(of: 2) {
                extra = String(
                    format: "coordinates: [%.4f, %.4f]\nradius: %d\n", 10 + Double(index) * 0.011,
                    20 + Double(index) * 0.013, 80 + (index % 5) * 20)
            }
            try write(
                root, "places/\(name).md",
                """
                ---
                type: place
                name: \(name)
                aliases: []
                \(extra)---

                Kurgusal konum notu \(index).

                """)
            markdownCount += 1
        }

        let goals: [(String, String, String, String, String, String?, String?)] = [
            ("Spor", "spor", "week", "boolean", "3", nil, places.first),
            ("Kitap", "kitap", "day", "number", "20", "sayfa", nil),
            ("Su", "su", "day", "number", "8", "bardak", nil),
            ("Meditasyon", "meditasyon", "day", "boolean", "1", nil, nil),
            ("Yürüyüş", "yuruyus", "day", "number", "6000", "adım", nil),
            ("Yazı", "yazi", "week", "boolean", "4", nil, places.count > 2 ? places[2] : nil),
        ]
        for (name, key, period, kind, target, unit, place) in goals {
            var text =
                "---\ntype: goal\nname: \(name)\nkey: \(key)\nperiod: \(period)\nkind: \(kind)\ntarget: \(target)\n"
            if let unit { text += "unit: \(unit)\n" }
            if let place { text += "place: \"[[\(place)]]\"\n" }
            try write(root, "goals/\(name).md", text + "---\n")
            markdownCount += 1
        }

        var blockCounter = 0
        func nextID() -> String {
            blockCounter += 1
            var n = blockCounter
            let digits = Array("0123456789abcdefghijklmnopqrstuvwxyz")
            var s = ""
            for _ in 0..<6 {
                s = String(digits[n % 36]) + s
                n /= 36
            }
            return s
        }

        for index in 0..<configuration.notesCount {
            let body = (0..<4).map { _ in
                let words = (0..<8).map { _ in words[Int(random.next() % UInt64(words.count))] }.joined(
                    separator: " ")
                return
                    "\(words) [[\(people[Int(random.next() % UInt64(people.count))])]] \(acts[Int(random.next() % UInt64(acts.count))])."
            }.joined(separator: "\n")
            let tasks = (0..<2).map { j in
                "- [ ] Not görevi \(index)-\(j) #project/\(projects[Int(random.next() % UInt64(projects.count))]) ^\(nextID())"
            }.joined(separator: "\n")
            try write(root, String(format: "notes/Not %04d.md", index), "# Not \(index)\n\n\(body)\n\n\(tasks)\n")
            markdownCount += 1
        }

        guard let start = configuration.endDate.addingDays(-(configuration.days - 1)) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let linked = configuration.linkedPerson
        for offset in 0..<configuration.days {
            guard let day = start.addingDays(offset) else { continue }
            let iso = day.description
            var lines = ["---", "type: journal", "date: \(iso)", "goals:"]
            if random.next() % 100 < 45 { lines.append("  spor: true") }
            lines.append("  kitap: \(random.next() % 41)")
            lines.append("  su: \(2 + random.next() % 9)")
            if random.next() % 100 < 60 { lines.append("  meditasyon: true") }
            lines.append("  yuruyus: \(1500 + random.next() % 10_501)")
            if random.next() % 100 < 50 { lines.append("  yazi: true") }
            lines += ["---", "", "## Tasks"]
            let taskCount = 1 + Int(random.next() % 4)
            for _ in 0..<taskCount {
                var text = tasks[Int(random.next() % UInt64(tasks.count))]
                if random.next() % 100 < 40 {
                    text = "[[\(people[Int(random.next() % UInt64(people.count))])]] için \(text)"
                }
                var fields = ""
                if random.next() % 100 < 60 {
                    let due = day.addingDays(Int(1 + random.next() % 21))!
                    fields += " 📅 \(due.description)"
                }
                if random.next() % 100 < 30 {
                    fields += " #project/\(projects[Int(random.next() % UInt64(projects.count))])"
                }
                lines.append("- [ ] \(text)\(fields) ^\(nextID())")
            }
            lines += ["", "## Events"]
            var minute = 7 * 60 + Int(random.next() % 50)
            let interval = max(1, configuration.linkedPersonInterval)
            let includeLinked = linked != nil && offset.isMultiple(of: interval)
            if includeLinked, let linked {
                let clock = String(format: "%02d:%02d", minute / 60, minute % 60)
                lines.append("- \(clock) [[\(linked)]] ile kurgusal görüşme ^\(nextID())")
                minute += 30
            }
            for _ in 0..<configuration.eventsPerDay {
                minute += Int(20 + random.next() % 76)
                if minute >= 24 * 60 { break }
                let roll = random.next() % 100
                let person = people[Int(random.next() % UInt64(people.count))]
                let place = places[Int(random.next() % UInt64(places.count))]
                let verb = verbs[Int(random.next() % UInt64(verbs.count))]
                let act = acts[Int(random.next() % UInt64(acts.count))]
                let text: String
                if roll < 45 {
                    var event = "[[\(person)]] \(verb)"
                    if random.next() % 100 < 35 { event = "[[\(place)]]'de \(event)" }
                    text = event
                } else if roll < 75 {
                    text = "[[\(place)]]'de \(act)"
                } else {
                    text = act.capitalized
                }
                let clock = String(format: "%02d:%02d", minute / 60, minute % 60)
                lines.append("- \(clock) \(text) ^\(nextID())")
            }
            lines += ["", "## Journal"]
            let wordCount = 35 + Int(random.next() % 36)
            var journal = (0..<wordCount).map { _ in words[Int(random.next() % UInt64(words.count))] }
                .joined(separator: " ")
            if includeLinked, let linked { journal += " [[\(linked)]] de yanımdaydı." }
            lines.append(journal.prefix(1).uppercased() + journal.dropFirst())
            lines.append("")
            try write(root, "journal/\(iso).md", lines.joined(separator: "\n"))
            markdownCount += 1
        }

        return Manifest(
            markdownFileCount: markdownCount, people: people, places: places,
            endDate: configuration.endDate,
            linkedPersonPath: linked.map { "people/\($0).md" })
    }

    private static func write(_ root: URL, _ path: String, _ text: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private static func uniqueNames(
        count: Int, first: [String], second: [String], using random: inout SeededRNG
    ) -> [String] {
        var names: [String] = []
        var seen = Set<String>()
        while names.count < count {
            var name =
                first[Int(random.next() % UInt64(first.count))] + " "
                + second[Int(random.next() % UInt64(second.count))]
            if seen.contains(name) {
                name +=
                    " " + second[Int(random.next() % UInt64(second.count))]
                if seen.contains(name) { continue }
            }
            seen.insert(name)
            names.append(name)
        }
        return names
    }

    private static let firstNames = [
        "Deniz", "Ece", "Baran", "Selin", "Mert", "Arda", "Zeynep", "Kaan", "Elif", "Emre", "Derya", "Onur",
        "Melis", "Tuna", "Irmak", "Bora", "Ceren", "Efe", "Nil", "Ozan", "Pelin", "Sarp", "Yaren", "Tolga",
        "Lale", "Umut", "Gizem", "Kerem", "Sena", "Volkan",
    ]
    private static let lastNames = [
        "Arıkan", "Yalın", "Tunç", "Korkmaz", "Aksu", "Erdem", "Güneş", "Soylu", "Karaca", "Işık", "Tekin",
        "Uçar", "Bulut", "Çınar", "Demirtaş", "Ersoy", "Akın", "Balcı", "Coşkun", "Doğru",
    ]
    private static let placeA = [
        "Çınaraltı", "Liman", "Tepe", "Kıyı", "Orman", "Meydan", "Köprü", "Bahçe", "Yokuş", "Deniz",
        "Göl", "Çarşı", "İskele", "Vadi", "Kule", "Ada", "Pınar", "Sahil", "Çayır", "Kavak",
    ]
    private static let placeB = [
        "Kafe", "Ofis", "Spor Salonu", "Kitabevi", "Parkı", "Lokantası", "Atölye", "Kütüphanesi", "Pazarı",
        "Stüdyo",
    ]
    private static let projects = [
        "portfolyo", "ev-tasinma", "kitap", "saglik", "bahce", "yazilim", "seyahat", "finans", "atolye",
        "kurs",
    ]
    private static let verbs = [
        "ile kahve içtik", "ile toplantı yaptık", "ile yürüyüşe çıktık", "ile telefonda konuştuk",
        "ile öğle yemeği yedik", "ile proje planını gözden geçirdik",
    ]
    private static let acts = [
        "sabah koşusu", "kısa bir mola", "kitap okuma saati", "haftalık planlama", "alışveriş", "yüzme",
        "sessiz çalışma", "akşam yemeği", "uzun bir yürüyüş", "not düzenleme",
    ]
    private static let tasks = [
        "raporu gönder", "faturaları öde", "randevu al", "sunumu bitir", "yedekleri kontrol et",
        "kitabı iade et", "aracı servise götür", "notları temize çek", "bütçeyi güncelle", "hediye al",
    ]
    private static let words: [String] = {
        let text = """
            bugün sabah erken kalkıp günün planını yaptım sonra uzun süredir ertelediğim işleri sırayla \
            bitirmeye çalıştım hava güzeldi biraz yürüdüm akşam üzeri kısa bir mola verip notlarımı toparladım \
            günün sonunda kendimi daha dingin hissettim yarın için küçük bir liste hazırladım
            """
        return text.split(separator: " ").map(String.init)
    }()
}

/// SplitMix64 — same family as VaultFormatTests.SeededGenerator, kept local so this target stays free of that suite.
private struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
