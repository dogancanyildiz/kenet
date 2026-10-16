#if os(iOS)
    import SwiftUI
    import Testing
    import UIKit
    import VaultFormat

    @testable import Journal

    /// The split shell at iPad widths (`docs/screens.md`, "Bölünmüş kabuk"): the sample vault in a
    /// window whose size classes are overridden, read through the UIKit tree the shell builds.
    /// The canvases are plain window sizes; the iPad snapshot canvas belongs to the image suites.
    @MainActor @Suite(.serialized, .timeLimit(.minutes(3)))
    struct SplitShellHostedTests {
        typealias Shell = AdaptiveShellHostedTests.Shell

        struct Canvas: Sendable, CustomTestStringConvertible {
            let width: CGFloat
            let height: CGFloat
            let window: String
            var size: CGSize { CGSize(width: width, height: height) }
            var testDescription: String { window }
        }

        // MARK: - Columns

        /// From 1000 pt the sidebar, the list and the detail stand side by side; the system would
        /// otherwise put an upright 13" iPad's detail in front and lay the sidebar over it.
        ///
        /// What these hosted cases do not show: in a test-host window iPadOS puts the three
        /// columns side by side at 1032 pt even without the shell's `.all` (a 1200 pt threshold
        /// failed only the sidebar width line here). The `.all` request itself is held by the
        /// unit table (`AdaptiveShellTests.columnVisibilityFollowsTheWidth`); the real upright
        /// 13" opening needs a look on the device or the simulator's own window.
        @Test(arguments: [
            Canvas(width: 1032, height: 1376, window: "13\" upright"),
            Canvas(width: 1376, height: 1032, window: "13\" landscape"),
            Canvas(width: 1210, height: 834, window: "11\" landscape"),
        ])
        func wideWindowDrawsThreeColumns(_ canvas: Canvas) async throws {
            // From an upright 11" (two columns), so every case is a change the shell answers.
            try await Shell.hosted(size: CGSize(width: 834, height: 1210), horizontal: .regular, vertical: .regular) {
                shell in
                shell.resize(to: canvas.size)
                await shell.settle(rounds: 20)
                let split = try #require(shell.split, "no split view under the shell")
                #expect(!split.isCollapsed)
                #expect(split.style == .tripleColumn, "sidebar, list column and detail")
                #expect(
                    split.displayMode == .twoBesideSecondary,
                    "the three columns are not side by side: mode \(split.displayMode.rawValue)")
                let sidebar = try #require(shell.onScreen(.primary), "sidebar off screen")
                let list = try #require(shell.onScreen(.supplementary), "list column off screen")
                let page = try #require(shell.onScreen(.secondary), "detail off screen")
                #expect(sidebar.maxX <= page.minX, "sidebar \(sidebar) laid over the page \(page)")
                #expect(list.maxX <= page.minX + 1, "list \(list) beside the page \(page)")
                // iPadOS floats the sidebar over the list column's leading edge.
                #expect(list.maxX - sidebar.maxX >= 300, "the list keeps its width beside the sidebar: \(list)")
                #expect(abs(sidebar.width - ShellStyle.threeColumnSidebarWidth.ideal) <= 1, "sidebar width \(sidebar)")
                #expect(page.width >= 440, "the page keeps a readable column: \(page)")
            }
        }

        /// Accessibility text: the wider sidebar still stands beside list and page, also on an
        /// upright 13" iPad (iPadOS would lay a sidebar that leaves too little detail over the list).
        @Test(arguments: [
            Canvas(width: 1032, height: 1376, window: "13\" upright"),
            Canvas(width: 1376, height: 1032, window: "13\" landscape"),
        ])
        func accessibilityTextKeepsTheColumnsReadable(_ canvas: Canvas) async throws {
            try await Shell.hosted(size: CGSize(width: 834, height: 1210), horizontal: .regular, vertical: .regular) {
                shell in
                shell.host.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
                await shell.settle()
                shell.resize(to: canvas.size)
                await shell.settle(rounds: 20)
                let split = try #require(shell.split)
                #expect(split.displayMode == .twoBesideSecondary, "mode \(split.displayMode.rawValue)")
                let sidebar = try #require(shell.onScreen(.primary))
                // iPadOS may give up a few points of the ideal on an upright 13".
                let width = ShellStyle.accessibilitySidebarWidth
                #expect(sidebar.width > width.min && sidebar.width <= width.ideal + 1, "\(sidebar)")
            }
        }

        /// A cold start in an upright 13" window, no resize before: the first frames are drawn
        /// for 1032 pt. Like the cases above it cannot tell the `.all` request from the system's
        /// own choice; it holds the opening sidebar width (three-column tier before the first
        /// measurement) and that nothing from an earlier, narrower layout is needed.
        @Test func coldStartUprightWideWindowDrawsThreeColumns() async throws {
            try await Shell.hosted(size: CGSize(width: 1032, height: 1376), horizontal: .regular, vertical: .regular) {
                shell in
                let split = try #require(shell.split)
                #expect(split.displayMode == .twoBesideSecondary, "mode \(split.displayMode.rawValue)")
                let sidebar = try #require(shell.onScreen(.primary), "sidebar off screen")
                let page = try #require(shell.onScreen(.secondary), "detail off screen")
                #expect(shell.onScreen(.supplementary) != nil, "list column off screen")
                #expect(sidebar.maxX <= page.minX, "sidebar \(sidebar) laid over the page \(page)")
                let ideal = ShellStyle.threeColumnSidebarWidth.ideal
                #expect(abs(sidebar.width - ideal) <= 1, "sidebar width \(sidebar)")
            }
        }

        /// Three columns, the sidebar put away with its button: a resize within the tier (a
        /// Split View drag, a turn of the 13") leaves it away; leaving the tier and coming back
        /// shows every column again.
        @Test func hiddenSidebarStaysHiddenWithinTheTier() async throws {
            try await Shell.hosted(size: CGSize(width: 1376, height: 1032), horizontal: .regular, vertical: .regular) {
                shell in
                let split = try #require(shell.split)
                #expect(shell.onScreen(.primary) != nil, "three columns to start with")
                split.hide(.primary)
                await shell.settle(rounds: 20)
                #expect(shell.onScreen(.primary) == nil, "the button did not put the sidebar away")

                shell.resize(to: CGSize(width: 1210, height: 834))
                await shell.settle(rounds: 20)
                #expect(shell.onScreen(.primary) == nil, "a resize within the tier brought the sidebar back")
                shell.resize(to: CGSize(width: 1032, height: 1376))
                await shell.settle(rounds: 20)
                #expect(shell.onScreen(.primary) == nil, "a turn within the tier brought the sidebar back")

                shell.resize(to: CGSize(width: 834, height: 1210))
                await shell.settle(rounds: 20)
                shell.resize(to: CGSize(width: 1376, height: 1032))
                await shell.settle(rounds: 20)
                #expect(
                    split.displayMode == .twoBesideSecondary, "entering the tier: mode \(split.displayMode.rawValue)")
                #expect(shell.onScreen(.primary) != nil, "entering the tier shows every column")
            }
        }

        /// Three columns, Kanban open, the sidebar put away with its button; then a section in
        /// the column layout (a notification or Siri opening Bugün; the "Liste" tab is the same
        /// switch). The list column comes back with the detail (before the fix the three-column
        /// split read the board's "detail only" and showed the page alone).
        @Test func boardWithHiddenSidebarOpensTheColumnsWithTheirList() async throws {
            try await Shell.hosted(size: CGSize(width: 1376, height: 1032), horizontal: .regular, vertical: .regular) {
                shell in
                try shell.chooseSidebarRow(3)  // Kanban
                await shell.settle(rounds: 20)
                try #require(shell.split).hide(.primary)
                await shell.settle(rounds: 20)
                #expect(shell.onScreen(.primary) == nil, "the button did not put the sidebar away")

                shell.navigation.section = .today
                await shell.settle(rounds: 20)
                let split = try #require(shell.split)
                #expect(
                    shell.onScreen(.supplementary) != nil, "the list column is gone: mode \(split.displayMode.rawValue)"
                )
                #expect(shell.onScreen(.secondary) != nil, "detail off screen")
                // The shell asks for list and detail (`.doubleColumn`); in the test host iPadOS
                // 26 still shows the sidebar beside them at 1376 pt (mode 4). Not measured here.
            }
        }

        /// An iPad 11" upright (834 pt) is the iPhone Duo's two-column tier.
        @Test func narrowIPadKeepsTheTwoColumnTier() async throws {
            try await Shell.hosted(size: CGSize(width: 834, height: 1210), horizontal: .regular, vertical: .regular) {
                shell in
                let split = try #require(shell.split)
                #expect(split.displayMode == .oneBesideSecondary, "list beside the page, sidebar put away")
                #expect(shell.onScreen(.primary) == nil, "sidebar still on screen")
                #expect(shell.onScreen(.supplementary) != nil)
            }
        }

        /// Turning the iPad (or resizing a Split View) recomputes the tier; the day picked and
        /// the text typed stay.
        @Test func widthChangeReflowsAndKeepsTheSelection() async throws {
            try await Shell.hosted(size: CGSize(width: 834, height: 1210), horizontal: .regular, vertical: .regular) {
                shell in
                let day = "journal/2026-09-20.md"
                shell.navigation.selectedDay = day
                let draft = shell.navigation.quickEntryDraft(for: nil, store: shell.store) {
                    QuickEntryModel(store: shell.store)
                }
                draft.text = "Döndürme taslağı"
                await shell.settle()
                let split = try #require(shell.split)
                #expect(shell.navigation.section == .days)
                #expect(split.displayMode == .oneBesideSecondary, "834 pt is two columns")

                shell.resize(to: CGSize(width: 1376, height: 1032))
                await shell.settle(rounds: 20)
                #expect(split.displayMode == .twoBesideSecondary, "1376 pt is three columns")
                #expect(shell.onScreen(.primary) != nil)

                shell.resize(to: CGSize(width: 834, height: 1210))
                await shell.settle()
                #expect(split.displayMode == .oneBesideSecondary, "834 pt is two columns")
                #expect(shell.onScreen(.primary) == nil, "the sidebar stepped aside")
                #expect(shell.navigation.section == .days && shell.navigation.selectedDay == day)

                shell.resize(to: CGSize(width: 1376, height: 1032))
                await shell.settle()
                #expect(split.displayMode == .twoBesideSecondary, "back to three columns")
                #expect(shell.onScreen(.primary) != nil)
                #expect(shell.navigation.selectedDay == day, "the day is still selected")
                #expect(draft.text == "Döndürme taslağı", "the draft survived the turns")
            }
        }

        /// An upright 11" iPad: the sidebar opened with its button, Kanban chosen (the sidebar
        /// steps aside), the iPad turned, then Görevler chosen. Each layout is a split view of its
        /// own; the new one still opens with every column.
        @Test func layoutSwitchAfterATurnKeepsThreeColumns() async throws {
            try await Shell.hosted(size: CGSize(width: 834, height: 1210), horizontal: .regular, vertical: .regular) {
                shell in
                try #require(shell.split).show(.primary)
                await shell.settle()
                try shell.chooseSidebarRow(3)  // Kanban
                await shell.settle(rounds: 20)
                #expect(shell.onScreen(.primary) == nil, "the board took the width")

                shell.resize(to: CGSize(width: 1210, height: 834))
                await shell.settle(rounds: 20)
                #expect(shell.onScreen(.primary) != nil, "the turned board shows the sidebar")

                try shell.chooseSidebarRow(2)  // Görevler
                await shell.settle(rounds: 20)
                let split = try #require(shell.split)
                #expect(
                    split.displayMode == .twoBesideSecondary,
                    "Görevler after the turn: mode \(split.displayMode.rawValue)")
                #expect(shell.onScreen(.primary) != nil && shell.onScreen(.supplementary) != nil)
            }
        }

        // MARK: - Sidebar

        /// The selected row is only the accent fill: the focus halo iPadOS draws around the
        /// focused cell (the selected one, selection follows focus) takes the sidebar's tint,
        /// which is clear.
        @Test func sidebarDrawsNoFocusHalo() async throws {
            try await Shell.hosted(size: CGSize(width: 1376, height: 1032), horizontal: .regular, vertical: .regular) {
                shell in
                let rows = try #require(shell.collectionViews(in: .primary).first, "sidebar has no list")
                #expect(rows.selectionFollowsFocus, "the keyboard still walks the rows")
                let cells = rows.visibleCells
                #expect(cells.count > 5)
                for cell in cells {
                    #expect(cell.tintColor.alpha == 0, "a halo would be drawn in \(String(describing: cell.tintColor))")
                }
            }
        }

        /// A tap on the selected row is still a choice (Mac: a click on the selected "Görevler"
        /// returns the list to its first section). Measured through the list's delegate path
        /// (`didSelectItemAt`), not a real touch: whether UIKit sends a touch on the selected
        /// row there is for the device check.
        @Test func tapOnTheSelectedRowRunsItsClick() async throws {
            let clicks = ClickLog()
            let host = try HostedWindow(size: CGSize(width: 320, height: 900)) {
                SidebarHarness(clicks: clicks)
            }
            defer { host.close() }
            await host.settle()
            let rows = try #require(host.views(UICollectionView.self).first)
            let tasks = IndexPath(item: 2, section: 0)
            #expect(rows.indexPathsForSelectedItems == [tasks], "Görevler starts selected")
            rows.delegate?.collectionView?(rows, didSelectItemAt: tasks)
            await host.settle()
            #expect(clicks.entries == [.section(.tasks)], "the tap on the selected row did nothing: \(clicks.entries)")

            let today = IndexPath(item: 0, section: 0)
            rows.selectItem(at: today, animated: false, scrollPosition: [])
            rows.delegate?.collectionView?(rows, didSelectItemAt: today)
            await host.settle()
            #expect(clicks.selected == .section(.today), "the row did not select")
            #expect(clicks.entries.last == .section(.today))
        }

        // MARK: - List column

        /// The split shell's list rows select like the Mac's (recessed fill, accent rule); the
        /// tab shell keeps paper and the search wash.
        @Test(arguments: [ShellKind.split, .tabs])
        func listColumnSelectionFollowsTheShell(_ kind: ShellKind) async throws {
            let host = try HostedWindow(size: CGSize(width: 320, height: 240)) {
                List {
                    Text(verbatim: "Seçili").inkListRow(columnSelected: true)
                    Text(verbatim: "Diğer").inkListRow(columnSelected: false)
                }
                .listStyle(.plain)
                .environment(\.shellKind, kind)
            }
            defer { host.close() }
            await host.settle()
            let list = try #require(host.views(UICollectionView.self).first)
            let cells = list.visibleCells.sorted { $0.frame.minY < $1.frame.minY }
            try #require(cells.count == 2)
            let selected = cells[0].convert(cells[0].bounds, to: host.window)
            let other = cells[1].convert(cells[1].bounds, to: host.window)
            let image = Pixels(host.window)
            let fill = image.color(at: CGPoint(x: selected.midX, y: selected.minY + 6))
            let mark = image.color(
                at: CGPoint(
                    x: selected.minX + InkListSelectionChrome.horizontalInset + InkListSelectionChrome.markWidth / 2,
                    y: selected.midY))
            let idle = image.color(at: CGPoint(x: other.midX, y: other.minY + 6))
            let paper = Pixels.color(.paper, style: .light)
            #expect(idle.isClose(to: paper), "an unselected row is paper: \(idle)")
            switch kind {
            case .split:
                #expect(fill.isClose(to: Pixels.color(.well, style: .light)), "selected fill \(fill) is not the well")
                // The 2 pt rule at scale 1 meets the rounded clip: nearer the accent than the well.
                let accent = Pixels.color(.accent, style: .light)
                let well = Pixels.color(.well, style: .light)
                #expect(mark.distance(to: accent) < mark.distance(to: well) / 4, "no accent rule: \(mark)")
            case .tabs:
                #expect(!fill.isClose(to: Pixels.color(.well, style: .light)), "the phone drew the Mac selection")
                #expect(!fill.isClose(to: paper), "the search wash is gone: \(fill)")
            }
        }

        /// Görevler in the split shell: changing the section or a filter, or the task leaving
        /// the list, clears the detail; the phone's tab shell has no detail column to clear.
        @Test(arguments: [ShellKind.split, .tabs])
        func taskSelectionClearsInTheSplitShellOnly(_ kind: ShellKind) async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let day = CalendarDate("2026-09-20")!
            let model = TasksModel(store: context.store, today: { day })
            await model.loadList()
            let project = try #require(model.agenda.flatMap(\.rows).first { $0.project != nil })
            let dated = try #require(model.agenda.flatMap(\.rows).first { $0.due != nil && $0.project == nil })
            let box = SelectionBox()
            box.value = project.id
            let host = try HostedWindow(size: CGSize(width: 420, height: 800)) {
                TasksSelectionHarness(store: context.store, model: model, box: box)
                    .environment(\.shellKind, kind)
            }
            defer { host.close() }
            await host.settle()
            #expect(box.value == project.id)

            model.projectFilter = project.project
            await host.settle()
            #expect(model.agenda.flatMap(\.rows).contains { $0.id == project.id }, "the filter still lists the task")
            #expect(box.value == (kind == .split ? nil : project.id), "project filter")

            model.projectFilter = nil
            box.value = dated.id
            await host.settle()
            model.viewState.listSection = .undated
            await host.settle()
            #expect(box.value == (kind == .split ? nil : dated.id), "section change")

            model.viewState.listSection = .upcoming
            box.value = dated.id
            await host.settle()
            let completed = await model.toggle(dated)
            #expect(completed)
            for _ in 0..<20 where box.value != nil {
                await host.settle()
                if kind == .tabs { break }
            }
            #expect(box.value == (kind == .split ? nil : dated.id), "completed task")
        }

        // MARK: - Empty detail

        /// Nothing selected: the split shell's empty detail keeps the magnifier where a manşet
        /// row puts it (top trailing); the tab shell never shows this column.
        @Test(arguments: [ShellKind.split, .tabs])
        func emptyDetailHoldsSearchInTheSplitShell(_ kind: ShellKind) async throws {
            let size = CGSize(width: 380, height: 600)
            let host = try HostedWindow(size: size) {
                MacEmptyDetail("Bir görev seç")
                    .background(Color.ink.paper)
                    .environment(\.shellKind, kind)
            }
            defer { host.close() }
            await host.settle()
            let image = Pixels(host.window)
            let paper = Pixels.color(.paper, style: .light)
            // The manşet slot: a 44 pt target inside the page margin, at the top.
            let top = host.window.safeAreaInsets.top
            var inked = 0
            for x in stride(from: size.width - InkSpacing.margin - 44, to: size.width - InkSpacing.margin, by: 2) {
                for y in stride(from: top, to: top + 60, by: 2)
                where !image.color(at: CGPoint(x: x, y: y)).isClose(to: paper) {
                    inked += 1
                }
            }
            if kind == .split {
                #expect(inked > 10, "no magnifier at the top trailing corner")
            } else {
                #expect(inked == 0, "the corner is not empty paper: \(inked) points")
            }
        }

        // MARK: - Search sheet

        /// In the split shell search is a form sheet (580 × 480), so it does not run under the
        /// software keyboard; the tab shell keeps the phone's tall sheet.
        @Test(arguments: [ShellKind.split, .tabs])
        func searchSheetIsAFormInTheSplitShell(_ kind: ShellKind) async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let size = CGSize(width: 1376, height: 1032)
            let host = try HostedWindow(size: size, key: true) {
                SearchSheetHarness(store: context.store)
            }
            host.controller.traitOverrides.horizontalSizeClass = kind == .split ? .regular : .compact
            host.controller.traitOverrides.verticalSizeClass = .regular
            defer { host.close() }
            let keyboard = KeyboardWatch()
            defer { keyboard.stop() }
            for _ in 0..<40 where host.controller.presentedViewController?.view.window == nil {
                await host.settle(rounds: 1)
            }
            await host.settle()
            let sheet = try #require(host.controller.presentedViewController, "the search sheet never opened")
            let frame = sheet.view.convert(sheet.view.bounds, to: host.window)
            // The form adds its own top inset to the content's ideal height. A screen narrower
            // than the form (the iPhone the suite also runs on) gives it its minimum width.
            let formHeights = SearchSheetChrome.idealHeight...SearchSheetChrome.idealHeight + 20
            switch kind {
            case .split:
                #expect(
                    (InkSheetChrome.macMinWidth - 1...SearchSheetChrome.idealWidth + 1).contains(frame.width),
                    "sheet \(frame)")
                #expect(formHeights.contains(frame.height), "sheet \(frame)")
                if let top = keyboard.top {
                    #expect(frame.maxY <= top + 1, "the keyboard (top \(top)) covers the sheet \(frame)")
                }
            case .tabs:
                #expect(!formHeights.contains(frame.height), "the tab shell's sheet took the form: \(frame)")
            }
        }
    }

    // MARK: - Search sheet content

    extension SplitShellHostedTests {
        /// The sheet's content keeps its identity when the size class changes under it (an
        /// iPad Split View dragged narrow and back): the query typed survives.
        @Test func searchSheetSizingKeepsItsContentAcrossShells() async throws {
            let probe = IdentityProbe()
            let kind = ShellKindBox()
            kind.value = .split
            let host = try HostedWindow(size: CGSize(width: 800, height: 700)) {
                SizingHarness(probe: probe, kind: kind)
            }
            defer { host.close() }
            await host.settle()
            #expect(probe.appearances == 1)
            kind.value = .tabs
            await host.settle()
            kind.value = .split
            await host.settle()
            #expect(probe.appearances == 1, "the content was built again: \(probe.appearances) appearances")
            #expect(probe.tokens.count == 1, "the content's state was reset: \(probe.tokens.count) tokens")
        }
    }

    @MainActor @Observable private final class ShellKindBox {
        var value: ShellKind = .tabs
    }

    @MainActor private final class IdentityProbe {
        var appearances = 0
        var tokens: Set<UUID> = []
    }

    private struct SizingHarness: View {
        let probe: IdentityProbe
        let kind: ShellKindBox

        var body: some View {
            IdentityProbeView(probe: probe).modifier(SearchSheetSizing(shellKind: kind.value))
        }
    }

    /// Stands in for `SearchView`: its `@State` is the query a rebuilt view would lose.
    private struct IdentityProbeView: View {
        let probe: IdentityProbe
        @State private var token = UUID()

        var body: some View {
            Text(verbatim: "Ara")
                .onAppear {
                    probe.appearances += 1
                    probe.tokens.insert(token)
                }
                .onChange(of: token) { _, new in probe.tokens.insert(new) }
        }
    }

    // MARK: - Support

    extension AdaptiveShellHostedTests.Shell {
        /// A sidebar row chosen as a touch does it: the list selects it and tells its delegate.
        func chooseSidebarRow(_ item: Int) throws {
            let rows = try #require(collectionViews(in: .primary).first, "the sidebar is not on screen")
            let path = IndexPath(item: item, section: 0)
            rows.selectItem(at: path, animated: false, scrollPosition: [])
            rows.delegate?.collectionView?(rows, didSelectItemAt: path)
        }

        /// A turn or a Split View resize: the window and the host take the new size.
        func resize(to size: CGSize) {
            host.view.window?.frame = CGRect(origin: .zero, size: size)
            host.view.frame = CGRect(origin: .zero, size: size)
        }
    }

    /// One SwiftUI view in its own window of the Journal test host, laid out on screen.
    @MainActor
    private final class HostedWindow {
        let window: UIWindow
        let controller: UIHostingController<AnyView>

        init<Content: View>(size: CGSize, key: Bool = false, @ViewBuilder content: () -> Content) throws {
            let scene = try #require(
                UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
                "needs the Journal test host's window scene")
            controller = UIHostingController(
                rootView: AnyView(content().tint(Color.ink.accent).transaction { $0.animation = nil }))
            window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: size)
            window.overrideUserInterfaceStyle = .light
            window.rootViewController = controller
            if key { window.makeKeyAndVisible() } else { window.isHidden = false }
        }

        func settle(rounds: Int = 8) async {
            for _ in 0..<rounds {
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(30))
                controller.view.layoutIfNeeded()
            }
        }

        func close() {
            controller.presentedViewController?.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
            window.windowScene = nil
        }

        func views<T: UIView>(_ type: T.Type) -> [T] {
            var found: [T] = []
            func walk(_ view: UIView) {
                if let match = view as? T { found.append(match) }
                view.subviews.forEach(walk)
            }
            walk(window)
            return found
        }
    }

    /// The window drawn into an 8-bit sRGB bitmap at scale 1, read point by point.
    @MainActor
    private struct Pixels {
        private let bytes: [UInt8]
        private let width: Int
        private let height: Int

        init(_ window: UIWindow) {
            let width = Int(window.bounds.width)
            let height = Int(window.bounds.height)
            var buffer = [UInt8](repeating: 0, count: width * height * 4)
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            buffer.withUnsafeMutableBytes { raw in
                guard
                    let context = CGContext(
                        data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                        bytesPerRow: width * 4, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { return }
                // UIKit draws top-down.
                context.translateBy(x: 0, y: CGFloat(height))
                context.scaleBy(x: 1, y: -1)
                UIGraphicsPushContext(context)
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                UIGraphicsPopContext()
            }
            bytes = buffer
            self.width = width
            self.height = height
        }

        func color(at point: CGPoint) -> RGB {
            let x = min(max(Int(point.x), 0), width - 1)
            let y = min(max(Int(point.y), 0), height - 1)
            let offset = (y * width + x) * 4
            guard offset + 2 < bytes.count else { return RGB(red: -1, green: -1, blue: -1) }
            return RGB(
                red: Double(bytes[offset]) / 255, green: Double(bytes[offset + 1]) / 255,
                blue: Double(bytes[offset + 2]) / 255)
        }

        static func color(_ token: InkPalette.Token, style: UIUserInterfaceStyle) -> RGB {
            let resolved = UIColor(named: token.assetName)?.resolvedColor(
                with: UITraitCollection(userInterfaceStyle: style))
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            resolved?.getRed(&red, green: &green, blue: &blue, alpha: nil)
            return RGB(red: Double(red), green: Double(green), blue: Double(blue))
        }
    }

    private struct RGB: CustomStringConvertible {
        let red: Double
        let green: Double
        let blue: Double

        func isClose(to other: RGB, tolerance: Double = 4.0 / 255) -> Bool {
            abs(red - other.red) <= tolerance && abs(green - other.green) <= tolerance
                && abs(blue - other.blue) <= tolerance
        }

        func distance(to other: RGB) -> Double {
            abs(red - other.red) + abs(green - other.green) + abs(blue - other.blue)
        }

        var description: String {
            String(format: "rgb(%.0f, %.0f, %.0f)", red * 255, green * 255, blue * 255)
        }
    }

    extension UIColor {
        fileprivate var alpha: CGFloat {
            var alpha: CGFloat = 0
            getRed(nil, green: nil, blue: nil, alpha: &alpha)
            return alpha
        }
    }

    /// The software keyboard's top edge in the window, once it is shown.
    @MainActor
    private final class KeyboardWatch {
        private(set) var top: CGFloat?
        private var token: (any NSObjectProtocol)?

        init() {
            token = NotificationCenter.default.addObserver(
                forName: UIResponder.keyboardDidShowNotification, object: nil, queue: .main
            ) { [weak self] note in
                let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
                MainActor.assumeIsolated { self?.top = frame?.minY }
            }
        }

        func stop() {
            if let token { NotificationCenter.default.removeObserver(token) }
            token = nil
        }
    }

    @MainActor
    private final class ClickLog {
        var entries: [MacSidebarEntry] = []
        var selected: MacSidebarEntry?
    }

    @MainActor
    private final class SelectionBox {
        var value: String?
    }

    private struct SidebarHarness: View {
        let clicks: ClickLog
        @State private var selection: MacSidebarEntry? = .section(.tasks)

        var body: some View {
            MacSidebarList(
                entries: MacSidebar.entries(projects: []),
                selection: Binding(
                    get: { selection },
                    set: {
                        selection = $0
                        clicks.selected = $0
                    }),
                onClick: { clicks.entries.append($0) })
        }
    }

    private struct TasksSelectionHarness: View {
        let store: IndexStore
        let model: TasksModel
        let box: SelectionBox

        var body: some View {
            let _ = box.value
            NavigationStack {
                TasksView(
                    store: store, selection: Binding(get: { box.value }, set: { box.value = $0 }), tasks: model)
            }
        }
    }

    private struct SearchSheetHarness: View {
        let store: IndexStore
        @State private var presented = false

        var body: some View {
            Color.ink.paper
                .onAppear { presented = true }
                .searchSheet(isPresented: $presented, store: store)
        }
    }
#endif
