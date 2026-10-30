import Foundation
import Testing
import VaultFormat
import VaultIndex

@testable import VaultStore

/// The task screens' queries against the construction they replaced in the app: every task row of
/// the read model, filtered and grouped in Swift (`TasksModel`, `TaskGroups`, `KanbanModel`,
/// `TimelineModel`, `ProjectModel`, `WeeklyReviewContent`).
struct TaskViewQueryTests {
    @Test func sampleVaultMatchesSnapshotConstruction() throws {
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: Fixtures.root().appendingPathComponent("vaults/sample"))
        let oracle = try expectConstruction(
            index, days: ["2026-09-14", "2026-09-20", "2026-09-27", "2026-10-15"],
            extraScopes: [TaskScope(project: "MOBİL"), TaskScope(project: "mobil")])
        // 26 checkbox lines, two of them in `conflicts/`, which is not indexed.
        #expect(oracle.tasks.count == 24)
        #expect(try index.taskGroups(today: CalendarDate("2026-09-20")!).today.count == 1)
    }

    @Test func syntheticVaultMatchesSnapshotConstruction() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = try SyntheticVault.generate(at: root, configuration: .compact)
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let end = manifest.endDate
        let oracle = try expectConstruction(
            index, days: [end, end.addingDays(-10)!, end.addingDays(30)!].map(\.description), extraScopes: [])
        #expect(oracle.tasks.count > 20)
    }

    /// Every rule of the construction in one small vault, with the answers written out by hand.
    @Test func edgeCaseVaultAnswersByHand() throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try Self.writeEdgeCases(vault)
        try vault.index.rebuild(vaultRoot: vault.root)
        try expectConstruction(
            vault.index, days: ["2026-03-01", "2026-03-09", "2026-03-10", "2026-03-11", "2026-04-01"],
            extraScopes: [TaskScope(project: "CAFÉ"), TaskScope(project: "Cafe\u{301}")])

        let today = CalendarDate("2026-03-10")!
        let index = vault.index
        func words(_ entries: [TaskEntry]) -> [String] {
            entries.map { String($0.block.text.split(separator: " ")[0]) }
        }
        let groups = try index.taskGroups(today: today)
        #expect(words(groups.overdue) == ["geçmiş", "not"])
        #expect(words(groups.today) == ["bugün", "her"])
        #expect(words(groups.upcoming) == ["acil", "bilinmeyen", "ters", "gelecek"])
        #expect(words(groups.undated) == ["dünkü", "tarihsiz", "sürüyor", "notta", "kopya"])
        let ada = TaskScope(linkedTo: "people/Ada Test.md")
        #expect(words(try index.taskGroups(today: today, scope: ada).overdue) == ["geçmiş"])
        #expect(words(try index.taskGroups(today: today, scope: ada).today) == ["bugün"])
        let cafe = try index.taskGroups(today: today, scope: TaskScope(project: "CAFÉ"))
        #expect(words(cafe.overdue + cafe.today + cafe.upcoming) == ["geçmiş", "not", "bugün", "gelecek"])
        #expect(try index.taskGroups(today: today, scope: TaskScope(project: "yok")) == TaskGroupEntries.empty)
        let both = TaskScope(linkedTo: "people/Can Test.md", project: "café")
        #expect(words(try index.taskGroups(today: today, scope: both).overdue) == ["not"])

        #expect(
            words(try index.completedTasks(limit: 10, scope: .all)) == [
                "geç", "bugün", "dün", "sınır", "eski", "tarihsiz",
            ])
        #expect(words(try index.completedTasks(limit: 2, scope: .all)) == ["geç", "bugün"])
        #expect(try index.completedTasks(limit: 0, scope: .all).isEmpty)

        #expect(
            words(try index.dayTasks(on: today)) == [
                "geç", "tarihsiz", "geçmiş", "bugün", "bugün", "gelecek", "sürüyor", "iptal", "bilinmeyen", "acil",
                "her", "tarihsiz", "ters", "not",
            ])
        let board = try index.boardTasks(doneFrom: today.addingDays(-29)!, to: today, includeCancelled: false)
        #expect(!words(board).contains("iptal") && !words(board).contains("eski") && words(board).contains("dün"))
        // The first of the thirty days is on the board.
        #expect(words(board).contains("sınır"))
        #expect(
            words(try index.boardTasks(doneFrom: today.addingDays(-29)!, to: today, includeCancelled: true)).contains(
                "iptal"))
        let timeline = try index.timelineTasks(
            from: CalendarDate("2026-03-11")!, to: CalendarDate("2026-03-13")!, today: today)
        #expect(
            Set(words(timeline)) == [
                "ters", "gelecek", "bilinmeyen", "acil", "tarihsiz", "dünkü", "dün", "eski", "sınır", "notta", "kopya",
            ])
        #expect(words(try index.tasks(inProject: "cafe\u{301}")) == ["geçmiş", "bugün", "gelecek", "not"])
        #expect(
            words(try index.openTasks(dueBy: CalendarDate("2026-03-09")!, orWrittenFrom: CalendarDate("2026-03-09")!))
                == ["geçmiş", "not", "dünkü"])
        // Swift keys compare canonically: the decomposed spelling counts with "Café".
        #expect(try index.openTaskCounts() == ["Café": 2, "café": 1, "CAFÉ": 1])
        let owned = try #require(try index.task(id: "journal/2026-03-10.md^bugun1"))
        #expect(owned.links.map(\.resolvedFile) == ["people/Ada Test.md", "people/Can Test.md"])
        #expect(try index.task(id: "journal/2026-03-10.md#3")?.block.text.hasPrefix("geçmiş") == true)
        #expect(try index.task(id: "journal/2026-03-10.md#\(owned.block.firstLine)") == nil)
        #expect(try index.task(id: "journal/2026-03-09.md#2")?.block.text == "dünkü tarihsiz")
        // A task whose identifier an event owns is named by its line.
        #expect(try index.task(id: "notes/Plan.md#3")?.block.text.hasPrefix("kopya") == true)
        #expect(try index.task(id: "notes/Plan.md^olay1") == nil)
    }

    /// A day page keeps the open tasks written in its file whatever their due day; a closed one
    /// written there with a due day, or an open one written on another day, is not among them.
    @Test func dayTasksKeepOpenTasksWrittenThatDayWhateverTheirDueDay() throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try vault.write(
            "journal/2026-03-10.md",
            """
            ## Tasks
            - [ ] ileri açık 📅 2026-03-15
            - [/] ileri sürüyor 🛫 2026-03-11 📅 2026-03-12
            - [x] ileri bitti 📅 2026-03-15 ✅ 2026-03-11
            - [-] ileri iptal 📅 2026-03-15
            - [ ] tarihsiz açık
            - [x] tarihsiz bitti

            """)
        try vault.write("journal/2026-03-09.md", "## Tasks\n- [ ] dünden ileri 📅 2026-03-15\n")
        try vault.write("notes/Plan.md", "- [ ] notta ileri 📅 2026-03-15\n")
        try vault.index.rebuild(vaultRoot: vault.root)
        try expectConstruction(
            vault.index, days: ["2026-03-09", "2026-03-10", "2026-03-11", "2026-03-15"], extraScopes: [])
        func texts(_ day: String) throws -> [String] {
            try vault.index.dayTasks(on: CalendarDate(day)!).map(\.block.text)
        }
        #expect(try texts("2026-03-10") == ["ileri açık", "ileri sürüyor", "tarihsiz açık", "tarihsiz bitti"])
        #expect(try texts("2026-03-09") == ["dünden ileri"])
        #expect(try texts("2026-03-11") == ["ileri bitti"])
    }

    /// Edits through the store keep the incrementally maintained index answering like a rebuild.
    @Test func storeEditsMatchSnapshotConstructionAndRebuild() async throws {
        let random = CountingRandom()
        let vault = try StoreVault(random: { random.next() })
        defer { vault.remove() }
        try Self.writeEdgeCases(vault)
        try vault.index.rebuild(vaultRoot: vault.root)
        let days = ["2026-03-09", "2026-03-10", "2026-03-12"]
        func check() throws {
            try expectConstruction(vault.index, days: days, extraScopes: [TaskScope(project: "CAFÉ")])
            let rebuilt = try VaultIndex()
            try rebuilt.rebuild(vaultRoot: vault.root)
            for day in days.compactMap(CalendarDate.init) {
                #expect(try vault.index.taskGroups(today: day) == rebuilt.taskGroups(today: day))
                #expect(try vault.index.dayTasks(on: day) == rebuilt.dayTasks(on: day))
            }
            #expect(
                try vault.index.completedTasks(limit: 50, scope: .all) == rebuilt.completedTasks(limit: 50, scope: .all)
            )
        }
        let path = "journal/2026-03-10.md"
        func task(_ prefix: String) throws -> TaskLine {
            try #require(
                RawDocument(bytes: try vault.bytes(path)).bodyLines.tasks.first { $0.text.hasPrefix(prefix) })
        }
        let today = CalendarDate("2026-03-10")!

        // Completion: the task leaves the open groups and is done today.
        try await vault.store.changingStatus(of: try task("geçmiş"), at: path, to: .done, completionDate: today)
        try check()
        #expect(try vault.index.completedTasks(limit: 1, scope: .all).first?.block.text.hasPrefix("geçmiş") == true)
        // A recurring task completed: the next one is written beside it.
        try await vault.store.changingStatus(of: try task("her"), at: path, to: .done, completionDate: today)
        try check()
        #expect(try vault.index.taskGroups(today: today).upcoming.contains { $0.block.text.hasPrefix("her") })
        // Move: a new due day.
        try await vault.store.settingTaskDueDate(of: try task("ters"), at: path, to: CalendarDate("2026-03-09"))
        try check()
        #expect(try vault.index.taskGroups(today: today).overdue.contains { $0.block.text.hasPrefix("ters") })
        // Addition with every field.
        try await vault.store.addingTask(
            on: today, text: "eklendi [[Can Test]]", due: CalendarDate("2026-03-12"), start: today, priority: .high,
            project: "café")
        try check()
        #expect(try vault.index.tasks(inProject: "CAFÉ").contains { $0.block.text.hasPrefix("eklendi") })
        // A file deleted outside the app.
        try FileManager.default.removeItem(at: vault.root.appendingPathComponent("notes/Plan.md"))
        try vault.index.refresh(vaultRoot: vault.root)
        try check()
        #expect(try vault.index.taskGroups(today: today).undated.allSatisfy { $0.block.file != "notes/Plan.md" })
    }

    static func writeEdgeCases(_ vault: StoreVault) throws {
        try vault.write("people/Ada Test.md", "---\ntype: person\nname: Ada Test\n---\n")
        try vault.write("people/Can Test.md", "---\ntype: person\nname: Can Test\n---\n")
        try vault.write(
            "journal/2026-03-10.md",
            """
            ## Tasks
            - [ ] tarihsiz açık
            - [ ] geçmiş [[Ada Test]] 📅 2026-03-01 ⏫ #project/Café
            - [ ] bugün [[Ada Test]] ve [[Can Test]] 📅 2026-03-10 🔼 #project/café ^bugun1
            - [x] bugün bitti 📅 2026-03-10 ✅ 2026-03-10
            - [ ] gelecek [[Yok]] 🛫 2026-03-12 📅 2026-03-20 🔽 #project/CAFÉ
            - [/] sürüyor 🛫 2026-03-05
            - [-] iptal 📅 2026-03-10
            - [?] bilinmeyen 📅 2026-03-11
            - [ ] acil 📅 2026-03-11 ⏫
            - [ ] her hafta 🔁 every week 📅 2026-03-10
            - [x] tarihsiz bitti
            - [ ] ters 🛫 2026-03-15 📅 2026-03-12

            ## Events
            - 09:00 Olay [[Ada Test]] ^olay1
            """)
        try vault.write(
            "journal/2026-03-09.md",
            "## Tasks\r\n- [ ] dünkü tarihsiz\r\n- [x] dün bitti ✅ 2026-03-09\r\n")
        try vault.write(
            "journal/2026-03-04.md",
            "## Tasks\n- [x] eski bitti ✅ 2026-02-01\n- [x] geç bitti 📅 2026-03-02 ✅ 2026-03-10\n- [x] sınır bitti ✅ 2026-02-09\n"
        )
        try vault.write(
            "notes/Plan.md",
            "- [ ] not görevi [[Can Test]] 📅 2026-03-08 #project/Cafe\u{301}\n- [ ] notta tarihsiz\n- [ ] kopya kimlik ^olay1\n"
        )
    }

    /// Each query on each day and scope equals the construction; every task is found by its id.
    @discardableResult
    private func expectConstruction(_ index: VaultIndex, days: [String], extraScopes: [TaskScope]) throws
        -> TaskConstruction
    {
        let oracle = TaskConstruction(try index.snapshot())
        let people = Set(oracle.tasks.flatMap { $0.links.compactMap(\.resolvedFile) })
        let projects = Set(oracle.tasks.compactMap(\.block.project))
        let scopes =
            [TaskScope.all] + people.sorted().map { TaskScope(linkedTo: $0) }
            + projects.sorted().map { TaskScope(project: $0) } + extraScopes
            + people.sorted().flatMap { person in projects.sorted().map { TaskScope(linkedTo: person, project: $0) } }
        for value in days {
            let day = try #require(CalendarDate(value))
            for scope in scopes {
                #expect(try index.taskGroups(today: day, scope: scope) == oracle.groups(today: day, scope: scope))
                for limit in [1, 3, 50] {
                    #expect(try index.completedTasks(limit: limit, scope: scope) == oracle.completed(limit, scope))
                }
                for cancelled in [false, true] {
                    let first = day.addingDays(-29)!
                    #expect(
                        try index.boardTasks(doneFrom: first, to: day, includeCancelled: cancelled, scope: scope)
                            == oracle.board(first, day, cancelled, scope), "\(day) \(scope)")
                }
                let from = day.addingDays(-365)!
                let to = day.addingDays(365)!
                #expect(
                    try index.timelineTasks(from: from, to: to, today: day, scope: scope)
                        == oracle.timeline(from, to, day, scope))
                let near = day.addingDays(3)!
                #expect(
                    try index.timelineTasks(from: day, to: near, today: day, scope: scope)
                        == oracle.timeline(day, near, day, scope))
            }
            #expect(try index.dayTasks(on: day) == oracle.day(day), "\(day)")
            let monday = day.addingDays(-6)!
            #expect(try index.openTasks(dueBy: day, orWrittenFrom: monday) == oracle.week(monday, day), "\(day)")
        }
        for project in projects {
            #expect(try index.tasks(inProject: project) == oracle.project(project))
            #expect(try index.tasks(inProject: project.uppercased()) == oracle.project(project))
        }
        #expect(try index.tasks(inProject: "yok-böyle-proje").isEmpty)
        #expect(try index.openTaskCounts() == oracle.openCounts)
        for entry in oracle.tasks {
            #expect(try index.task(id: TaskConstruction.id(entry.block)) == entry)
        }
        return oracle
    }
}

