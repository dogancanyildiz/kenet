#if os(macOS)
    import AppKit
    import SwiftUI
    import Testing
    import VaultFormat

    @testable import Journal

    /// Mac Today desk hour grid: a timed task card has a completion box. A click on the box
    /// completes the task through the day page's own path (the file first: `- [x]`), keeps the
    /// card on the grid drawn done, and does not open the editor.
    @MainActor @Suite(.serialized, .timeLimit(.minutes(1)))
    struct TodayDeskTaskBoxHostedTests {
        private let watchdog = HostedTestWatchdog()

        @Test func boxOnTheGridCompletesTheTaskWithoutOpeningTheEditor() async throws {
            let context = try TaskTestContext()
            defer { context.clean() }
            await context.start()
            let today = LocalDay.today()
            let path = "journal/\(today).md"
            let url = context.root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("## Tasks\n- [ ] 10:00 Sunum provası\n\n## Events\n- 11:00 Toplantı\n".utf8).write(to: url)
            await context.store.refresh()

            let mount = HostedLayout.Mount(
                GoalScreenEnvironment.wrap(
                    NavigationStack { DayView(store: context.store, date: today, isToday: true) }
                        .environment(\.todayDeskChrome, TodayDeskChrome(showsPanel: false, onThisDay: nil))
                        .environment(\.locale, Locale(identifier: "tr_TR")),
                    context: context),
                size: CGSize(width: 720, height: 1600))
            let release = await HostedJournalWindow.claim(mount.window)
            defer {
                release()
                mount.close()
            }
            let id = TodayDeskTimeline.taskBoxIdentifier
            guard
                await HostedControls.isAvailable(
                    mount, until: { HostedControls.node(id, in: mount) != nil })
            else { return }

            // One box: the task card has it, the event card does not.
            let boxes = HostedControls.nodes(in: mount).filter { $0.identifier == id }
            #expect(boxes.count == 1, "boxes on the grid: \(boxes.map(\.label))")
            let box = try #require(boxes.first)
            #expect(box.label == "Tamamla, Sunum provası", "box label: \(box.label)")

            let windows = Set(NSApp.windows.map(ObjectIdentifier.init))
            box.press()
            var written = ""
            for _ in 0..<60 {
                await mount.settle(rounds: 1)
                written = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                if written.contains("- [x] 10:00 Sunum provası") { break }
            }
            #expect(written.contains("- [x] 10:00 Sunum provası"), "file after the click:\n\(written)")
            #expect(written.contains("- 11:00 Toplantı"), "the rest of the file stays")

            // The card stays on the grid, done; its box is now a mark only.
            for _ in 0..<40 where HostedControls.node(id, in: mount) != nil {
                await mount.settle(rounds: 1)
            }
            await mount.settle(rounds: 8)
            #expect(HostedControls.node(id, in: mount) == nil, "a done task's box takes no click")
            #expect(
                HostedControls.nodes(in: mount).contains {
                    $0.label.contains("Sunum provası") && $0.value.contains("Tamamlandı")
                }, "the card stays on the grid drawn done")

            let opened = NSApp.windows.filter { !windows.contains(ObjectIdentifier($0)) }
            #expect(
                !opened.contains { String(describing: type(of: $0)).contains("Sheet") },
                "the box click opened the editor: \(opened)")
            for window in opened { window.orderOut(nil) }
        }
    }
#endif
