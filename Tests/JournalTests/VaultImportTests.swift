import Foundation
import Testing
import VaultFormat

@testable import Journal

@MainActor struct VaultImportTests {
    @Test func detectsObsidianDailyUntypedEntitiesAndSkipsHiddenContent() throws {
        let root = try sample()
        defer { try? FileManager.default.removeItem(at: root) }
        let report = try VaultImportScanner.inspect(root)
        #expect(report.markdownCount == 8)
        #expect(report.externalDays == ["2026-09-22.md", "daily/2026-09-21.md"])
        #expect(report.journalDays == ["journal/2026-09-20.md"])
        #expect(report.typed == ["person": 1, "goal": 1])
        #expect(report.candidates.map(\.path) == ["people/Deniz.md", "places/Ev.md"])
        #expect(report.skipped == ["people/Broken.md"])
        #expect(report.missingFolders == ["notes", "templates"] && report.needsSettings)
        #expect(report.foundFolders.contains(".obsidian") && report.needsPreparation)
        #expect(report.caseVariantFolders.isEmpty)
    }

    @Test func reportsJournalCaseVariantAndDoesNotTreatItAsMissing() throws {
        let root = try testDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("## Events\n- Eski\n", "Journal/2026-10-04.md", root)
        try write("---\ntype: person\nname: Selin Korkmaz\n---\n", "people/Selin.md", root)
        let report = try VaultImportScanner.inspect(root)
        #expect(report.caseVariantFolders == ["Journal"])
        #expect(!report.missingFolders.contains("journal"))
        #expect(report.journalDays.isEmpty)
        #expect(report.needsPreparation)
    }

    @Test func templatesCaseVariantDoesNotScaffoldTemplates() throws {
        let root = try testDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("# Kişi\n", "Templates/person.md", root)
        let report = try VaultImportScanner.inspect(root)
        #expect(report.caseVariantFolders == ["Templates"])
        #expect(report.missingTemplates.isEmpty)
    }

