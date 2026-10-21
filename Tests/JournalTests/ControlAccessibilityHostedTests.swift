#if os(macOS)
    import AppKit
    import Foundation
    import GoalTracking
    import Observation
    import SwiftUI
    import Testing
    import VaultFormat

    @testable import Journal

    /// What the shared controls and the screens built on them say and do, read from the
    /// accessibility tree of the mounted views (the window is never ordered on screen): the
    /// names VoiceOver reads, which choice is selected, which buttons take presses.
    @MainActor @Suite(.timeLimit(.minutes(1)))
    struct ControlAccessibilityHostedTests {
        private let watchdog = HostedTestWatchdog()

        // MARK: - Tabs

        /// With a prefix each tab reads "prefix, word"; the selected one says so.
        @Test func tabsReadAsPrefixAndWordAndMarkTheSelection() async throws {
            let selection = Selection(1)
            let tabs = InkTabs(
                selection: Binding(get: { selection.value }, set: { selection.value = $0 }),
                items: [InkTabItem(verbatim: "Bir", value: 1), InkTabItem(verbatim: "İki", value: 2)],
                accessibilityLabelPrefix: "Hedef adı")
            let mount = HostedLayout.Mount(tabs, size: CGSize(width: 400, height: 120))
            defer { mount.close() }
            guard await HostedControls.isAvailable(mount, until: { Self.tab("İki", mount) != nil }) else { return }
            let first = try #require(Self.tab("Bir", mount))
            let second = try #require(Self.tab("İki", mount))
            #expect(first.label.hasPrefix("Hedef adı") && second.label.hasPrefix("Hedef adı"))
            #expect(Self.isSelected(first) && !Self.isSelected(second))

            second.press()
            await mount.settle(rounds: 2)
            #expect(selection.value == 2)
            #expect(Self.tab("İki", mount).map(Self.isSelected) == true)
        }

        /// Screens whose tab words could repeat or need context name what the tabs choose.
        @Test func screenTabsCarryTheirPrefix() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let store = context.store
            let today = context.today

            let tasks = TasksModel(store: store, today: { today })
            try await Self.expectTabs(
                TasksViewTabs(tasks: tasks, current: .list), prefix: String(localized: "Görünüm"),
                word: String(localized: "Kanban"), context: context)
            try await Self.expectTabs(
                SummariesView(store: store, today: { today }), prefix: String(localized: "Dönem"),
                word: String(localized: "Hafta"), context: context)
            let kinds = EntityTypeChoices.choices(
                store.entityTypes, language: Locale.current.language.languageCode?.identifier ?? "en")
            try #require(InkTabsChrome.fits(count: kinds.count), "the sample has the two built-in kinds")
            try await Self.expectTabs(
                EntityTypePicker(store: store, selection: .constant(kinds[0].id)), prefix: String(localized: "Tür"),
                word: kinds[1].plural, context: context)
            let goal = try #require(try await store.goalDefinitions().first { $0.id == "goals/Su.md" })
            try await Self.expectTabs(
                NavigationStack {
                    GoalDefinitionForm(store: store, goal: goal, deletion: DefinitionDeletionModel())
                }, prefix: GoalEditableField.period.title, word: GoalPeriod.week.title, context: context)
            try await Self.expectTabs(
                NavigationStack {
                    GoalDefinitionForm(store: store, goal: goal, deletion: DefinitionDeletionModel())
                }, prefix: GoalEditableField.kind.title, word: GoalKind.boolean.title, context: context)
        }

        // MARK: - Labeled menu

        /// One element: the current choice as its value and the "double-tap to choose" hint. (The
        /// Mac tree does not surface a menu's own label; the visible label word sits beside it.)
        @Test func labeledMenuSpeaksValueAndHint() async throws {
            let menu = InkLabeledMenu(
                "Alan türü", selection: .constant(2),
                options: [InkMenuOption(verbatim: "Metin", value: 1), InkMenuOption(verbatim: "Tarih", value: 2)])
            let mount = HostedLayout.Mount(menu, size: CGSize(width: 400, height: 120))
            defer { mount.close() }
            guard await HostedControls.isAvailable(mount, until: { Self.menuButton(mount) != nil }) else { return }
            let node = try #require(Self.menuButton(mount))
            #expect(node.value == "Tarih")
            #expect(node.help == String(localized: "Seçmek için çift dokun"))
        }

        // MARK: - Manşet row

        /// The icon-only actions carry their name for VoiceOver and as the Mac tooltip.
        @Test func headerActionsAreNamed() async throws {
            let header = InkPageHeader(verbatim: "Gün") {
                InkHeaderAction("Görev ekle", systemImage: "plus", role: .primary, identifier: "probe.add") {}
                InkHeaderMenu("Sırala", systemImage: "arrow.up.arrow.down", identifier: "probe.sort") {
                    Button("Ada göre") {}
                }
                SearchButton()
            }
            .environment(\.openSearch, {})
            let mount = HostedLayout.Mount(header, size: CGSize(width: 500, height: 120))
            defer { mount.close() }
            guard await HostedControls.isAvailable(mount, until: { HostedControls.node("probe.add", in: mount) != nil })
            else { return }
            let add = try #require(HostedControls.node("probe.add", in: mount))
            #expect(add.label == String(localized: "Görev ekle") && add.help == String(localized: "Görev ekle"))
            // A menu's own label is not surfaced on the Mac; its tooltip names it.
            #expect(HostedControls.node("probe.sort", in: mount)?.help == String(localized: "Sırala"))
            // Mac: the window toolbar holds search; a manşet row shows no magnifier.
            #expect(!HostedControls.nodes(in: mount).contains { $0.label == String(localized: "Ara") })
        }

        /// Inside the search sheet a page's manşet keeps the magnifier: it leads back to the results.
        @Test func searchSheetPagesKeepTheMagnifier() async throws {
            let opened = ShellSheetKindHostedTests.Counter()
            let header = InkPageHeader(verbatim: "Not") { SearchButton() }
                .environment(\.isSearchSheet, true)
                .environment(\.openSearch, { opened.count += 1 })
            let mount = HostedLayout.Mount(header, size: CGSize(width: 500, height: 120))
            defer { mount.close() }
            let search = String(localized: "Ara")
            guard await HostedControls.isAvailable(mount, until: { Self.button(search, mount) != nil }) else { return }
            Self.button(search, mount)?.press()
            await mount.settle(rounds: 2)
            #expect(opened.count == 1)
        }

        /// At accessibility text sizes the icons take their own row above the manşet, in the
        /// header itself and in the page titles built on it (stack and list).
        @Test(arguments: ["header", "title", "titleRow"])
        func headerIconsMoveAboveTheHeadlineAtAccessibilitySizes(_ kind: String) async throws {
            for (size, stacked) in [(DynamicTypeSize.large, false), (.accessibility2, true)] {
                let action = InkHeaderAction("Görev ekle", systemImage: "plus", identifier: "probe.add") {}
                let header: AnyView =
                    switch kind {
                    case "title": AnyView(ScrollView { InkPageTitle(verbatim: "Gün") { action } })
                    case "titleRow": AnyView(List { InkPageTitleRow(verbatim: "Gün") { action } })
                    default: AnyView(InkPageHeader(verbatim: "Gün") { action })
                    }
                let mount = HostedLayout.Mount(header.dynamicTypeSize(size), size: CGSize(width: 600, height: 400))
                defer { mount.close() }
                guard
                    await HostedControls.isAvailable(
                        mount,
                        until: { HostedControls.node("probe.add", in: mount) != nil && Self.heading(mount) != nil })
                else { return }
                let icon = try #require(HostedControls.node("probe.add", in: mount))
                let title = try #require(Self.heading(mount))
                // Screen y grows upward: above means the icon's bottom is over the title's top.
                #expect((icon.frame.minY >= title.frame.maxY) == stacked, "\(size): \(icon.frame) / \(title.frame)")
            }
        }

        // MARK: - Filter field and buttons

        /// The clear button shows while there is text and empties the field; a form field
        /// (`showsClearButton: false`) never shows it.
        @Test func filterFieldClearButtonFollowsTheText() async throws {
            let text = Selection("Deniz")
            let binding = Binding(get: { text.value }, set: { text.value = $0 })
            let mount = HostedLayout.Mount(
                VStack {
                    InkFilterField("Ara", text: binding, identifier: "probe.search", clearIdentifier: "probe.clear")
                    InkFilterField(
                        "Ad", text: .constant("Kitap"), identifier: "probe.form", clearIdentifier: "probe.formClear",
                        showsClearButton: false)
                }, size: CGSize(width: 400, height: 200))
            defer { mount.close() }
            guard
                await HostedControls.isAvailable(mount, until: { HostedControls.node("probe.clear", in: mount) != nil })
            else { return }
            #expect(HostedControls.node("probe.clear", in: mount)?.label == String(localized: "Temizle"))
            #expect(HostedControls.node("probe.formClear", in: mount) == nil)
            HostedControls.node("probe.clear", in: mount)?.press()
            await mount.settle(rounds: 2)
            #expect(text.value.isEmpty)
            #expect(HostedControls.node("probe.clear", in: mount) == nil, "no clear button on an empty field")
        }

        /// The shared button styles keep the 44 pt target height.
        @Test func inkButtonStylesKeepTheMinimumHeight() async throws {
            let mount = HostedLayout.Mount(
                VStack(spacing: 20) {
                    Button("Uygula") {}.buttonStyle(InkPrimaryButtonStyle()).accessibilityIdentifier("probe.primary")
                    Button("Atla") {}.buttonStyle(InkTextButtonStyle()).accessibilityIdentifier("probe.text")
                    Button("Sil") {}.buttonStyle(InkDestructiveButtonStyle()).accessibilityIdentifier("probe.delete")
                }, size: CGSize(width: 300, height: 300))
            defer { mount.close() }
            let ids = ["probe.primary", "probe.text", "probe.delete"]
            guard
                await HostedControls.isAvailable(
                    mount, until: { ids.allSatisfy { HostedControls.node($0, in: mount) != nil } })
            else { return }
            for id in ids {
                let height = HostedControls.node(id, in: mount)?.frame.height ?? 0
                #expect(height >= InkButtonChrome.minimumHeight - 0.5, "\(id): \(height)")
            }
        }

        // MARK: - Today

        /// More than three carried-over tasks fold behind a row that reads its own text, keeps a
        /// 44 pt height and opens the rest when pressed.
        @Test func carriedOverDisclosureIsALabeledRowThatOpensTheRest() async throws {
            let context = try TaskTestContext()
            defer { context.clean() }
            let earlier = context.root.appendingPathComponent("journal/2026-09-28.md")
            try FileManager.default.createDirectory(
                at: earlier.deletingLastPathComponent(), withIntermediateDirectories: true)
            let tasks = (1...5).map { "- [ ] devreden \($0) 📅 2026-09-2\($0)" }
            try Data(("## Tasks\n" + tasks.joined(separator: "\n") + "\n").utf8).write(to: earlier)
            await context.start()
            let today = context.today
            let mount = HostedLayout.Mount(
                Self.environment(
                    NavigationStack { DayView(store: context.store, date: today, isToday: true) }, context),
                size: CGSize(width: 720, height: 1400))
            defer { mount.close() }
            let disclosure = String(
                localized: "\(2) devreden daha", bundle: PresentationLocalization.bundle(.current), locale: .current)
            guard await HostedControls.isAvailable(mount, until: { Self.button(disclosure, mount) != nil }) else {
                return
            }
            let row = try #require(Self.button(disclosure, mount))
            #expect(row.frame.height >= TapTarget.minimumLength - 0.5, "44 pt floor: \(row.frame)")
            #expect(Self.taskTexts(mount).count == 3)

            row.press()
            let opened = await waitUntil(timeout: .seconds(5)) {
                await mount.settle(rounds: 1)
                return Self.taskTexts(mount).count == 5
            }
            #expect(opened, "the row opens every carried-over task")
            #expect(Self.button(disclosure, mount) == nil)
        }

        /// The goal strip starts over on another day: its order is that day's (open goals first),
        /// not the order it kept on the day before.
        @Test func goalStripTakesTheNewDaysOrder() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let store = context.store
            let (first, second, expected) = try await Self.daysWithAnotherGoalOrder(store)
            let shown = Selection(first)
            let page = Self.environment(
                NavigationStack { DayPageSwitch(store: store, day: shown) }, context)
            let mount = HostedLayout.Mount(page, size: CGSize(width: 720, height: 1600))
            defer { mount.close() }
            let names = try await store.goalDefinitions().filter { $0.period == .day }.map(\.name)
            // Each goal row's name is its own button, in the strip's order.
            func order() -> [String] {
                HostedControls.nodes(in: mount).filter { $0.role == "AXButton" && names.contains($0.label) }.map(
                    \.label)
            }
            guard await HostedControls.isAvailable(mount, until: { order().count == names.count }) else { return }
            shown.value = second
            let settled = await waitUntil(timeout: .seconds(5)) {
                await mount.settle(rounds: 1)
                return order() == expected
            }
            #expect(settled, "\(second): \(order()) instead of \(expected)")
        }

        // MARK: - Onboarding and vault settings

        /// Large text keeps every part reachable (the page scrolls) and the page says where a new
        /// vault is created.
        @Test func onboardingScrollsAndSaysWhereANewVaultGoes() async throws {
            let context = try TaskTestContext()
            defer { context.clean() }
            let mount = HostedLayout.Mount(
                OnboardingView(store: context.store).dynamicTypeSize(.accessibility3),
                size: CGSize(width: 500, height: 500))
            defer { mount.close() }
            let create = String(localized: "Bu cihazda")
            guard await HostedControls.isAvailable(mount, until: { Self.button(create, mount) != nil }) else { return }
            #expect(HostedControls.nodes(in: mount).contains { $0.role == "AXScrollArea" })
            let location = String(localized: OnboardingCopy.newVaultLocation(for: .current))
            #expect(HostedControls.texts(in: mount).contains(location))
        }

        @Test func vaultSettingsOfferToRevealTheVaultInFinder() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let mount = HostedLayout.Mount(
                VaultSettingsView(store: context.store), size: CGSize(width: 600, height: 700))
            defer { mount.close() }
            let reveal = String(localized: "Finder'da göster")
            guard await HostedControls.isAvailable(mount, until: { Self.button(reveal, mount) != nil }) else { return }
            #expect(Self.button(reveal, mount)?.isEnabled == true)
        }

        // MARK: - Timeline

        /// A Mac timeline row shows the task's dates through the shared date line.
        @Test func macTimelineRowShowsTheTaskDates() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let model = TimelineModel(tasks: TasksModel(store: context.store, today: { context.today }))
            await model.load()
            let row = try #require(model.groups.flatMap(\.rows).first { $0.start != nil })
            let start = LocalDay.instant(for: try #require(row.start)).formatted(.dateTime.day().month().year())
            let mount = HostedLayout.Mount(
                TimelineDesktopView(model: model, todayRequest: UUID(), select: { _ in }, edit: { _, _ in }),
                size: CGSize(width: 1000, height: 1600))
            defer { mount.close() }
            guard
                await HostedControls.isAvailable(
                    mount, until: { HostedControls.texts(in: mount).contains(start) })
            else { return }
            #expect(HostedControls.texts(in: mount).contains(start))
        }

        // MARK: - Forms

        /// The goal form's "Kaydet" follows the draft: off while nothing changed, on after a
        /// change; while the write runs both bar words are off.
        @Test func goalFormConfirmFollowsTheDraftAndTheWrite() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let store = context.store
            let goal = try #require(try await store.goalDefinitions().first { $0.id == "goals/Su.md" })
            let mount = HostedLayout.Mount(
                Self.environment(
                    NavigationStack {
                        GoalDefinitionForm(store: store, goal: goal, deletion: DefinitionDeletionModel())
                    },
                    context), size: CGSize(width: 600, height: 900))
            defer { mount.close() }
            let week = GoalPeriod.week.title
            guard await HostedControls.isAvailable(mount, until: { Self.tab(week, mount) != nil }) else { return }
            #expect(HostedControls.node("button.goal.form.save", in: mount)?.isEnabled == false, "nothing changed")

            Self.tab(week, mount)?.press()
            let changed = await waitUntil(timeout: .seconds(5)) {
                await mount.settle(rounds: 1)
                return HostedControls.node("button.goal.form.save", in: mount)?.isEnabled == true
            }
            #expect(changed, "a changed period can be saved")

            let turn = ShellSheetKindHostedTests.HeldTurn()
            store.testingEditTurnDidArrive = { await turn.hold() }
            defer { turn.release() }
            HostedControls.node("button.goal.form.save", in: mount)?.press()
            #expect(await waitUntil { turn.isHeld })
            await mount.settle(rounds: 2)
            #expect(HostedControls.node("button.goal.form.cancel", in: mount)?.isEnabled == false)
            #expect(HostedControls.node("button.goal.form.save", in: mount)?.isEnabled == false)
            store.testingEditTurnDidArrive = nil
            turn.release()
        }

        /// An invalid amount shows the field's own error under it and keeps "Kaydet" off. Typed
        /// through the field editor, as a keyboard would.
        @Test func goalFormShowsTheFieldErrorAndKeepsSaveOff() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let store = context.store
            let goal = try #require(try await store.goalDefinitions().first { $0.id == "goals/Su.md" })
            let mount = HostedLayout.Mount(
                Self.environment(
                    NavigationStack {
                        GoalDefinitionForm(store: store, goal: goal, deletion: DefinitionDeletionModel())
                    },
                    context), size: CGSize(width: 600, height: 900))
            defer { mount.close() }
            let target = goal.target.formatted()
            guard
                await HostedControls.isAvailable(
                    mount, until: { mount.views(NSTextField.self).contains { $0.stringValue == target } })
            else { return }
            let field = try #require(mount.views(NSTextField.self).first { $0.stringValue == target })
            guard HostedFocus.isAvailable(for: field, in: mount.window) else { return }
            let editor = try #require(mount.window.firstResponder as? NSTextView)
            editor.selectAll(nil)
            editor.insertText("0", replacementRange: editor.selectedRange())
            let error = String(localized: "Hedef miktar sıfırdan büyük bir sayı olmalı.")
            let shown = await waitUntil(timeout: .seconds(5)) {
                await mount.settle(rounds: 1)
                return HostedControls.texts(in: mount).contains(error)
            }
            #expect(shown, "the amount's error is shown under the field")
            #expect(HostedControls.node("button.goal.form.save", in: mount)?.isEnabled == false)
        }

        /// Form fields of the entity type editor are labeled values: VoiceOver reads each field by
        /// its visible label (which itself is hidden from VoiceOver), and no field offers a clear
        /// button even with text in it.
        @Test func entityTypeEditorFieldsAreLabeledWithoutClearButtons() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let model = EntityTypeEditorModel(store: context.store)
            model.id = "book"
            model.folder = "books"
            model.nameTR = "Kitap"
            model.fields = [EntityTypeFieldDraft(key: "yazar", kind: .text)]
            let mount = HostedLayout.Mount(
                NavigationStack { EntityTypeEditorView(model: model) }, size: CGSize(width: 600, height: 1600))
            defer { mount.close() }
            let labels = [
                "Tip kimliği", "Klasör", "Ad — Türkçe", "Ad — İngilizce", "Çoğul ad — Türkçe",
                "Çoğul ad — İngilizce", "SF Symbol adı", "Şablon yolu (isteğe bağlı)", "Alan adı",
            ].map { String(localized: String.LocalizationValue($0)) }
            guard
                await HostedControls.isAvailable(
                    mount, until: { Self.fields(mount).count >= labels.count })
            else { return }
            let fields = Self.fields(mount)
            #expect(Set(fields.map(\.label)) == Set(labels), "\(fields.map(\.label))")
            #expect(fields.first { $0.label == labels[0] }?.value == "book")
            // A clear button inside a labeled field would read as that field's label.
            let buttons = HostedControls.nodes(in: mount).filter { $0.role == "AXButton" }
            #expect(!buttons.contains { labels.contains($0.label) || $0.label == String(localized: "Temizle") })
            let visible = HostedControls.nodes(in: mount).filter { $0.role == "AXStaticText" }.map(\.value)
            #expect(!visible.contains(labels[1]), "the visible label is not read twice")
        }

        /// The one-line editor's field is read by the words of its visible label, which VoiceOver
        /// does not read a second time.
        @Test func textEditorFieldIsReadByItsLabel() async throws {
            let mount = HostedLayout.Mount(
                NavigationStack {
                    SingleLineTextEditor(
                        text: .constant("Deniz"), placeholder: "Olay metni", canSave: true, isDisabled: false,
                        isSaving: false, errorText: nil, load: {}, save: { false })
                }, size: CGSize(width: 600, height: 500))
            defer { mount.close() }
            guard
                await HostedControls.isAvailable(
                    mount, until: { HostedControls.node("field.textEditor", in: mount) != nil })
            else { return }
            let label = String(localized: "Olay metni")
            // The Mac reads a text field's prompt as its placeholder.
            let field = try #require(HostedControls.node("field.textEditor", in: mount))
            #expect(field.object.value(forKey: "accessibilityPlaceholderValue") as? String == label)
            #expect(!HostedControls.nodes(in: mount).contains { $0.role == "AXStaticText" && $0.value == label })
        }

        // MARK: - Support

        @MainActor @Observable final class Selection<Value> {
            var value: Value
            init(_ value: Value) { self.value = value }
        }

        /// Shows the day the test picks, as a page that keeps its place when the day changes.
        private struct DayPageSwitch: View {
            let store: IndexStore
            let day: Selection<CalendarDate>
            var body: some View { DayView(store: store, date: day.value) }
        }

        private static func environment(_ view: some View, _ context: TaskTestContext) -> some View {
            let defaults = context.defaults.defaults
            return
                view
                .environment(NotificationService(center: FakeNotificationCenter(), defaults: defaults))
                .environment(CalendarService(source: QuietCalendar()))
                .environment(LocationService(source: FakeLocationSource(), defaults: defaults))
                .environment(IntentNavigation())
                .environment(\.openSearch, {})
        }

        @MainActor private final class QuietCalendar: CalendarEventSource {
            var authorization = CalendarAuthorization.denied
            var onChange: (@MainActor @Sendable () -> Void)?
            func requestFullAccess() async throws -> Bool { false }
            func events(from start: Date, to end: Date) async throws -> [CalendarEvent] { [] }
        }

        private static func expectTabs(
            _ view: some View, prefix: String, word: String, context: TaskTestContext,
            sourceLocation: SourceLocation = #_sourceLocation
        ) async throws {
            let mount = HostedLayout.Mount(environment(view, context), size: CGSize(width: 900, height: 900))
            defer { mount.close() }
            guard await HostedControls.isAvailable(mount, until: { tab(word, mount, prefix: prefix) != nil }) else {
                return
            }
            #expect(tab(word, mount, prefix: prefix) != nil, sourceLocation: sourceLocation)
        }

        /// The button that reads `word` (with any prefix in front of it).
        private static func tab(_ word: String, _ mount: HostedLayout.Mount, prefix: String? = nil) -> HostedControls
            .Node?
        {
            HostedControls.nodes(in: mount).first {
                $0.role == "AXButton" && $0.label.hasSuffix(word) && (prefix.map($0.label.hasPrefix) ?? true)
            }
        }

        private static func isSelected(_ node: HostedControls.Node) -> Bool {
            (node.object.value(forKey: "accessibilitySelected") as? Bool) == true
        }

        private static func menuButton(_ mount: HostedLayout.Mount) -> HostedControls.Node? {
            HostedControls.nodes(in: mount).first { $0.role == "AXMenuButton" && !$0.value.isEmpty }
        }

        private static func heading(_ mount: HostedLayout.Mount) -> HostedControls.Node? {
            HostedControls.nodes(in: mount).first { $0.role == "AXHeading" }
        }

        private static func button(_ label: String, _ mount: HostedLayout.Mount) -> HostedControls.Node? {
            HostedControls.nodes(in: mount).first { $0.role == "AXButton" && $0.label == label }
        }

        private static func fields(_ mount: HostedLayout.Mount) -> [HostedControls.Node] {
            HostedControls.nodes(in: mount).filter { $0.role == "AXTextField" }
        }

        private static func taskTexts(_ mount: HostedLayout.Mount) -> Set<String> {
            Set(HostedControls.texts(in: mount).filter { $0.hasPrefix("devreden ") })
        }

        /// Two sample days whose open-first goal orders differ in a way the kept order would hide;
        /// the second day's own order.
        private static func daysWithAnotherGoalOrder(_ store: IndexStore) async throws -> (
            CalendarDate, CalendarDate, [String]
        ) {
            let goals = try await store.goalDefinitions().filter { $0.period == .day }
            var previous: (CalendarDate, [String])?
            var day = try #require(CalendarDate("2026-09-01"))
            for _ in 0..<40 {
                let model = GoalDayModel(store: store, day: day)
                await model.load()
                let order = GoalStripPresentation.ordered(goals, status: model.status(for:)).map(\.name)
                if let (before, kept) = previous,
                    GoalStripPresentation.stableOrder(previous: kept, current: order) != order
                {
                    return (before, day, order)
                }
                previous = (day, order)
                day = try #require(day.addingDays(1))
            }
            Issue.record("the sample has no two days whose goal order differs")
            throw CancellationError()
        }
    }
#endif
