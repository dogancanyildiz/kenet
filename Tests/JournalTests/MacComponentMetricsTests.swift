import SwiftUI
import Testing

@testable import Journal

/// Kip-word spacing is a layout decision: iPhone's 44 pt frames make the gap, Mac does not
/// grow those frames, so Mac uses the same 12 pt gap the accessibility row already uses.
struct QuickEntryWordSpacingTests {
    @Test func stackSpacingFollowsWhetherTapFramesSeparateTheWords() {
        #if os(macOS)
            #expect(
                QuickEntryCapsuleLayout.stackSpacing(for: .singleRow)
                    == QuickEntryCapsuleLayout.visualWordGap)
            #expect(
                QuickEntryCapsuleLayout.stackSpacing(for: .stacked)
                    == QuickEntryCapsuleLayout.visualWordGap)
        #else
            // iPhone single row stays at the tight frame gap. Raising it would widen the capsule.
            #expect(QuickEntryCapsuleLayout.stackSpacing(for: .singleRow) == 2)
            #expect(QuickEntryCapsuleLayout.stackSpacing(for: .stacked) == 12)
            #expect(
                QuickEntryCapsuleLayout.stackSpacing(for: .singleRow)
                    < QuickEntryCapsuleLayout.stackSpacing(for: .stacked))
        #endif
    }
}