extension TaskGroupEntries {
    fileprivate static let empty = TaskGroupEntries(overdue: [], today: [], upcoming: [], undated: [])
}

/// The read model's task rows and the screens' Swift filters, in Core terms. Status is read from
/// the raw checkbox (`x`/`X` done, `-` cancelled) as the app's `TaskRow` read it.
private struct TaskConstruction {
    /// Every task, by file and line: the read model's order.
    let tasks: [TaskEntry]

    init(_ snapshot: IndexSnapshot) {
        let links = Dictionary(grouping: snapshot.links, by: \.file)
        tasks = snapshot.blocks.filter { $0.kind == "task" }.sorted {
            $0.file != $1.file ? $0.file < $1.file : $0.ordinal < $1.ordinal
        }.map { block in
            TaskEntry(
                block: block,
                links: (links[block.file] ?? []).filter { $0.block == block.ordinal }.sorted { $0.ordinal < $1.ordinal }
            )
        }
    }

    static func id(_ block: IndexedBlock) -> String {
        block.file + (block.ownsIdentifier && block.identifier != nil ? "^" + block.identifier! : "#\(block.firstLine)")
    }

    private static func isDone(_ entry: TaskEntry) -> Bool { ["x", "X"].contains(entry.block.rawStatus) }
    private static func isCancelled(_ entry: TaskEntry) -> Bool { entry.block.rawStatus == "-" }
    private static func isOpen(_ entry: TaskEntry) -> Bool { !isDone(entry) && !isCancelled(entry) }
    private static func due(_ entry: TaskEntry) -> CalendarDate? { entry.block.dueDate.flatMap(CalendarDate.init) }
    private static func start(_ entry: TaskEntry) -> CalendarDate? { entry.block.startDate.flatMap(CalendarDate.init) }
    private static func done(_ entry: TaskEntry) -> CalendarDate? { entry.block.doneDate.flatMap(CalendarDate.init) }
    private static func rank(_ entry: TaskEntry) -> Int {
        switch entry.block.priority {
        case "⏫": 0
        case "🔼": 1
        case "🔽": 3
        default: 2
        }
    }

