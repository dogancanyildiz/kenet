#if os(macOS)
    import AppKit
    import Foundation
    import Observation
    import SwiftUI
    import Testing
    import VaultFormat

    @testable import Journal

    /// The kind of each shell sheet as the user meets it on the Mac: which words the sheet's bar
    /// shows (read-only "Kapat", editing "Vazgeç" + "Kaydet" / "Oluştur", cancel-only "Vazgeç"),
    /// whether they take presses, and what a press does. Read from the accessibility tree of the
    /// mounted sheet content; the window is never ordered on screen.
    @MainActor @Suite(.timeLimit(.minutes(1)))
    struct ShellSheetKindHostedTests {
        private let watchdog = HostedTestWatchdog()

        // MARK: - Read-only: "Kapat"

        @Test func searchIsAReadOnlySheet() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let mount = HostedLayout.Mount(
                SearchView(store: context.store).environment(\.openSearch, {}), size: CGSize(width: 700, height: 700))
            defer { mount.close() }
            guard await HostedControls.isAvailable(mount, until: { Self.has("button.search.close", mount) }) else {
                return
            }
            #expect(HostedControls.node("button.search.close", in: mount)?.label == HostedControls.word("Kapat"))
            #expect(Self.barWords(mount) == [HostedControls.word("Kapat")])
        }

        /// A note opened from search closes the whole search sheet: its "Kapat" runs the sheet's
        /// dismiss action, not the push's.
        @Test func searchNoteCloseEndsTheSheetThatHoldsIt() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let ended = Counter()
            let note = NavigationStack {
                SearchNoteView(store: context.store, file: "journal/\(context.today).md")
            }
            .inkSheetDismissAction { ended.count += 1 }
            .environment(\.openSearch, {})
            let mount = HostedLayout.Mount(note, size: CGSize(width: 700, height: 700))
            defer { mount.close() }
            guard await HostedControls.isAvailable(mount, until: { Self.has("button.search.note.close", mount) })
            else { return }
            #expect(Self.barWords(mount) == [HostedControls.word("Kapat")])
            HostedControls.node("button.search.note.close", in: mount)?.press()
            await mount.settle(rounds: 2)
            #expect(ended.count == 1)
        }

        /// Search hands its sheet's dismiss to the pages it pushes: the note's "Kapat" does not
        /// only pop back to the results (offscreen, closing the sheet itself has nothing to close).
        @Test func searchHandsItsNotesTheSheetsDismiss() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let model = SearchModel(store: context.store)
            let destination = SearchDestination.note("journal/\(context.today).md")
            model.path = [destination]
            let mount = HostedLayout.Mount(
                SearchView(store: context.store, model: model).environment(\.openSearch, {}),
                size: CGSize(width: 700, height: 700))
            defer { mount.close() }
            guard await HostedControls.isAvailable(mount, until: { Self.has("button.search.note.close", mount) })
            else { return }
            HostedControls.node("button.search.note.close", in: mount)?.press()
            await mount.settle(rounds: 4)
            #expect(model.path == [destination], "the note's Kapat popped the push instead of closing search")
        }

        // MARK: - Editing: "Vazgeç" / "Kaydet" or "Oluştur"

        @Test func textEditorIsAnEditingSaveSheet() async throws {
            let saves = Counter()
            let mount = Self.textEditor(canSave: true, isSaving: false, saves: saves)
            defer { mount.close() }
            guard await HostedControls.isAvailable(mount, until: { Self.has("button.textEditor.save", mount) })
            else { return }
            let cancel = try #require(HostedControls.node("button.textEditor.cancel", in: mount))
            let save = try #require(HostedControls.node("button.textEditor.save", in: mount))
            #expect(cancel.label == HostedControls.word("Vazgeç") && cancel.isEnabled)
            #expect(save.label == HostedControls.word("Kaydet") && save.isEnabled)
            #expect(Self.barWords(mount) == [HostedControls.word("Vazgeç"), HostedControls.word("Kaydet")])

            // The Mac bar is under the content: cancel leading, confirm trailing.
            let field = try #require(HostedControls.node("field.textEditor", in: mount))
            #expect(save.frame.maxY <= field.frame.minY, "the bar sits below the field")
            #expect(cancel.frame.maxX < save.frame.minX)
            // Assist sits below the field so chips do not cover the typed line (screen y grows up).
            let assist = try #require(HostedControls.nodes(in: mount).first { $0.value == Self.assistMark })
            #expect(assist.frame.maxY <= field.frame.minY)

            save.press()
            await mount.settle(rounds: 2)
            #expect(saves.count == 1)
        }

        @Test func textEditorConfirmFollowsCanSave() async throws {
            let mount = Self.textEditor(canSave: false, isSaving: false, saves: Counter())
            defer { mount.close() }
            guard await HostedControls.isAvailable(mount, until: { Self.has("button.textEditor.save", mount) })
            else { return }
            #expect(HostedControls.node("button.textEditor.save", in: mount)?.isEnabled == false)
            #expect(HostedControls.node("button.textEditor.cancel", in: mount)?.isEnabled == true)
        }

        /// While saving, "Vazgeç" is drawn disabled (not silently ignored) and so is the confirm word.
        @Test func textEditorWhileSavingDisablesBothWords() async throws {
            let mount = Self.textEditor(canSave: true, isSaving: true, saves: Counter())
            defer { mount.close() }
            guard await HostedControls.isAvailable(mount, until: { Self.has("button.textEditor.save", mount) })
            else { return }
            #expect(HostedControls.node("button.textEditor.cancel", in: mount)?.isEnabled == false)
            #expect(HostedControls.node("button.textEditor.save", in: mount)?.isEnabled == false)
        }

        /// The event editor is the shared one-line editor: its bar, its field and its clear
        /// button, with the mention assist under the field.
        @Test func eventTextEditorRunsOnTheSharedEditorWithMentionAssist() async throws {
            let context = try DayEditingTestContext()
            defer { context.clean() }
            await context.start()
            let row = try #require(try await context.store.computeDay(on: context.day).events.first)
            let model = EventEditorModel(store: context.store, day: context.day, row: row)
            let mount = HostedLayout.Mount(
                NavigationStack { EventTextEditor(model: model) }, size: CGSize(width: 600, height: 500))
            defer { mount.close() }
            guard
                await HostedControls.isAvailable(
                    mount, until: { Self.has("button.textEditor.save", mount) && model.target != nil })
            else { return }
            #expect(Self.barWords(mount) == [HostedControls.word("Vazgeç"), HostedControls.word("Kaydet")])
            #expect(Self.has("field.textEditor", mount))
            #expect(HostedControls.nodes(in: mount).contains { $0.label == HostedControls.word("Temizle") })

            model.text = "@De"
            let suggested = await waitUntil(timeout: .seconds(5)) {
                await mount.settle(rounds: 1)
                return HostedControls.texts(in: mount).contains { $0.contains("Deniz Arıkan") }
            }
            #expect(suggested, "the mention assist offers the person under the field")
        }

        @Test func entityTypeEditorCreatesANewTypeAndSavesAnExistingOne() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let new = HostedLayout.Mount(
                NavigationStack { EntityTypeEditorView(model: EntityTypeEditorModel(store: context.store)) },
                size: CGSize(width: 600, height: 800))
            defer { new.close() }
            guard await HostedControls.isAvailable(new, until: { Self.has("button.entityType.save", new) }) else {
                return
            }
            #expect(Self.barWords(new) == [HostedControls.word("Vazgeç"), HostedControls.word("Oluştur")])
            #expect(HostedControls.node("button.entityType.cancel", in: new)?.isEnabled == true)

            let existing = HostedLayout.Mount(
                NavigationStack {
                    EntityTypeEditorView(model: EntityTypeEditorModel(store: context.store, original: Self.book))
                }, size: CGSize(width: 600, height: 800))
            defer { existing.close() }
            guard await HostedControls.isAvailable(existing, until: { Self.has("button.entityType.save", existing) })
            else { return }
            #expect(Self.barWords(existing) == [HostedControls.word("Vazgeç"), HostedControls.word("Kaydet")])
        }

        /// "Vazgeç" and the confirm word are drawn disabled while the type is written.
        @Test func entityTypeEditorLocksTheBarWhileSaving() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let model = Self.validNewType(store: context.store)
            let mount = HostedLayout.Mount(
                NavigationStack { EntityTypeEditorView(model: model, onSaved: { _ in }) },
                size: CGSize(width: 600, height: 800))
            defer { mount.close() }
            guard await HostedControls.isAvailable(mount, until: { Self.has("button.entityType.save", mount) }) else {
                return
            }
            try #require(HostedControls.node("button.entityType.save", in: mount)?.isEnabled == true)
            let turn = HeldTurn()
            context.store.testingEditTurnDidArrive = { await turn.hold() }
            defer { turn.release() }
            HostedControls.node("button.entityType.save", in: mount)?.press()
            #expect(await waitUntil { turn.isHeld && model.isSaving })
            await mount.settle(rounds: 2)
            #expect(HostedControls.node("button.entityType.cancel", in: mount)?.isEnabled == false)
            #expect(HostedControls.node("button.entityType.save", in: mount)?.isEnabled == false)
            context.store.testingEditTurnDidArrive = nil
            turn.release()
            #expect(await waitUntil { !model.isSaving })
        }

        /// Mac sheet chrome: a body that cannot collapse to its title bar, no sans window title
        /// over the serif manşet, and bar words with the 44 pt target height.
        @Test func macSheetChromeKeepsItsSizeAndOnlyTheManşetTitle() async throws {
            // The smallest size the chrome accepts, and the size it asks for.
            let host = NSHostingController(rootView: Color.clear.inkSheet("Düzenle", onConfirm: {}))
            let smallest = host.sizeThatFits(in: .zero)
            #expect(smallest.width >= InkSheetChrome.macMinWidth && smallest.height >= InkSheetChrome.macMinHeight)
            let ideal = NSHostingView(rootView: Color.clear.inkSheet("Düzenle", onConfirm: {})).fittingSize
            #expect(ideal.height >= InkSheetChrome.macIdealHeight, "\(ideal)")

            let mount = HostedLayout.Mount(
                NavigationStack {
                    Text(verbatim: "Gövde").inkSheet("Düzenle", cancelIdentifier: "probe.cancel", onConfirm: {})
                },
                size: CGSize(width: 600, height: 500))
            defer { mount.close() }
            guard await HostedControls.isAvailable(mount, until: { Self.has("probe.cancel", mount) }) else { return }
            #expect(mount.window.title.trimmingCharacters(in: .whitespaces).isEmpty, "title: \(mount.window.title)")
            #expect(
                (HostedControls.node("probe.cancel", in: mount)?.frame.height ?? 0) >= InkButtonChrome.minimumHeight
                    - 0.5)
        }

        /// "Vazgeç" closes a draft that has not changed, and asks (stays open) once it has: the
        /// editor is pushed here, so its `dismiss` pops the push, which the test can see.
        @Test func entityTypeEditorKeepsAChangedDraftOnCancel() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            for changed in [false, true] {
                let model = EntityTypeEditorModel(store: context.store)
                let stack = PushStack()
                let mount = HostedLayout.Mount(
                    PushedTypeEditor(stack: stack, model: model), size: CGSize(width: 600, height: 800))
                defer { mount.close() }
                guard await HostedControls.isAvailable(mount, until: { Self.has("button.entityType.cancel", mount) })
                else { return }
                if changed {
                    model.nameTR = "Albüm"
                    await mount.settle(rounds: 2)
                }
                HostedControls.node("button.entityType.cancel", in: mount)?.press()
                let closed = await waitUntil(timeout: .seconds(changed ? 1 : 5)) {
                    await mount.settle(rounds: 1)
                    return stack.path.isEmpty
                }
                #expect(closed == !changed, changed ? "a changed draft closed without asking" : "a clean draft stayed")
            }
        }

        // MARK: - Cancel-only: vault preparation

        /// While the vault is being written (here: the store indexes a new event), "Vazgeç" and the
        /// page actions are off, and come back once the write is over.
        @Test func vaultPreparationLocksThePageWhileTheVaultIsWritten() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let store = context.store
            let model = try await VaultImportModel(root: context.root)
            let mount = HostedLayout.Mount(
                NavigationStack { VaultImportView(store: store, model: model) }, size: CGSize(width: 700, height: 1400))
            defer { mount.close() }
            let skip = HostedControls.word("Atla")
            func enabled(_ identifier: String) -> Bool? { HostedControls.node(identifier, in: mount)?.isEnabled }
            func skipEnabled() -> Bool? {
                HostedControls.nodes(in: mount).first { $0.role == "AXButton" && $0.label == skip }?.isEnabled
            }
            guard
                await HostedControls.isAvailable(
                    mount, until: { Self.has("button.vaultImport.apply", mount) && skipEnabled() != nil })
            else { return }
            #expect(enabled("button.vaultImport.cancel") == true && skipEnabled() == true)

            let turn = HeldTurn()
            store.testingRecognitionReloadDidLoad = { await turn.hold() }
            defer { turn.release() }
            let write = await startedTask { await store.addEvent(on: context.today, text: "Yazılırken", time: nil) }
            #expect(await waitUntil { turn.isHeld && store.isProcessing })
            await mount.settle(rounds: 2)
            #expect(enabled("button.vaultImport.cancel") == false, "Vazgeç while the vault is written")
            #expect(enabled("button.vaultImport.apply") == false)
            #expect(skipEnabled() == false, "Atla while the vault is written")

            store.testingRecognitionReloadDidLoad = nil
            turn.release()
            #expect(await write.value)
            let unlocked = await waitUntil(timeout: .seconds(5)) {
                await mount.settle(rounds: 1)
                return enabled("button.vaultImport.cancel") == true && skipEnabled() == true
            }
            #expect(unlocked)
        }

        /// The bar holds "Vazgeç" alone; "Uygula" is a button in the page. Once the result is in,
        /// the bar is empty and the result sits directly under the manşet, above the folder report.
        @Test func vaultPreparationIsACancelOnlySheetWithTheResultUnderTheHeadline() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let model = try await VaultImportModel(root: context.root)
            let mount = HostedLayout.Mount(
                NavigationStack { VaultImportView(store: context.store, model: model) },
                size: CGSize(width: 700, height: 900))
            defer { mount.close() }
            guard await HostedControls.isAvailable(mount, until: { Self.has("button.vaultImport.apply", mount) })
            else { return }
            #expect(Self.barWords(mount) == [HostedControls.word("Vazgeç")])
            #expect(HostedControls.node("button.vaultImport.cancel", in: mount)?.isEnabled == true)
            let apply = try #require(HostedControls.node("button.vaultImport.apply", in: mount))
            #expect(apply.label == HostedControls.word("Uygula") && apply.isEnabled == model.report.canPrepare)
            try #require(model.report.canPrepare, "the sample vault can be prepared")

            apply.press()
            #expect(await waitUntil { model.result != nil })
            let ready = await waitUntil(timeout: .seconds(5)) {
                await mount.settle(rounds: 1)
                return Self.barWords(mount).isEmpty && Self.labels(mount).contains(Self.resultTitle)
            }
            #expect(ready, "with the result in, the bar is empty and the result is listed")
            // Screen y grows upward: the higher row has the larger y.
            let title = try #require(Self.top(of: HostedControls.word("Kasa hazırlığı"), mount))
            let result = try #require(Self.top(of: Self.resultTitle, mount))
            let report = try #require(Self.top(of: HostedControls.word("Klasör raporu"), mount))
            #expect(title > result && result > report)
        }

        /// A folder that cannot be prepared keeps "Uygula" off through the same decision.
        @Test func vaultPreparationApplyIsOffWhenTheFolderCannotBePrepared() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            // A folder written by a vault format this app does not know.
            let folder = context.directory.appendingPathComponent("Newer")
            let version = folder.appendingPathComponent(".app/vault.json")
            try FileManager.default.createDirectory(
                at: version.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(#"{ "formatVersion": 999 }"#.utf8).write(to: version)
            let model = try await VaultImportModel(root: folder)
            try #require(!model.report.canPrepare)
            let mount = HostedLayout.Mount(
                NavigationStack { VaultImportView(store: context.store, model: model) },
                size: CGSize(width: 700, height: 900))
            defer { mount.close() }
            guard await HostedControls.isAvailable(mount, until: { Self.has("button.vaultImport.apply", mount) })
            else { return }
            #expect(HostedControls.node("button.vaultImport.apply", in: mount)?.isEnabled == false)
        }

        // MARK: - Support

        @MainActor final class Counter { var count = 0 }

        @MainActor @Observable final class PushStack { var path: [Int] = [1] }

        /// The editor as a pushed page, so that its `dismiss` has something to close.
        private struct PushedTypeEditor: View {
            @Bindable var stack: PushStack
            let model: EntityTypeEditorModel
            var body: some View {
                NavigationStack(path: $stack.path) {
                    Text(verbatim: "root")
                        .navigationDestination(for: Int.self) { _ in EntityTypeEditorView(model: model) }
                }
            }
        }

        /// Holds a write at its turn until released.
        @MainActor final class HeldTurn {
            private var waiter: CheckedContinuation<Void, Never>?
            private(set) var isHeld = false
            private var released = false

            func hold() async {
                guard !released else { return }
                isHeld = true
                await withCheckedContinuation { waiter = $0 }
            }

            func release() {
                released = true
                waiter?.resume()
                waiter = nil
            }
        }

        private static let assistMark = "assist-under-the-field"
        private static var resultTitle: String { HostedControls.word("Hazırlama sonucu") }

        private static let book = EntityTypeDefinition(
            id: "book", folder: "books", name: .init(tr: "Kitap", en: "Book"),
            plural: .init(tr: "Kitaplar", en: "Books"), icon: "book",
            fields: [EntityTypeField(key: "yazar", kind: .text)], template: nil)

        private static func validNewType(store: IndexStore) -> EntityTypeEditorModel {
            let model = EntityTypeEditorModel(store: store)
            model.id = "album"
            model.folder = "albums"
            model.nameTR = "Albüm"
            model.nameEN = "Album"
            model.pluralTR = "Albümler"
            model.pluralEN = "Albums"
            model.icon = "opticaldisc"
            return model
        }

        private static func textEditor(canSave: Bool, isSaving: Bool, saves: Counter) -> HostedLayout.Mount {
            let view = NavigationStack {
                SingleLineTextEditor(
                    text: .constant("Deniz ile sahilde yürüyüş"), placeholder: "Olay metni", canSave: canSave,
                    isDisabled: false, isSaving: isSaving, errorText: nil, load: {},
                    save: {
                        saves.count += 1
                        return false
                    },
                    assist: { Text(verbatim: assistMark) })
            }
            return HostedLayout.Mount(view, size: CGSize(width: 600, height: 500))
        }

        private static func has(_ identifier: String, _ mount: HostedLayout.Mount) -> Bool {
            HostedControls.node(identifier, in: mount) != nil
        }

        /// Top edge of the first node labelled `label`, in screen coordinates.
        private static func top(of label: String, _ mount: HostedLayout.Mount) -> CGFloat? {
            HostedControls.nodes(in: mount).first { $0.label == label }?.frame.maxY
        }

        private static func labels(_ mount: HostedLayout.Mount) -> [String] {
            HostedControls.nodes(in: mount).map(\.label).filter { !$0.isEmpty }
        }

        /// The sheet words on buttons, in tree order (leading to trailing in the bar).
        private static func barWords(_ mount: HostedLayout.Mount) -> [String] {
            let words = Set(["Vazgeç", "Kaydet", "Oluştur", "Kapat"].map(HostedControls.word))
            return HostedControls.nodes(in: mount)
                .filter { $0.role == "AXButton" && words.contains($0.label) }
                .sorted { $0.frame.minX < $1.frame.minX }
                .map(\.label)
        }
    }
#endif
