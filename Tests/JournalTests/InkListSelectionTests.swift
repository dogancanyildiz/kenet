import Foundation
import Testing

@testable import Journal

/// Mac list-column selection: the drawn fill is the well token, the mark is accent,
/// and a sheet row does not inherit the column selection.
struct InkListSelectionTests {
    private static let bodyMinimum = 4.5

    @Test func fillAndMarkArePaletteTokens() {
        #expect(InkListSelectionChrome.fill == .well)
        #expect(InkListSelectionChrome.mark == .accent)
        #expect(InkListSelectionChrome.markWidth == InkSize.modeUnderline)
        #expect(InkListSelectionChrome.cornerRadius == InkSize.listSelectionCorner)
        #expect(InkListSelectionChrome.horizontalInset == InkSpacing.listSelectionHorizontal)
        #expect(InkListSelectionChrome.verticalInset == InkSpacing.listSelectionVertical)
    }

    @Test func keepingDropsAnIdThatLeftTheList() {
        #expect(TaskListSelection.keeping("a", listedIDs: ["a", "b"]) == "a")
        #expect(TaskListSelection.keeping("a", listedIDs: ["b"]) == nil)
        #expect(TaskListSelection.keeping(nil, listedIDs: ["a"]) == nil)
    }

    @Test func boxLinkAndRowStayApart() {
        #expect(TasksListRowInteraction.action(for: .box, hasLink: true, isMac: true) == .toggleCompletion)
        #expect(TasksListRowInteraction.action(for: .link, hasLink: true, isMac: true) == .openLink)
        #expect(TasksListRowInteraction.action(for: .row, hasLink: true, isMac: true) == .selectRow)
        #expect(TasksListRowInteraction.action(for: .row, hasLink: false, isMac: true) == .selectRow)
        #expect(TasksListRowInteraction.action(for: .row, hasLink: false, isMac: false) == .toggleCompletion)
        #expect(TasksListRowInteraction.action(for: .row, hasLink: true, isMac: false) == nil)
        #expect(TasksListRowInteraction.action(for: .box, hasLink: false, isMac: false) == .toggleCompletion)
    }
}

