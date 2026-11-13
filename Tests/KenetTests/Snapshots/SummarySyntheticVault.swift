import Foundation
import VaultFormat

/// Deterministic fictional vault for the Summaries references: a full period of every kind.
/// Days from 2025-01-01 to 2026-10-11 with gaps, one empty week (2026-08-10…16), tasks with done
/// and due dates, daily, weekly, yearly and milestone goals, and names that first appear in
/// September and October 2026.
enum SummarySyntheticVault {
    static let first = CalendarDate("2025-01-01")!
    static let today = CalendarDate("2026-10-11")!
    static let quietWeek = CalendarDate("2026-08-10")!...CalendarDate("2026-08-16")!

    private static let people: [(String, CalendarDate)] = [
        ("Deniz Arıkan", first), ("Ece Yalın", first), ("Baran Tunç", first), ("Selin Korkmaz", first),
        ("Mert Aksu", first), ("Zeynep Erdem", first), ("Kaan Güneş", first), ("Elif Soylu", first),
        ("Onur Karaca", first), ("Melis Işık", first), ("Tuna Tekin", first), ("Irmak Uçar", first),
        ("Bora Bulut", CalendarDate("2026-03-02")!), ("Ceren Çınar", CalendarDate("2026-06-15")!),
        ("Efe Ersoy", CalendarDate("2026-09-08")!), ("Nil Akın", CalendarDate("2026-10-06")!),
    ]
    private static let places: [(String, CalendarDate)] = [
        ("Çınaraltı Kafe", first), ("Liman Ofis", first), ("Tepe Spor Salonu", first),
        ("Kıyı Kitabevi", first), ("Orman Parkı", first), ("Meydan Pazarı", first), ("Köprü Atölye", first),
        ("Ada Lokantası", first), ("Göl Kütüphanesi", CalendarDate("2026-09-21")!),
    ]
    /// Events per day by month (index 0 = January); 2026 is a little busier than 2025.
    private static let monthLoad = [3, 3, 4, 4, 5, 5, 4, 3, 5, 5, 4, 3]