    /// `TasksModel.order`.
    private static func order(_ lhs: TaskEntry, _ rhs: TaskEntry) -> Bool {
        if due(lhs) != due(rhs) {
            guard let left = due(lhs) else { return false }
            guard let right = due(rhs) else { return true }
            return left < right
        }
        if rank(lhs) != rank(rhs) { return rank(lhs) < rank(rhs) }
        if lhs.block.file != rhs.block.file { return lhs.block.file < rhs.block.file }
        return lhs.block.firstLine < rhs.block.firstLine
    }

    private func scoped(_ scope: TaskScope) -> [TaskEntry] {
        tasks.filter { entry in
            (scope.linkedTo.map { file in entry.links.contains { $0.resolvedFile == file } } ?? true)
                && (scope.project == nil
                    || entry.block.project.map(VaultIndex.projectKey) == scope.project.map(VaultIndex.projectKey))
        }
    }

    func groups(today: CalendarDate, scope: TaskScope) -> TaskGroupEntries {
        let open = scoped(scope).filter(Self.isOpen).sorted(by: Self.order)
        return TaskGroupEntries(
            overdue: open.filter { Self.due($0).map { $0 < today } ?? false },
            today: open.filter { Self.due($0) == today },
            upcoming: open.filter { Self.due($0).map { $0 > today } ?? false },
            undated: open.filter { Self.due($0) == nil })
    }

