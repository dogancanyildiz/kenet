import CoreTransferable
import Foundation
import Testing
import UniformTypeIdentifiers

@testable import Journal

/// Which board and timeline each shell draws (`docs/screens.md`, Kanban and Zaman çizelgesi:
/// "iPad (bölünmüş kabuk)"), and where a dragged card lands.
@Suite struct KanbanBoardStyleTests {
    @Test func splitShellDrawsTheDesktopBoardAndTabsThePhoneBoard() {
        #expect(KanbanBoardStyle.resolve(shell: .split) == .desktop)
        #if os(macOS)
            // The Mac window has one board whatever a hosted view reports.
            #expect(KanbanBoardStyle.resolve(shell: .tabs) == .desktop)
        #else
            #expect(KanbanBoardStyle.resolve(shell: .tabs) == .phone)
        #endif
    }

    /// iPad 13" landscape: the detail column beside the sidebar (200 to 240 pt), the 340 pt panel
    /// and its rule beside the board. All three status columns are on screen at once.
    @Test func desktopBoardFitsThreeColumnsBesideTheIPadPanel() {
        for sidebar in [InkSpacing.macSidebarIdealWidth, InkSpacing.macSidebarMaxWidth] {
            let board = 1376 - sidebar - KanbanDetailPlacement.panelWidth - 1
            let width = KanbanBoardStyle.desktop.columnWidth(fitting: board, columns: 3)
            let used = width * 3 + KanbanBoardLayout.columnSpacing * 2 + KanbanBoardLayout.boardPadding * 2
            #expect(width >= KanbanBoardLayout.minimumColumnWidth, "board \(board)")
            #expect(abs(used - board) < 0.01, "board \(board): columns use \(used)")
        }
        // Without the panel the columns grow and still fill the board instead of leaving paper.
        let board = 1376 - InkSpacing.macSidebarIdealWidth
        let open = KanbanBoardStyle.desktop.columnWidth(fitting: board, columns: 3)
        let used = open * 3 + KanbanBoardLayout.columnSpacing * 2 + KanbanBoardLayout.boardPadding * 2
        #expect(open > KanbanBoardLayout.maximumPhoneColumnWidth && abs(used - board) < 0.01, "\(open)")
    }

    /// The phone column keeps a peek of the next one and never grows past 360 pt.
    @Test func phoneBoardKeepsItsPagedColumn() {
        #expect(KanbanBoardStyle.phone.columnWidth(fitting: 390, columns: 3) == 358)
        #expect(KanbanBoardStyle.phone.columnWidth(fitting: 1136, columns: 3) == 360)
        #expect(KanbanBoardStyle.phone.columnWidth(fitting: 200, columns: 3) == 240)
        #expect(KanbanBoardStyle.phone.columnWidth(fitting: .nan, columns: 3) == 240)
    }

    @Test func onlyTheDesktopBoardHugsTheMenuDragsAndScrollsFreely() {
        #expect(!KanbanBoardStyle.desktop.groupingMenuExpands)
        #expect(KanbanBoardStyle.desktop.dragsCards)
        #expect(!KanbanBoardStyle.desktop.pagesColumns)
        #expect(KanbanBoardStyle.phone.groupingMenuExpands)
        #expect(!KanbanBoardStyle.phone.dragsCards)
        #expect(KanbanBoardStyle.phone.pagesColumns)
    }

    /// The 13" boards keep the panel: two columns at their floor fit beside it. The 11" and
    /// iPad mini upright boards (834 and 744 pt) and the 13" upright board beside an open
    /// sidebar (792 pt) open the detail in a sheet instead.
    @Test func iPadBoardsKeepTheDetailPanelOnlyWithTwoColumns() {
        for width: CGFloat in [1032, 1136, 1176] {
            #expect(KanbanDetailPlacement.usesPanel(shell: .split, width: width), "\(width)")
        }
        for width: CGFloat in [744, 792, 834] {
            #expect(!KanbanDetailPlacement.usesPanel(shell: .split, width: width), "\(width)")
        }
    }
}

@Suite struct TimelineLayoutStyleTests {
    @Test func splitShellDrawsTheChartAndTabsTheList() {
        #expect(TimelineLayoutStyle.resolve(shell: .split) == .desktop)
        #if os(macOS)
            #expect(TimelineLayoutStyle.resolve(shell: .tabs) == .desktop)
        #else
            #expect(TimelineLayoutStyle.resolve(shell: .tabs) == .list)
        #endif
    }