#if os(macOS)
    import AppKit

    /// Hosted frames for the two Mac findings: kip-word gap, and manşet icon size / hit target.
    @MainActor
    struct MacComponentMetricsTests {
        @Test func quickEntryModeWordsSitAVisualGapApart() async throws {
            let mount = HostedLayout.Mount(
                QuickEntryMetricsProbe(dynamicTypeSize: .large),
                size: CGSize(width: 640, height: 80))
            defer { mount.close() }
            await mount.settle()
            let gap = try Self.modeWordGap(in: mount)
            // Audit: iPhone ~12 pt, Mac was ~3 pt. The floor is below the token and above the old gap.
            #expect(gap >= 10, "Olay–Görev gap \(gap) pt")
            #expect(
                abs(gap - QuickEntryCapsuleLayout.visualWordGap) <= 2,
                "Olay–Görev gap \(gap) pt, token \(QuickEntryCapsuleLayout.visualWordGap)")
        }

        @Test func quickEntryModeWordsKeepTheGapWhenStacked() async throws {
            let mount = HostedLayout.Mount(
                QuickEntryMetricsProbe(dynamicTypeSize: .accessibility1),
                size: CGSize(width: 640, height: 160))
            defer { mount.close() }
            await mount.settle()
            let gap = try Self.modeWordGap(in: mount)
            #expect(gap >= 10, "stacked Olay–Görev gap \(gap) pt")
            #expect(abs(gap - QuickEntryCapsuleLayout.visualWordGap) <= 2, "stacked gap \(gap) pt")
        }

        /// The three icon kinds on one manşet (button, menu, plain system button) share one hit size.
        @Test func headerIconsShareAPointerTargetAndAReadableSymbol() async throws {
            let mount = HostedLayout.Mount(
                HeaderMetricsProbe(), size: CGSize(width: 640, height: 80))
            defer { mount.close() }
            await mount.settle()
            let root = mount.window.contentView ?? NSView()
            let rings = Self.pointerTargets(in: root)
            #expect(rings.count == 3, "pointer targets \(rings)")
            guard rings.count == 3 else { return }
            for ring in rings {
                #expect(ring.width >= 28, "target width \(ring.width)")
                #expect(ring.height >= 28, "target height \(ring.height)")
                let ink = Self.symbolInk(inside: ring, root: root)
                let longer = max(ink.width, ink.height)
                #expect(longer >= 15, "symbol ink \(ink) pt; the old glyph was about 12 pt")
                #expect(
                    ink.width <= ring.width + 0.5 && ink.height <= ring.height + 0.5,
                    "ink \(ink) outside the \(ring.width)×\(ring.height) pt target")
            }
            for pair in zip(rings, rings.dropFirst()) {
                let gap = pair.1.minX - pair.0.maxX
                #expect(abs(gap - InkHeaderActionChrome.spacing) <= 1, "target gap \(gap) pt")
                let left = Self.symbolInk(inside: pair.0, root: root)
                let right = Self.symbolInk(inside: pair.1, root: root)
                let air =
                    (pair.0.width - left.width) / 2 + gap + (pair.1.width - right.width) / 2
                #expect(air >= 12, "visual gap \(air) pt")
            }
            let heights = rings.map(\.height)
            #expect(heights.max()! - heights.min()! <= 1, "icon targets differ: \(heights)")
        }

        /// The list column at its narrowest (280 pt). Two manşet icons, one more than Görevler
        /// and Hedefler show there, must not paint over the title.
        @Test func headerIconsLeaveTheTitleClearInTheListColumn() async {
            let mount = HostedLayout.Mount(
                NarrowHeaderProbe(), size: CGSize(width: InkSpacing.macListMinWidth, height: 120))
            defer { mount.close() }
            await mount.settle()
            let root = mount.window.contentView ?? NSView()
            let rings = Self.pointerTargets(in: root)
            #expect(rings.count == 2, "list-column targets \(rings)")
            guard let firstIcon = rings.first, let title = Self.titleInk(in: root) else { return }
            #expect(
                title.maxX <= firstIcon.minX + 0.5,
                "title ends at \(title.maxX) pt, first icon starts at \(firstIcon.minX) pt")
        }

        /// Mac search lives in the window toolbar: the manşet row shows no magnifier, and the
        /// same button outside a manşet row (the toolbar) is still drawn.
        @Test func headerRowDrawsNoSearchButTheBareButtonStillDraws() async {
            let header = HostedLayout.Mount(SearchSlotProbe(inHeader: true), size: CGSize(width: 640, height: 80))
            defer { header.close() }
            await header.settle()
            let inHeader = Self.pointerTargets(in: header.window.contentView ?? NSView())
            #expect(inHeader.count == 1, "manşet targets \(inHeader): only the screen's own icon")

            let bare = HostedLayout.Mount(SearchSlotProbe(inHeader: false), size: CGSize(width: 640, height: 80))
            defer { bare.close() }
            await bare.settle()
            let outside = Self.pointerTargets(in: bare.window.contentView ?? NSView())
            #expect(outside.count == 2, "targets outside a manşet \(outside): the icon and search")
        }

        private static func modeWordGap(in mount: HostedLayout.Mount) throws -> CGFloat {
            let root = mount.window.contentView ?? NSView()
            let words = Self.wordFrames(in: root)
            #expect(words.count >= 2, "mode-word frames \(words)")
            let pair = try #require(words.count >= 2 ? Array(words.prefix(2)) : nil)
            return pair[1].minX - pair[0].maxX
        }

        /// Kip words are the short controls on one row (the send control is the tall one).
        private static func wordFrames(in root: NSView) -> [CGRect] {
            let boxes = Self.subviewFrames(in: root).filter { $0.height < 24 && $0.width < 80 }
            guard let row = boxes.map(\.midY).max() else { return [] }
            return boxes.filter { abs($0.midY - row) <= 4 }.sorted { $0.minX < $1.minX }
        }

        /// Manşet pointer targets: the controls SwiftUI actually built, large enough to click.
        private static func pointerTargets(in root: NSView) -> [CGRect] {
            Self.subviewFrames(in: root)
                .filter { $0.width >= 20 && $0.height >= 20 }
                .sorted { $0.minX < $1.minX }
        }

        private static func subviewFrames(in root: NSView) -> [CGRect] {
            var frames: [CGRect] = []
            func walk(_ view: NSView) {
                if view !== root {
                    let box = view.convert(view.bounds, to: root)
                    if box.width > 1, box.height > 1 { frames.append(box) }
                }
                view.subviews.forEach(walk)
            }
            walk(root)
            return frames
        }

        /// Symbol drawing that sits inside one pointer target, in the host's coordinates.
        private static func symbolInk(inside ring: CGRect, root: NSView) -> CGRect {
            let inside = Self.layerFrames(in: root).filter { frame in
                ring.insetBy(dx: 1, dy: 1).contains(CGPoint(x: frame.midX, y: frame.midY))
                    && frame.width < ring.width - 1
                    && frame.height < ring.height - 1
                    && frame.width > 4
                    && frame.height > 4
            }
            guard let seed = inside.max(by: { $0.width * $0.height < $1.width * $1.height }) else {
                return .zero
            }
            return inside.reduce(seed) { $0.union($1) }
        }

        /// The manşet's drawn title: the glyph block on the leading edge, not the page fill.
        /// The page margin (16 pt) insets it, so the leading edge is not zero.
        private static func titleInk(in root: NSView) -> CGRect? {
            let limit = root.bounds.width
            return Self.layerFrames(in: root)
                .filter { frame in
                    frame.minX < 40 && frame.width > 40 && frame.width < limit - 24
                        && frame.height > 16 && frame.height < 80
                }
                .max { $0.width * $0.height < $1.width * $1.height }
        }

        private static func layerFrames(in root: NSView) -> [CGRect] {
            guard let rootLayer = root.layer else { return [] }
            var frames: [CGRect] = []
            func walk(_ layer: CALayer) {
                let box = layer.convert(layer.bounds, to: rootLayer)
                if box.width > 1, box.height > 1 { frames.append(box) }
                layer.sublayers?.forEach(walk)
            }
            walk(rootLayer)
            return frames
        }
    }

    private struct QuickEntryMetricsProbe: View {
        var dynamicTypeSize: DynamicTypeSize
        @State private var mode = QuickEntryMode.event

        var body: some View {
            QuickEntryCapsule(mode: $mode, canSubmit: false, onSubmit: {}) {
                Text(verbatim: "alan")
            }
            .environment(\.locale, Locale(identifier: "tr_TR"))
            .environment(\.dynamicTypeSize, dynamicTypeSize)
            .frame(width: 640)
        }
    }

    private struct HeaderMetricsProbe: View {
        var body: some View {
            InkPageHeader(verbatim: "Görevler") {
                InkHeaderAction("Pano seçenekleri", systemImage: "slider.horizontal.3") {}
                InkHeaderMenu("Filtre", systemImage: "line.3.horizontal.decrease") {
                    Button("Hiçbiri") {}
                }
                // A bare system button, styled by the slot alone (what search is on iPhone).
                Button("Yenile", systemImage: "arrow.clockwise") {}
                    .labelStyle(.iconOnly)
            }
            .environment(\.locale, Locale(identifier: "tr_TR"))
            .frame(width: 640, alignment: .leading)
        }
    }

    /// Görevler / Hedefler in the narrowest list column: page margin, then two icons.
    private struct NarrowHeaderProbe: View {
        var body: some View {
            InkPageHeader(verbatim: "Görevler") {
                InkHeaderAction("Yeni hedef", systemImage: "plus", role: .primary) {}
                InkHeaderMenu("Filtre", systemImage: "line.3.horizontal.decrease") {
                    Button("Hiçbiri") {}
                }
            }
            .padding(.horizontal, InkSpacing.margin)
            .environment(\.locale, Locale(identifier: "tr_TR"))
            .frame(width: InkSpacing.macListMinWidth, alignment: .leading)
        }
    }

    /// One screen icon and search, inside a manşet row or loose (as a toolbar holds it).
    private struct SearchSlotProbe: View {
        var inHeader: Bool

        var body: some View {
            Group {
                if inHeader {
                    InkPageHeader(verbatim: "Görevler") {
                        InkHeaderAction("Pano seçenekleri", systemImage: "slider.horizontal.3") {}
                        SearchButton()
                    }
                } else {
                    HStack {
                        InkHeaderAction("Pano seçenekleri", systemImage: "slider.horizontal.3") {}
                        SearchButton()
                    }
                }
            }
            .environment(\.openSearch, {})
            .environment(\.locale, Locale(identifier: "tr_TR"))
            .frame(width: 640, alignment: .leading)
        }
    }
#endif