    @Test func approvedTypeInsertionPreservesCommentsCRLFBodiesAndOtherFiles() async throws {
        let root = try sample()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try bytes(root)
        let report = try VaultImportScanner.inspect(root)
        let result = await VaultImportWriter.apply(report: report, options: VaultImportOptions())
        #expect(result.failures.isEmpty && result.typed == ["people/Deniz.md", "places/Ev.md"])
        #expect(result.skipped == ["people/Broken.md"])
        let person = try Data(contentsOf: root.appendingPathComponent("people/Deniz.md"))
        #expect(
            person
                == Data(
                    "---\r\nname: Deniz Arıkan # keep\r\ncustom: [keep]\r\ntype: person\r\n---\r\nBody [[Ev]]\r\n".utf8)
        )
        let place = try Data(contentsOf: root.appendingPathComponent("places/Ev.md"))
        #expect(place == Data("---\ntype: place\n---\nNo frontmatter\n".utf8))
        for (path, data) in original where !["people/Deniz.md", "places/Ev.md"].contains(path) {
            #expect(try Data(contentsOf: root.appendingPathComponent(path)) == data)
        }
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("templates/person.md").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("journal/2026-09-21.md").path))
        let second = try VaultImportScanner.inspect(root)
        #expect(!second.needsPreparation && second.candidates.isEmpty)
    }
    @Test func uncheckedOffersAndSkipDoNotWriteAnySourceBytes() async throws {
        let root = try sample()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try bytes(root)
        let report = try VaultImportScanner.inspect(root)
        let result = await VaultImportWriter.apply(
            report: report,
            options: VaultImportOptions(folders: false, settings: false, types: false))
        #expect(result.created.isEmpty && result.typed.isEmpty && result.failures.isEmpty)
        #expect(try bytes(root) == original)
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.store.inspectSelection(root)
        let model = try #require(context.store.importModel)
        #expect(context.store.vaultURL == nil && context.store.requiresOnboarding)
        await context.store.finishImport(model)
        #expect(context.store.vaultURL == root && context.store.importModel == nil && !context.store.requiresOnboarding)
        #expect(try bytes(root) == original)
        #expect(context.store.content.days.count == 1)
    }
    @Test func existingAndChangedTypeTemplatesSettingsAndSymlinksAreNeverOverwritten() async throws {
        let root = try sample()
        defer { try? FileManager.default.removeItem(at: root) }
        let report = try VaultImportScanner.inspect(root)
        try write("---\ntype: note\n---\nExternal edit\n", "people/Deniz.md", root)
        try write("custom template\n", "templates/person.md", root)
        try write("{ \"formatVersion\": 1, \"custom\": 12 }\n", ".app/vault.json", root)
        let original = try bytes(root)
        let result = await VaultImportWriter.apply(report: report, options: VaultImportOptions())
        #expect(result.skipped.contains("people/Deniz.md"))
        for path in ["people/Deniz.md", "templates/person.md", ".app/vault.json"] {
            #expect(try Data(contentsOf: root.appendingPathComponent(path)) == original[path])
        }
        let outside = try testDirectory()
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("linked"), withDestinationURL: outside)
        #expect(throws: CocoaError.self) { try VaultImportBootstrap.directory("linked", root: root) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
        #expect(try VaultImportScanner.inspect(root).skipped.contains("linked"))
    }
    @Test func firstLaunchUsesBookmarkOrExistingDefaultWithoutCreatingUntilExplicitChoice() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        #expect(context.store.requiresOnboarding)
        await context.store.startAutomatically(environment: [:], arguments: [])
        #expect(context.store.vaultURL == nil && !FileManager.default.fileExists(atPath: context.root.path))
        await context.start()
        #expect(!context.store.requiresOnboarding && context.store.content.days.isEmpty)
        let location = VaultLocation(
            defaults: context.defaults.defaults, documentsURL: context.directory, bookmarks: pathBookmarks())
        #expect(!location.needsFirstLaunch)
        let another = try TestDefaults()
        defer { another.clean() }
        another.defaults.set(Data("/unavailable".utf8), forKey: "vaultBookmark")
        #expect(
            !VaultLocation(
                defaults: another.defaults, documentsURL: context.directory.appendingPathComponent("unused"),
                bookmarks: pathBookmarks()
            ).needsFirstLaunch)
    }
    @Test func completeFolderOpensWithoutReportAndUnsupportedSettingsStayReadOnly() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let model = VaultImportScanner.supportsSettings(at: context.root)
        #expect(model)
        await context.store.inspectSelection(context.root)
        #expect(context.store.importModel == nil)
        try write("{ \"formatVersion\": 2 }\n", ".app/vault.json", context.root)
        await context.store.inspectSelection(context.root)
        let report = try #require(context.store.importModel?.report)
        #expect(!report.canPrepare)
        let result = await VaultImportWriter.apply(report: report, options: VaultImportOptions())
        #expect(result.created.isEmpty && result.typed.isEmpty)
        let session = try #require(context.store.importModel)
        await context.store.finishImport(session)
        #expect(context.store.isVaultReadOnly && !context.store.canAddEvent)
    }
    @Test func initialIndexShowsTotalWhileBusyThenPublishesActualCounts() async throws {
        let directory = try testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let root = try sample()
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = UpdateGate()
        let store = IndexStore(
            location: VaultLocation(defaults: defaults.defaults, documentsURL: directory, bookmarks: pathBookmarks()),
            supportURL: directory.appendingPathComponent("indexes"),
            update: { index, root, rebuild, previous, skip, skipped, previousContent in
                await gate.hold()
                return try await IndexUpdate.read(
                    index: index, root: root, rebuild: rebuild, previousTypes: previous,
                    skipUnchanged: skip, previousSkipped: skipped, previousContent: previousContent)
            })
        await gate.arm()
        let operation = Task { await store.select(root) }
        try await waitForGate(gate)
        #expect(store.isProcessing && store.indexingFileCount == 8)
        await gate.release()
        await operation.value
        #expect(store.indexingFileCount == nil && store.counts.files == 8)
    }
    private func sample() throws -> URL {
        let root = try testDirectory()
        try write(
            "---\r\nname: Deniz Arıkan # keep\r\ncustom: [keep]\r\n---\r\nBody [[Ev]]\r\n", "people/Deniz.md", root)
        try write("No frontmatter\n", "places/Ev.md", root)
        try write("---\nname: [broken\n---\nBody\n", "people/Broken.md", root)
        try write("---\ntype: person\nname: Selin Korkmaz\n---\n", "people/Selin.md", root)
        try write("---\ntype: goal\nkey: spor\n---\n", "goals/Spor.md", root)
        try write("## Events\n- A note\n", "journal/2026-09-20.md", root)
        try write("Daily note\n", "daily/2026-09-21.md", root)
        try write("Root day\n", "2026-09-22.md", root)
        try write("Private settings\n", ".obsidian/config.json", root)
        try write("Ignored note\n", ".obsidian/Hidden.md", root)
        return root
    }
    private func write(_ text: String, _ path: String, _ root: URL) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
    private func bytes(_ root: URL) throws -> [String: Data] {
        let root = root.resolvingSymlinksInPath()
        let enumerator = try #require(
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]))
        var result: [String: Data] = [:]
        for case let url as URL in enumerator
        where try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            let path = url.resolvingSymlinksInPath().path
            result[String(path.dropFirst(root.path.count + 1))] = try Data(contentsOf: url)
        }
        return result
    }
}