    /// The panel needs the 260 pt label column and a 200 pt chart beside it: iPad 11" upright
    /// (834 pt) and wider keep it; the Duo upright (626 pt) and iPad mini upright (744 pt) open a
    /// sheet. Mac: always the panel.
    @Test func chartKeepsThePanelWhileTheLabelsAndAChartFit() {
        let threshold = TimelineDetailPlacement.panelWidth + TimelineDetailPlacement.minimumChartWidth
        #expect(threshold == 800)
        #if os(macOS)
            #expect(TimelineDetailPlacement.usesPanel(shell: .tabs, width: 0))
            #expect(TimelineDetailPlacement.usesPanel(shell: .split, width: 626))
        #else
            for width: CGFloat in [threshold, 834, 890, 1176] {
                #expect(TimelineDetailPlacement.usesPanel(shell: .split, width: width), "\(width)")
            }
            for width: CGFloat in [0, 626, 744, threshold - 1] {
                #expect(!TimelineDetailPlacement.usesPanel(shell: .split, width: width), "\(width)")
            }
            #expect(!TimelineDetailPlacement.usesPanel(shell: .tabs, width: 1376))
        #endif
    }
}

@MainActor struct KanbanDropLandingTests {
    private static let source = """
        ## Tasks
        - [ ] Early 📅 2026-10-02 ^early
        - [ ] Late 📅 2026-10-09 ^late
        - [/] Middle 📅 2026-10-05 ^middle
        - [/] Undated ^undated
        - [/] First 📅 2026-10-01 ^first
        """

    /// The column under the finger takes the card at the place its order gives: between two
    /// dates, after every dated card, or first.
    @Test func cardLandsWhereTheTargetColumnOrderPutsIt() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let model = try await Self.board(context)
        let todo = try #require(model.columns.first { $0.destination == .status(.todo) })
        let doing = try #require(model.columns.first { $0.destination == .status(.inProgress) })
        #expect(todo.rows.compactMap(\.sourceIdentifier) == ["early", "late"])
        #expect(doing.rows.compactMap(\.sourceIdentifier) == ["first", "middle", "undated"])

        let middle = try #require(doing.rows.first { $0.sourceIdentifier == "middle" })
        #expect(KanbanDropLanding.resolve(middle, over: todo, in: model) == .init(columnID: todo.id, index: 1))
        let undated = try #require(doing.rows.first { $0.sourceIdentifier == "undated" })
        #expect(KanbanDropLanding.resolve(undated, over: todo, in: model) == .init(columnID: todo.id, index: 2))
        let first = try #require(doing.rows.first { $0.sourceIdentifier == "first" })
        #expect(KanbanDropLanding.resolve(first, over: todo, in: model) == .init(columnID: todo.id, index: 0))
        let early = try #require(todo.rows.first)
        #expect(KanbanDropLanding.resolve(early, over: doing, in: model) == .init(columnID: doing.id, index: 1))
    }

    /// No mark where the board would not move the card: its own column, or the person grouping.
    @Test func noLandingWhereTheBoardRefusesTheMove() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let model = try await Self.board(context)
        let doing = try #require(model.columns.first { $0.destination == .status(.inProgress) })
        let middle = try #require(doing.rows.first { $0.sourceIdentifier == "middle" })
        #expect(KanbanDropLanding.resolve(middle, over: doing, in: model) == nil)
        model.grouping = .person
        for column in model.columns {
            #expect(KanbanDropLanding.resolve(middle, over: column, in: model) == nil, "\(column.id)")
        }
        #expect(try Data(contentsOf: context.file) == Data(Self.source.utf8))
    }

    /// Its own place is not counted: a card already in the list lands where it sits.
    @Test func cardIsNotCountedAgainstItself() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let model = try await Self.board(context)
        let doing = try #require(model.columns.first { $0.destination == .status(.inProgress) })
        for (index, row) in doing.rows.enumerated() {
            #expect(KanbanDropLanding.index(of: row, among: doing.rows) == index)
        }
    }

    private static func board(_ context: TaskTestContext) async throws -> KanbanModel {
        await context.start()
        try source.write(to: context.file, atomically: true, encoding: .utf8)
        await context.store.refresh()
        let model = KanbanModel(tasks: TasksModel(store: context.store, today: { context.today }))
        await model.load()
        return model
    }
}

/// A dragged card carries its board token as plain text, the type the columns' drop reads, and
/// nothing else another app could take.
@Suite struct KanbanDragPayloadTests {
    @Test func cardCarriesTheTokenAsPlainTextOnly() async throws {
        let token = UUID().uuidString
        let provider = KanbanDragPayload.provider(token: token)
        #expect(provider.registeredTypeIdentifiers == [UTType.utf8PlainText.identifier])
        // The columns read it as `dropDestination(for: String.self)` does.
        let read = try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadTransferable(type: String.self) { continuation.resume(with: $0) }
        }
        #expect(read == token)
    }
}