#if os(macOS)
    import AppKit
    import Observation
    import SwiftUI
    import VaultFormat

    @MainActor
    struct InkListSelectionMacTests {
        @Test func drawnSelectionUsesFillAndMark() async throws {
            for appearance in [AppearanceCase.light, AppearanceCase.dark] {
                let bitmap = try await SelectionBitmap.render(
                    SelectionSwatches(scheme: appearance.scheme),
                    size: SelectionSwatches.size,
                    appearance: appearance.name)
                let swatches = SelectionSwatches.samples(in: bitmap)
                let center = try #require(bitmap.color(x: Int(SelectionSwatches.size.width) / 2, y: 24))
                #expect(
                    center.nearest(among: swatches) == .fill,
                    "center \(center) on \(appearance.scheme) is not the fill swatch \(swatches.fill)")
                let mark = try #require(bitmap.color(x: 5, y: 24))
                #expect(
                    mark.nearest(among: swatches) == .mark,
                    "leading rule \(mark) on \(appearance.scheme) is not the mark swatch \(swatches.mark)")
                for token in InkListSelectionChrome.textTokens {
                    let foreground = try #require(swatches.text[token])
                    let ratio = InkPalette.contrastRatio(foreground: foreground.hex, background: center.hex)
                    #expect(
                        ratio + 0.000_1 >= 4.5,
                        "\(token.rawValue) on drawn fill \(appearance.scheme): \(ratio)")
                }
            }
        }

        @Test func sheetRowDoesNotPaintColumnSelection() async throws {
            let size = CGSize(width: 280, height: 160)
            let bitmap = try await SelectionBitmap.render(SheetSelectionProbe(), size: size)
            let fill = try await SelectionBitmap.fillSwatch()
            let row = SelectionBitmap.wellCount(in: bitmap, yRange: 0..<160, fill: fill)
            #expect(row < 150, "sheet row painted \(row) fill pixels")
        }

        @Test func journalDayRowDrawsColumnSelection() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let days = context.store.content.days
            let id = try #require(days.first?.id)
            let sink = HostedLayout.Sink()
            let size = CGSize(width: 320, height: 360)
            let view = MacDayList(days: days, selection: .constant(id))
                .frame(width: size.width, height: size.height)
                .onPreferenceChange(InkColumnChromeCountKey.self) { sink.values = [CGFloat($0)] }
            await HostedLayout.settle(view, size: size)
            #expect(sink.values.first == 1, "day list chrome count \(sink.values)")

            let bitmap = try await SelectionBitmap.render(
                MacDayList(days: days, selection: .constant(id))
                    .frame(width: size.width, height: size.height),
                size: size)
            let fill = try await SelectionBitmap.fillSwatch()
            let wells = SelectionBitmap.wellCount(in: bitmap, yRange: 0..<120, fill: fill)
            #expect(wells > 200, "journal row fill pixels \(wells)")
        }

        @Test func macTaskRowHasNoDetailButton() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let row = try #require(
                context.store.content.tasks.first {
                    $0.sourceText.contains("Hafta sonu dinlenme planı yap")
                })
            let sink = HostedLayout.Sink()
            let width: CGFloat = 360
            let view = TasksListRow(
                store: context.store, row: row, day: context.today, isOverdue: false, isBusy: false,
                allowsReopening: true
            ) {}
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: RowHeightKey.self, value: proxy.size.height)
                }
            }
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
            .onPreferenceChange(RowHeightKey.self) { sink.values = [$0] }
            await HostedLayout.settle(view, size: CGSize(width: width, height: 400))
            let height = try #require(sink.values.first)
            // This row is a single line (33 pt). A control under it adds another line.
            #expect(height < 48, "task row is \(height) pt; a control under it would be taller")
        }

        @Test func macRowClickDoesNotComplete() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let row = try #require(
                context.store.content.tasks.first {
                    $0.sourceText.contains("Hafta sonu dinlenme planı yap")
                })
            let clicks = ClickCount()
            let size = CGSize(width: 360, height: 72)
            let host = MacHost(
                TasksListRow(
                    store: context.store, row: row, day: context.today, isOverdue: false, isBusy: false,
                    allowsReopening: true
                ) { clicks.value += 1 }
                .frame(width: size.width, height: size.height),
                size: size)
            await host.settle()
            var boxPoint: CGPoint?
            for x in stride(from: CGFloat(12), to: 40, by: 8) {
                for y in stride(from: CGFloat(20), to: 52, by: 8) {
                    let before = clicks.value
                    host.click(at: CGPoint(x: x, y: y))
                    if clicks.value > before {
                        boxPoint = CGPoint(x: x, y: y)
                        break
                    }
                }
                if boxPoint != nil { break }
            }
            let afterBox = clicks.value
            host.click(at: CGPoint(x: 220, y: 28))
            host.click(at: CGPoint(x: 100, y: 48))
            host.close()
            #expect(boxPoint != nil, "no point in the gutter completed the task")
            #expect(clicks.value == afterBox, "text or date click completed the task")
        }

        @Test func sectionFilterAndCompletionClearSelection() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let day = CalendarDate("2026-09-20")!
            let model = TasksModel(store: context.store, today: { day })
            let project = try #require(
                model.agenda.flatMap(\.rows).first { $0.project != nil })
            let dated = try #require(
                model.agenda.flatMap(\.rows).first { $0.due != nil && $0.project == nil })
            let box = SelectionBox()
            box.value = project.id
            let host = MacHost(
                SelectionHarness(store: context.store, model: model, box: box),
                size: CGSize(width: 420, height: 640))
            await host.settle()
            #expect(box.value == project.id)

            model.projectFilter = project.project
            await host.settle()
            #expect(
                model.agenda.flatMap(\.rows).contains { $0.id == project.id },
                "filter removed the task; the test needs a filter that still lists it")
            #expect(box.value == nil, "filter change left the selection")

            model.projectFilter = nil
            await host.settle()
            box.value = dated.id
            await host.settle()
            #expect(box.value == dated.id)
            model.viewState.listSection = .undated
            await host.settle()
            #expect(box.value == nil, "section change left the selection")

            model.viewState.listSection = .upcoming
            await host.settle()
            box.value = dated.id
            await host.settle()
            #expect(box.value == dated.id)
            let completed = await model.toggle(dated)
            #expect(completed)
            for _ in 0..<20 {
                await host.settle()
                if box.value == nil { break }
            }
            host.close()
            #expect(box.value == nil, "completed task stayed selected")
            #expect(!model.agenda.flatMap(\.rows).contains { $0.id == dated.id })
        }
    }

    private struct SelectionHarness: View {
        let store: IndexStore
        let model: TasksModel
        let box: SelectionBox

        var body: some View {
            let _ = box.value
            TasksView(
                store: store,
                selection: Binding(get: { box.value }, set: { box.value = $0 }),
                tasks: model)
        }
    }

    private enum AppearanceCase {
        case light, dark

        var scheme: ColorScheme {
            switch self {
            case .light: .light
            case .dark: .dark
            }
        }

        var name: NSAppearance.Name {
            switch self {
            case .light: .aqua
            case .dark: .darkAqua
            }
        }
    }

    private struct SelectionSwatches: View {
        var scheme: ColorScheme
        static let size = CGSize(width: 220, height: 88)

        var body: some View {
            VStack(spacing: 0) {
                InkListSelectionBackground(isSelected: true)
                    .frame(width: Self.size.width, height: 48)
                HStack(spacing: 0) {
                    swatch(InkListSelectionChrome.fillColor)
                    swatch(InkListSelectionChrome.markColor)
                    swatch(Color.ink.paper)
                    swatch(Color.ink.accent)
                    ForEach(InkListSelectionChrome.textTokens, id: \.rawValue) { token in
                        swatch(Color(token.assetName))
                    }
                }
                .frame(width: Self.size.width, height: 40, alignment: .leading)
            }
            .frame(width: Self.size.width, height: Self.size.height)
            .environment(\.colorScheme, scheme)
        }

        private func swatch(_ color: Color) -> some View {
            color.frame(width: 20, height: 40)
        }
    }

    private struct SheetSelectionProbe: View {
        var body: some View {
            List {
                Text(verbatim: "Her gün")
                    .inkListRow()
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.inkColumnRowSelected, true)
            .frame(width: 280, height: 160)
            .background(Color.ink.paper)
        }
    }

    private enum SwatchKind: Equatable {
        case fill, mark, paper, accent, text
    }

    private struct SwatchSet {
        var fill: SampledRGB
        var mark: SampledRGB
        var paper: SampledRGB
        var accent: SampledRGB
        var text: [InkPalette.Token: SampledRGB]

        func kind(of color: SampledRGB) -> SwatchKind {
            let pairs: [(SwatchKind, SampledRGB)] = [
                (.fill, fill), (.mark, mark), (.paper, paper), (.accent, accent),
            ]
            return pairs.min { color.distance(to: $0.1) < color.distance(to: $1.1) }?.0 ?? .paper
        }
    }

    extension SelectionSwatches {
        fileprivate static func samples(in bitmap: SelectionBitmap) -> SwatchSet {
            func at(_ index: Int) -> SampledRGB {
                bitmap.color(x: index * 20 + 8, y: 68) ?? SampledRGB(r: 0, g: 0, b: 0)
            }
            var text: [InkPalette.Token: SampledRGB] = [:]
            for (offset, token) in InkListSelectionChrome.textTokens.enumerated() {
                text[token] = at(4 + offset)
            }
            return SwatchSet(fill: at(0), mark: at(1), paper: at(2), accent: at(3), text: text)
        }
    }

    extension SampledRGB {
        fileprivate func nearest(among swatches: SwatchSet) -> SwatchKind {
            swatches.kind(of: self)
        }
    }

    struct SampledRGB: Equatable {
        var r: CGFloat
        var g: CGFloat
        var b: CGFloat

        var hex: UInt32 {
            let red = UInt32((Double(r) * 255).rounded())
            let green = UInt32((Double(g) * 255).rounded())
            let blue = UInt32((Double(b) * 255).rounded())
            return (red << 16) | (green << 8) | blue
        }

        func distance(to other: SampledRGB) -> CGFloat {
            max(abs(r - other.r), abs(g - other.g), abs(b - other.b))
        }
    }

    struct SelectionBitmap {
        let rep: NSBitmapImageRep

        func color(x: Int, y: Int) -> SampledRGB? {
            guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh, let color = rep.colorAt(x: x, y: y) else {
                return nil
            }
            let converted = color.usingColorSpace(.sRGB) ?? color
            return SampledRGB(
                r: converted.redComponent, g: converted.greenComponent, b: converted.blueComponent)
        }

        @MainActor
        static func render<V: View>(
            _ view: V, size: CGSize, appearance: NSAppearance.Name = .aqua
        ) async throws -> SelectionBitmap {
            let host = NSHostingView(rootView: view.environment(\.locale, Locale(identifier: "tr_TR")))
            host.appearance = NSAppearance(named: appearance)
            host.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(
                contentRect: NSRect(x: -20_000, y: -20_000, width: size.width, height: size.height),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            for _ in 0..<6 {
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(20))
                host.layoutSubtreeIfNeeded()
            }
            guard
                let rep = NSBitmapImageRep(
                    bitmapDataPlanes: nil,
                    pixelsWide: Int(size.width),
                    pixelsHigh: Int(size.height),
                    bitsPerSample: 8,
                    samplesPerPixel: 4,
                    hasAlpha: true,
                    isPlanar: false,
                    colorSpaceName: .deviceRGB,
                    bytesPerRow: 0,
                    bitsPerPixel: 0)
            else {
                window.contentView = nil
                throw SelectionBitmapError.unreadable
            }
            rep.size = size
            host.cacheDisplay(in: host.bounds, to: rep)
            window.contentView = nil
            return SelectionBitmap(rep: rep)
        }

        @MainActor
        static func fillSwatch() async throws -> SampledRGB {
            let bitmap = try await render(
                InkListSelectionBackground(isSelected: true).frame(width: 80, height: 40),
                size: CGSize(width: 80, height: 40))
            return try #require(bitmap.color(x: 40, y: 20))
        }

        static func wellCount(in bitmap: SelectionBitmap, yRange: Range<Int>, fill: SampledRGB) -> Int {
            var count = 0
            for y in yRange {
                for x in 0..<bitmap.rep.pixelsWide {
                    guard let color = bitmap.color(x: x, y: y) else { continue }
                    if color.distance(to: fill) < 0.04 { count += 1 }
                }
            }
            return count
        }
    }

    private enum SelectionBitmapError: Error { case unreadable }

    private struct RowHeightKey: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    @MainActor
    private final class ClickCount {
        var value = 0
    }

    @MainActor @Observable
    private final class SelectionBox {
        var value: String?
    }

    private final class ClickWindow: NSWindow {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }

    @MainActor
    final class MacHost {
        private let window: ClickWindow
        private let host: NSHostingView<AnyView>

        init<V: View>(_ view: V, size: CGSize) {
            let hosting = NSHostingView(rootView: AnyView(view))
            hosting.frame = NSRect(origin: .zero, size: size)
            let window = ClickWindow(
                contentRect: NSRect(x: -20_000, y: -20_000, width: size.width, height: size.height),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.alphaValue = 0.01
            window.contentView = hosting
            self.window = window
            self.host = hosting
        }

        func settle() async {
            host.needsLayout = true
            host.layoutSubtreeIfNeeded()
            for _ in 0..<8 {
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(40))
                host.layoutSubtreeIfNeeded()
            }
        }

        /// Puts the nearly invisible window on the visible desktop so hit-testing works, then
        /// removes it. `point` is measured from the top-left of the hosted view.
        private func placeOnScreen() {
            guard let screen = NSScreen.main else { return }
            let visible = screen.visibleFrame
            window.setFrame(
                NSRect(
                    x: visible.maxX - window.frame.width - 4,
                    y: visible.minY + 4,
                    width: window.frame.width,
                    height: window.frame.height),
                display: true)
            window.makeKeyAndOrderFront(nil)
            window.displayIfNeeded()
        }

        private func windowPoint(for point: CGPoint) -> NSPoint {
            let local =
                host.isFlipped
                ? NSPoint(x: point.x, y: point.y)
                : NSPoint(x: point.x, y: host.bounds.height - point.y)
            return host.convert(local, to: nil)
        }

        func click(at point: CGPoint) {
            placeOnScreen()
            let windowPoint = windowPoint(for: point)
            func make(_ type: NSEvent.EventType) -> NSEvent {
                NSEvent.mouseEvent(
                    with: type, location: windowPoint, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil,
                    eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            NSApp.sendEvent(make(.leftMouseDown))
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            NSApp.sendEvent(make(.leftMouseUp))
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        func close() {
            window.orderOut(nil)
            window.contentView = nil
        }
    }
#endif