    func completed(_ limit: Int, _ scope: TaskScope) -> [TaskEntry] {
        Array(
            scoped(scope).filter(Self.isDone).sorted {
                if Self.done($0) != Self.done($1) {
                    guard let lhs = Self.done($0) else { return false }
                    guard let rhs = Self.done($1) else { return true }
                    return lhs > rhs
                }
                if Self.rank($0) != Self.rank($1) { return Self.rank($0) < Self.rank($1) }
                if $0.block.file != $1.block.file { return $0.block.file < $1.block.file }
                return $0.block.firstLine < $1.block.firstLine
            }.prefix(limit))
    }

    /// `TaskGroups` for a day and Today's closed rows: a superset, by file and line.
    func day(_ day: CalendarDate) -> [TaskEntry] {
        tasks.filter { entry in
            (Self.isOpen(entry) && Self.due(entry).map { $0 < day } ?? false) || Self.due(entry) == day
                || ((Self.due(entry) == nil || Self.isOpen(entry)) && entry.block.file == "journal/\(day).md")
                || (Self.isDone(entry) && Self.done(entry) == day)
        }
    }

    /// `KanbanModel.eligible` before its own sort.
    func board(_ first: CalendarDate, _ last: CalendarDate, _ cancelled: Bool, _ scope: TaskScope) -> [TaskEntry] {
        scoped(scope).filter { entry in
            if Self.isCancelled(entry) { return cancelled }
            if Self.isDone(entry) { return Self.done(entry).map { $0 >= first && $0 <= last } ?? false }
            return true
        }.sorted(by: Self.order)
    }

