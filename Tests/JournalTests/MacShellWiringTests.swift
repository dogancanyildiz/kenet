#if os(macOS)
    import AppKit
    import SwiftUI
    import Testing

    @testable import Journal

    /// The real shell (`MacNavigation`) with the sample vault, mounted offscreen: what the three
    /// layouts really install (columns, window minimum, toolbar, title) and what a sidebar row
    /// really does. The window is never ordered on screen.
    @MainActor @Suite(.serialized, .timeLimit(.minutes(1)))
    struct MacShellWiringTests {
        private let watchdog = HostedTestWatchdog()
        @Test func columnsLayoutUsesTheColumnWidthsAndHidesTheToolbarTitle() async throws {
            let shell = try await Shell()
            defer { shell.close() }
            #expect(shell.window.title == String(localized: "Bugün"), "the window is named after the selected row")
            #expect(shell.window.titleVisibility == .hidden, "the toolbar repeats no title")
            let widths = try MacSplitMeasure.columns(in: shell.mount)
            try await MacSplitMeasure.expectSidebar(widths[0], isIdeal: 200, window: 1280)
            #expect(abs(widths[1] - 320) <= 2, "list \(widths[1]) pt")
            #expect(widths[2] >= InkSpacing.macPageWidth, "detail \(widths[2]) pt")
            #expect(shell.searchItems == 1, "toolbar: \(shell.toolbarLabels)")
        }

        @Test func windowDoesNotShrinkBelowItsMinimum() async throws {
            let shell = try await Shell()
            defer { shell.close() }
            let fitted = NSHostingController(rootView: shell.view).sizeThatFits(in: CGSize(width: 500, height: 300))
            #expect(fitted.width == 1000, "width \(fitted.width)")
            #expect(fitted.height == 560, "height \(fitted.height)")
        }

        /// Down the sidebar with the arrow keys: every layout keeps one toolbar search, a board
        /// row really opens its board, and focus stays in the sidebar across the layout swaps
        /// (the test never puts it back itself).
        @Test func sidebarRowsOpenTheirLayoutsWithOneSearchEach() async throws {
            let shell = try await Shell()
            defer { shell.close() }
            let table = try #require(shell.sidebarTable)
            guard HostedFocus.isAvailable(for: table, in: shell.window) else { return }

            var seen: [String: (panes: Int, search: Int)] = [:]
            var titles: [String] = []
            for _ in 0..<17 {
                try await shell.pressDown()
                titles.append(shell.window.title)
                seen[shell.window.title] = (shell.paneCounts.max() ?? 0, shell.searchItems)
            }
            #expect(
                Array(titles.prefix(4)) == [
                    String(localized: "Günlük"), String(localized: "Görevler"), "Kanban",
                    String(localized: "Zaman çizelgesi"),
                ],
                "walked: \(titles)")
            #expect(titles.contains(String(localized: "Özetler")) && titles.contains("Graph"), "walked: \(titles)")
            #expect(seen[String(localized: "Görevler")]?.panes == 3)
            #expect(seen["Kanban"]?.panes == 2, "the board takes the full width")
            #expect(seen[String(localized: "Zaman çizelgesi")]?.panes == 2)
            #expect(seen[String(localized: "Özetler")]?.panes == 2)
            for (title, state) in seen {
                #expect(state.search == 1, "\(title): \(state.search) toolbar search items")
            }
            #expect(shell.window.titleVisibility == .hidden)
        }

        /// A project removed from the vault while its page is open.
        @Test func deletedProjectFallsBackToTasks() async throws {
            let shell = try await Shell()
            defer { shell.close() }
            let table = try #require(shell.sidebarTable)
            guard HostedFocus.isAvailable(for: table, in: shell.window) else { return }
            for _ in 0..<5 { try await shell.pressDown() }
            #expect(shell.window.title == "altyapi", "walked to the first project: \(shell.window.title)")

            let file = shell.context.root.appendingPathComponent("journal/2026-09-15.md")
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(text.contains("#project/altyapi"))
            try text.replacingOccurrences(of: " #project/altyapi", with: "")
                .write(to: file, atomically: true, encoding: .utf8)
            await shell.context.store.refresh()
            await shell.mount.settle(rounds: 16)
            #expect(!shell.context.store.content.projects.contains("altyapi"))
            #expect(shell.window.title == String(localized: "Görevler"), "window: \(shell.window.title)")
        }

        /// Audit finding 8: an empty detail column was system white (dark: gray) with the prompt
        /// inside a paper box. The column is paper, and the prompt is ink on that paper.
        @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
        func emptyDetailColumnIsPaperWithoutABox(appearance: NSAppearance.Name) async throws {
            let shell = try await Shell(appearance: appearance)
            defer { shell.close() }
            let table = try #require(shell.sidebarTable)
            guard HostedFocus.isAvailable(for: table, in: shell.window) else { return }
            let paper = DetailPixels.paper(appearance)
            let wanted = [
                String(localized: "Günlük"), String(localized: "Görevler"), "altyapi",
                String(localized: "Kişiler"), String(localized: "Konumlar"), String(localized: "Hedefler"),
            ]
            var seen: [String] = []
            for _ in 0..<20 {
                try await shell.pressDown()
                guard wanted.contains(shell.window.title), !seen.contains(shell.window.title) else { continue }
                let detail = try #require(shell.detailColumn, "no detail column on \(shell.window.title)")
                let bitmap = try DetailPixels.render(detail)
                DetailPixels.expectPaper(bitmap, paper: paper, title: shell.window.title)
                seen.append(shell.window.title)
            }
            #expect(seen == wanted, "measured \(seen)")
        }

        @MainActor
        struct Shell {
            let context: TaskTestContext
            let view: AnyView
            let mount: HostedLayout.Mount

            init(appearance: NSAppearance.Name? = nil) async throws {
                context = try TaskTestContext(sample: true)
                await context.start()
                let defaults = context.defaults.defaults
                let scheme: ColorScheme = appearance == .darkAqua ? .dark : .light
                let navigation = MacNavigation(store: context.store)
                    .environment(NotificationService(center: FakeNotificationCenter(), defaults: defaults))
                    .environment(CalendarService(source: IdleShellCalendarSource()))
                    .environment(LocationService(source: FakeLocationSource(), defaults: defaults))
                    .environment(IntentNavigation())
                    .environment(\.openSearch, {})
                    .environment(\.locale, Locale(identifier: "tr_TR"))
                view = AnyView(
                    appearance == nil ? AnyView(navigation) : AnyView(navigation.environment(\.colorScheme, scheme)))
                mount = HostedLayout.Mount(view, size: CGSize(width: 1280, height: 800), bridgesToolbar: true)
                releaseJournalMark = await HostedJournalWindow.claim(mount.window)
                if let appearance {
                    mount.window.appearance = NSAppearance(named: appearance)
                    mount.window.contentView?.appearance = mount.window.appearance
                }
                await mount.settle(rounds: 20)
            }

            /// The shell judges focus in the journal window: that is this hosted window until
            /// the shell closes.
            private let releaseJournalMark: @MainActor () -> Void

            var window: NSWindow { mount.window }
            var paneCounts: [Int] { mount.views(NSSplitView.self).map(\.arrangedSubviews.count) }
            var toolbarLabels: [String] { window.toolbar?.items.map(\.label) ?? [] }
            var searchItems: Int { toolbarLabels.filter { $0 == "Ara" }.count }
            /// The sidebar's list: the table that is as narrow as the sidebar column.
            var sidebarTable: NSTableView? {
                mount.views(NSTableView.self).first {
                    $0.convert($0.bounds, to: nil).width <= InkSpacing.macSidebarMaxWidth + 1
                }
            }

            /// The detail pane of the three-column split.
            var detailColumn: NSView? {
                mount.views(NSSplitView.self).first { $0.arrangedSubviews.count == 3 }?.arrangedSubviews.last
            }

            func pressDown() async throws {
                let table = try #require(sidebarTable)
                let responder = try #require(window.firstResponder as? NSView, "nothing holds the focus")
                #expect(
                    responder === table || responder.isDescendant(of: table),
                    "the arrow key would miss the sidebar (\(window.title))")
                let characters = String(UnicodeScalar(UInt16(NSDownArrowFunctionKey))!)
                let event = try #require(
                    NSEvent.keyEvent(
                        with: .keyDown, location: .zero, modifierFlags: [.numericPad, .function], timestamp: 0,
                        windowNumber: window.windowNumber, context: nil, characters: characters,
                        charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 125))
                responder.keyDown(with: event)
                await mount.settle(rounds: 12)
            }

            func close() {
                releaseJournalMark()
                mount.close()
                context.clean()
            }
        }
    }

    /// Pixels of a hosted detail column, compared with the paper token.
    @MainActor
    private enum DetailPixels {
        struct Sample: Equatable {
            var r: Int
            var g: Int
            var b: Int

            var hex: String { String(format: "%02X%02X%02X", r, g, b) }

            func near(_ other: Sample, tolerance: Int = 6) -> Bool {
                abs(r - other.r) <= tolerance && abs(g - other.g) <= tolerance && abs(b - other.b) <= tolerance
            }
        }

        static func paper(_ appearance: NSAppearance.Name) -> Sample {
            let hex = InkPalette.Token.paper.variant.hex(for: appearance == .darkAqua ? .dark : .light)
            return Sample(r: Int((hex >> 16) & 0xFF), g: Int((hex >> 8) & 0xFF), b: Int(hex & 0xFF))
        }

        static func render(_ view: NSView) throws -> NSBitmapImageRep {
            let width = max(1, Int(view.bounds.width.rounded()))
            let height = max(1, Int(view.bounds.height.rounded()))
            let rep = try #require(
                NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                    bytesPerRow: 0, bitsPerPixel: 0))
            rep.size = NSSize(width: width, height: height)
            view.cacheDisplay(in: view.bounds, to: rep)
            return rep
        }

        static func expectPaper(_ rep: NSBitmapImageRep, paper: Sample, title: String) {
            let width = rep.pixelsWide
            let height = rep.pixelsHigh
            #expect(width > 200 && height > 200, "\(title) detail \(width)x\(height)")
            let corners = [(16, 28), (width - 16, 28), (16, height - 16), (width - 16, height - 16)]
            for (x, y) in corners {
                let sample = color(rep, x: x, y: y)
                #expect(
                    sample.near(paper),
                    "\(title) (\(x),\(y)) \(sample.hex) paper \(paper.hex)")
            }
            var ink = 0
            let midY = height / 2
            for y in (midY - 16)..<(midY + 16) {
                for x in (width / 2 - 80)..<(width / 2 + 80) {
                    if !color(rep, x: x, y: y).near(paper, tolerance: 24) { ink += 1 }
                }
            }
            #expect(ink > 8, "\(title) has no empty-state sentence (\(ink) ink pixels)")
        }

        /// Same origin as ``InkListSelectionTests``: y grows downward from the top of the view.
        private static func color(_ rep: NSBitmapImageRep, x: Int, y: Int) -> Sample {
            guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                return Sample(r: 0, g: 0, b: 0)
            }
            return Sample(
                r: Int((color.redComponent * 255).rounded()),
                g: Int((color.greenComponent * 255).rounded()),
                b: Int((color.blueComponent * 255).rounded()))
        }
    }

    @MainActor
    private final class IdleShellCalendarSource: CalendarEventSource {
        var authorization = CalendarAuthorization.notDetermined
        var onChange: (@MainActor @Sendable () -> Void)?
        func requestFullAccess() async throws -> Bool { false }
        func events(from start: Date, to end: Date) async throws -> [CalendarEvent] { [] }
    }
#endif