    static func generate(at root: URL) throws {
        var random = Generator(seed: 20_261_011)
        try write(root, ".app/vault.json", "{ \"formatVersion\": 1 }\n")
        try write(root, "templates/person.md", "---\ntype: person\n---\n")
        try write(root, "templates/place.md", "---\ntype: place\n---\n")
        for (name, _) in people {
            try write(
                root, "people/\(name).md", "---\ntype: person\nname: \(name)\naliases: []\n---\n\nKurgusal kişi.\n")
        }
        for (name, _) in places {
            try write(
                root, "places/\(name).md", "---\ntype: place\nname: \(name)\naliases: []\n---\n\nKurgusal konum.\n")
        }
        let goals = [
            ("Kitap", "kitap", "period: day\nkind: number\ntarget: 20\nunit: sayfa\n"),
            ("Meditasyon", "meditasyon", "period: day\nkind: boolean\ntarget: 1\n"),
            ("Spor", "spor", "period: week\nkind: boolean\ntarget: 3\nplace: \"[[Tepe Spor Salonu]]\"\n"),
            ("Okunan kitap", "okunan", "period: year\nkind: number\ntarget: 24\nunit: kitap\n"),
            ("Portfolyo yayını", "portfolyo", "period: year\nkind: milestone\n"),
        ]
        for (name, key, body) in goals {
            try write(root, "goals/\(name).md", "---\ntype: goal\nname: \(name)\nkey: \(key)\n\(body)---\n")
        }

        var counter = 0
        func nextID() -> String {
            counter += 1
            var n = counter + 46_656
            let digits = Array("0123456789abcdefghijklmnopqrstuvwxyz")
            var s = ""
            for _ in 0..<6 {
                s = String(digits[n % 36]) + s
                n /= 36
            }
            return s
        }
        func weighted<T>(_ items: [(T, CalendarDate)], on day: CalendarDate) -> T {
            let open = items.filter { $0.1 <= day }
            // Earlier names come up more often, so the top five hold still for a few weeks.
            let weights = open.indices.map { 1.0 / Double($0 + 1) }
            var pick = random.unit() * weights.reduce(0, +)
            for (index, weight) in weights.enumerated() {
                pick -= weight
                if pick <= 0 { return open[index].0 }
            }
            return open[open.count - 1].0
        }
        // A newly met name is mentioned on its first day, so "ilk kez" falls where the vault says.
        let introductions = Dictionary(
            (people + places).filter { $0.1 > first }.map { ($0.1, $0.0) }, uniquingKeysWith: { a, _ in a })

        let acts = [
            "sabah koşusu", "kısa bir mola", "kitap okuma saati", "haftalık planlama", "alışveriş", "yüzme",
            "sessiz çalışma", "akşam yemeği", "uzun bir yürüyüş", "not düzenleme",
        ]
        let verbs = [
            "ile kahve içtik", "ile toplantı yaptık", "ile yürüyüşe çıktık", "ile telefonda konuştuk",
            "ile öğle yemeği yedik",
        ]
        let chores = [
            "raporu gönder", "faturaları öde", "randevu al", "sunumu bitir", "yedekleri kontrol et",
            "kitabı iade et", "aracı servise götür", "notları temize çek", "bütçeyi güncelle", "hediye al",
        ]

        var day = first
        while day <= today {
            defer { day = day.addingDays(1)! }
            if quietWeek.contains(day) { continue }
            let introduced = introductions[day]
            if introduced == nil, random.unit() < 0.13 { continue }

            var front = ["---", "type: journal", "date: \(day)"]
            var goalLines: [String] = []
            if random.unit() < 0.78 { goalLines.append("  kitap: \(5 + Int(random.unit() * 36))") }
            if random.unit() < 0.64 { goalLines.append("  meditasyon: true") }
            if random.unit() < 0.45 { goalLines.append("  spor: true") }
            if random.unit() < 0.07 { goalLines.append("  okunan: 1") }
            if day == CalendarDate("2026-09-18")! { goalLines.append("  portfolyo: true") }
            if !goalLines.isEmpty { front += ["goals:"] + goalLines }
            front.append("---")

            var lines = front + [""]
            let taskCount = Int(random.unit() * 3.4)
            if taskCount > 0 {
                lines.append("## Tasks")
                let age = today.ordinal - day.ordinal
                for _ in 0..<taskCount {
                    var text = chores[Int(random.unit() * Double(chores.count))]
                    if random.unit() < 0.3 { text = "[[\(weighted(people, on: day))]] için \(text)" }
                    var doneDay = day.addingDays(Int(random.unit() * 4))!
                    if quietWeek.contains(doneDay) { doneDay = day }
                    let doneChance = age > 45 ? 0.985 : 0.72
                    if doneDay <= today, random.unit() < doneChance {
                        lines.append("- [x] \(text) ✅ \(doneDay) ^\(nextID())")
                    } else if random.unit() < 0.55 {
                        lines.append("- [ ] \(text) 📅 \(day.addingDays(1 + Int(random.unit() * 14))!) ^\(nextID())")
                    } else {
                        lines.append("- [ ] \(text) ^\(nextID())")
                    }
                }
                lines.append("")
            }

            let load = Double(monthLoad[day.month - 1]) * (day.year == 2026 ? 1.25 : 1)
            var events = max(0, Int((load + (random.unit() * 4 - 2)).rounded()))
            if introduced == nil, random.unit() < 0.06 { events = 0 }
            if introduced != nil { events = max(events, 1) }
            if events > 0 {
                lines.append("## Events")
                var minute = 7 * 60 + Int(random.unit() * 60)
                for index in 0..<events {
                    minute += 25 + Int(random.unit() * 80)
                    if minute >= 23 * 60 { break }
                    let clock = String(format: "%02d:%02d", minute / 60, minute % 60)
                    let roll = random.unit()
                    let text: String
                    if index == 0, let introduced {
                        text =
                            people.contains(where: { $0.0 == introduced })
                            ? "[[\(introduced)]] ile tanıştık" : "[[\(introduced)]]'ne ilk kez gittik"
                    } else if roll < 0.4 {
                        text = "[[\(weighted(people, on: day))]] \(verbs[Int(random.unit() * Double(verbs.count))])"
                    } else if roll < 0.55 {
                        text =
                            "[[\(weighted(places, on: day))]]'de [[\(weighted(people, on: day))]] \(verbs[Int(random.unit() * Double(verbs.count))])"
                    } else if roll < 0.8 {
                        text = "[[\(weighted(places, on: day))]]'de \(acts[Int(random.unit() * Double(acts.count))])"
                    } else {
                        let act = acts[Int(random.unit() * Double(acts.count))]
                        text = act.prefix(1).uppercased() + act.dropFirst()
                    }
                    lines.append("- \(clock) \(text) ^\(nextID())")
                }
                lines.append("")
            }
            if random.unit() < 0.7 || events == 0 {
                lines.append("## Journal")
                lines.append("Günün sonunda kısa bir not: sakin bir gündü, yarın için küçük bir liste hazırladım.")
                lines.append("")
            }
            try write(root, "journal/\(day).md", lines.joined(separator: "\n"))
        }
    }

    private static func write(_ root: URL, _ path: String, _ text: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private struct Generator {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var mixed = state
            mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
            return mixed ^ (mixed >> 31)
        }
        /// 0 ..< 1
        mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    }
}