    /// `TimelineModel.undated` and `dated` (`TimelineDates.span(on:)` clipped) before their sorts.
    func timeline(_ from: CalendarDate, _ to: CalendarDate, _ today: CalendarDate, _ scope: TaskScope) -> [TaskEntry] {
        scoped(scope).filter { entry in
            guard !Self.isCancelled(entry) else { return false }
            guard let first = Self.start(entry) ?? Self.due(entry) else { return true }
            let last = Self.due(entry) ?? max(first, today)
            return min(first, last) <= to && max(first, last) >= from
        }.sorted(by: Self.order)
    }

    func project(_ name: String) -> [TaskEntry] {
        tasks.filter { $0.block.project.map(VaultIndex.projectKey) == VaultIndex.projectKey(name) }
    }

    /// `WeeklyReviewContent`'s open tasks left from the week, before its sort.
    func week(_ first: CalendarDate, _ last: CalendarDate) -> [TaskEntry] {
        tasks.filter { entry in
            guard Self.isOpen(entry) else { return false }
            if let due = Self.due(entry) { return due <= last }
            let file = entry.block.file
            guard file.hasPrefix("journal/"), file.hasSuffix(".md"),
                let created = CalendarDate(String(file.dropFirst(8).dropLast(3)))
            else { return false }
            return created >= first && created <= last
        }.sorted(by: Self.order)
    }

    var openCounts: [String: Int] {
        Dictionary(tasks.filter(Self.isOpen).compactMap { $0.block.project }.map { ($0, 1) }, uniquingKeysWith: +)
    }
}
