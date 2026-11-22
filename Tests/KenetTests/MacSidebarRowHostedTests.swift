#if os(iOS)
    import SwiftUI
    import Testing
    import UIKit

    @testable import Kenet

    /// The split shell's sidebar row on iOS, laid out by SwiftUI: icon and name up to the largest
    /// ordinary text size; at accessibility sizes the name alone, so a long single word
    /// ("çizelgesi", "Bugün" at AX5) keeps its line instead of being broken inside the word.
    @MainActor @Suite(.serialized, .timeLimit(.minutes(1)))
    struct MacSidebarRowHostedTests {
        static let entries: [MacSidebarEntry] = [
            .section(.today), .section(.summaries), .kanban, .timeline, .project("performans"),
        ]

        /// At accessibility sizes the row is exactly as wide as its name (plus the nested indent).
        @Test(arguments: [DynamicTypeSize.accessibility1, .accessibility3, .accessibility5])
        func accessibilitySizeRowIsTheNameAlone(_ size: DynamicTypeSize) {
            for entry in Self.entries {
                let extra = Self.rowWidth(entry, size: size) - Self.titleWidth(entry, size: size)
                #expect(abs(extra) < 1, "\(entry) at \(size): \(extra) pt beside the name")
            }
        }

        /// Below the accessibility sizes the icon stays: the row is wider than its name by at
        /// least the icon.
        @Test(arguments: [DynamicTypeSize.large, .xxxLarge])
        func ordinarySizeRowKeepsItsIcon(_ size: DynamicTypeSize) {
            for entry in Self.entries {
                let extra = Self.rowWidth(entry, size: size) - Self.titleWidth(entry, size: size)
                #expect(extra > 15, "\(entry) at \(size): only \(extra) pt beside the name")
            }
        }

        /// Upright 11" iPad (two columns): the sidebar laid over the list at an accessibility size
        /// is the wide one, so "Zaman çizelgesi" keeps its words whole there too.
        @Test func twoColumnSidebarWidensAtAccessibilitySizes() async throws {
            try await AdaptiveShellHostedTests.Shell.hosted(
                size: CGSize(width: 834, height: 1210), horizontal: .regular, vertical: .regular
            ) { shell in
                shell.host.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
                await shell.settle()
                let split = try #require(shell.split)
                split.show(.primary)
                await shell.settle(rounds: 20)
                let sidebar = try #require(shell.onScreen(.primary), "sidebar did not open")
                let width = ShellStyle.accessibilitySidebarWidth
                #expect(sidebar.width >= width.min, "sidebar \(sidebar)")
            }
        }

        /// A project name is one word: at accessibility sizes it keeps one line (shrunk if it has
        /// to) instead of breaking inside the word ("perfor- / mans" at AX5 in the 280 pt sidebar).
        @Test(arguments: [DynamicTypeSize.accessibility3, .accessibility5])
        func accessibilitySizeProjectNameKeepsOneLine(_ size: DynamicTypeSize) {
            // The sidebar's ideal width less the list's own side margins (about 26 pt each).
            let width = ShellStyle.accessibilitySidebarWidth.ideal - 52
            let short = Self.height(.project("ar"), width: width, size: size)
            let long = Self.height(.project("performans"), width: width, size: size)
            // A shrunk line is lower than a full one, never taller.
            #expect(long <= short + 1, "\"performans\" at \(size): \(long) pt against one line's \(short)")
            // The other names still wrap between their words.
            let wrapped = Self.height(.timeline, width: width, size: size)
            #expect(wrapped > short * 1.5, "\"Zaman çizelgesi\" at \(size): \(wrapped) pt")
        }

        /// The selected row is semibold and wider than the same name unselected. In the 240 pt
        /// three-column sidebar "Zaman çizelgesi" was cut to "Zaman çizelg…" only while selected:
        /// the name may shrink by ``MacSidebarChrome/titleMinimumScale`` and must then fit the
        /// room the system's sidebar list really gives a row.
        @Test func selectedTimelineNameFitsTheThreeColumnSidebar() async throws {
            let scene = try #require(
                UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
                "needs the Kenet test host's window scene")
            let entries = MacSidebar.entries(projects: ["performans"])
            let width = ShellStyle.threeColumnSidebarWidth.ideal
            let host = UIHostingController(
                rootView: MacSidebarList(entries: entries, selection: .constant(.timeline))
                    .environment(\.locale, Locale(identifier: "tr_TR"))
                    .environment(\.dynamicTypeSize, .large))
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: width, height: 900)
            window.traitOverrides.preferredContentSizeCategory = .large
            window.rootViewController = host
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
                window.windowScene = nil
            }
            for _ in 0..<10 {
                // Frame pump: the list lays its cells out on a later run-loop turn.
                try? await Task.sleep(for: .milliseconds(30))
                host.view.layoutIfNeeded()
            }
            let list = try #require(Self.views(UICollectionView.self, under: host.view).first, "no sidebar list")
            let index = try #require(entries.firstIndex(of: .timeline))
            let cell = try #require(list.cellForItem(at: IndexPath(item: index, section: 0)), "no timeline cell")
            // The SwiftUI row is the narrowest view the cell lays out inside itself.
            let room = try #require(
                Self.views(UIView.self, under: cell).map(\.bounds.width).filter { $0 > 0 }.min(), "empty cell")
            let regular = Self.rowIdealWidth(.timeline, isSelected: false)
            let selected = Self.rowIdealWidth(.timeline, isSelected: true)
            let name = Self.titleWidth(.timeline, size: .large)
            #expect(selected > regular, "the selected name is the wider one: \(selected) against \(regular)")
            let semibold = name + (selected - regular)
            let shrunk = selected - semibold * (1 - MacSidebarChrome.titleMinimumScale)
            #expect(shrunk <= room, "selected \"Zaman çizelgesi\" needs \(shrunk) pt of \(room)")
        }

        private static func views<T: UIView>(_ type: T.Type, under root: UIView) -> [T] {
            ((root as? T).map { [$0] } ?? []) + root.subviews.flatMap { views(type, under: $0) }
        }

        /// The row's one-line ideal width at the default text size, nested indent included.
        private static func rowIdealWidth(_ entry: MacSidebarEntry, isSelected: Bool) -> CGFloat {
            idealSize(of: MacSidebarRow(entry: entry, isSelected: isSelected, isWindowActive: true), size: .large)
                .width
        }

        /// The row's height in a column `width` wide.
        private static func height(_ entry: MacSidebarEntry, width: CGFloat, size: DynamicTypeSize) -> CGFloat {
            let host = UIHostingController(
                rootView: MacSidebarRow(entry: entry, isSelected: false, isWindowActive: true)
                    .frame(width: width)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.locale, Locale(identifier: "tr_TR"))
                    .environment(\.dynamicTypeSize, size))
            return host.sizeThatFits(in: CGSize(width: width, height: 4000)).height
        }

        /// The row's ideal width without the nested rows' leading indent.
        private static func rowWidth(_ entry: MacSidebarEntry, size: DynamicTypeSize) -> CGFloat {
            let row = MacSidebarRow(entry: entry, isSelected: false, isWindowActive: true)
            let indent = entry.isNested ? InkSpacing.margin : 0
            return idealSize(of: row, size: size).width - indent
        }

        private static func titleWidth(_ entry: MacSidebarEntry, size: DynamicTypeSize) -> CGFloat {
            idealSize(of: entry.title, size: size).width
        }

        /// One line, as wide as the view wants (`fixedSize`: the row's `maxWidth: .infinity`
        /// frame gives back its content's ideal width).
        private static func idealSize<V: View>(of view: V, size: DynamicTypeSize) -> CGSize {
            let host = UIHostingController(
                rootView: view.fixedSize()
                    .environment(\.locale, Locale(identifier: "tr_TR"))
                    .environment(\.dynamicTypeSize, size))
            return host.sizeThatFits(in: CGSize(width: 2000, height: 2000))
        }
    }
#endif
