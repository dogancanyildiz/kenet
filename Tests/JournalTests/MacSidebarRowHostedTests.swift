#if os(iOS)
    import SwiftUI
    import Testing
    import UIKit

    @testable import Journal

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
