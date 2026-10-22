import SwiftUI
import Testing

@testable import Journal

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// The manşet row of a page in a Mac window column stays above the content that scrolls under
/// it (the opaque window toolbar hid a manşet that scrolled away, and its icons with it); on
/// iPhone and iPad it scrolls with the page as before. Measured on a page laid out by the real
/// pattern (``InkScrolledMasthead`` + `inkPinnedMasthead`), scrolled by its scroll view.
@MainActor @Suite(.serialized, .timeLimit(.minutes(1)))
struct PinnedMastheadTests {
    #if os(macOS)
        private let watchdog = HostedTestWatchdog()
    #endif

    @Test func ruleShowsOnlyOnceTheContentHasMovedUnderTheStrip() {
        // At rest the offset is minus the top inset (the strip is part of that inset).
        #expect(!InkPinnedMastheadChrome.showsRule(offset: -64, topInset: 64))
        // Pulled down past the top (elastic scrolling): still at rest as far as the rule goes.
        #expect(!InkPinnedMastheadChrome.showsRule(offset: -90, topInset: 64))
        #expect(InkPinnedMastheadChrome.showsRule(offset: -63, topInset: 64))
        #expect(InkPinnedMastheadChrome.showsRule(offset: 300, topInset: 64))
    }

    /// The platform's own placement (no override): pinned in the Mac window, scrolled away on
    /// iPhone and iPad.
    @Test func manşetFollowsThePlatformPlacementWhenThePageScrolls() async throws {
        let page = try await ScrolledProbePage.measure(placement: nil)
        #if os(macOS)
            expectPinned(page)
        #else
            expectScrolledAway(page)
        #endif
    }

    #if os(macOS)
        @Test func pinnedManşetStaysUnderTheTopEdge() async throws {
            expectPinned(try await ScrolledProbePage.measure(placement: .pinned))
        }

        /// The other placement on the same page: the manşet leaves with the content, as on iOS.
        @Test func scrolledManşetLeavesWithTheContent() async throws {
            expectScrolledAway(try await ScrolledProbePage.measure(placement: .scrolled))
        }

        /// Scrolled 300 pt in a 400 pt tall column: the manşet's icon is still inside the visible
        /// column and a press on it reaches its action.
        @Test func pinnedIconStaysVisibleAndPressable() async throws {
            let probe = ScrolledProbePage.Probe()
            let mount = HostedLayout.Mount(
                ScrolledProbePage(probe: probe).environment(\.locale, Locale(identifier: "tr_TR")),
                size: ScrolledProbePage.size)
            defer { mount.close() }
            await mount.settle()
            let scroll = try #require(mount.views(NSScrollView.self).first, "the page has no scroll view")
            ScrolledProbePage.scroll(scroll, by: ScrolledProbePage.distance)
            await mount.settle()
            guard
                await HostedControls.isAvailable(
                    mount, until: { HostedControls.node(ScrolledProbePage.actionID, in: mount) != nil })
            else { return }
            let icon = try #require(HostedControls.node(ScrolledProbePage.actionID, in: mount))
            let visible = mount.window.convertToScreen(scroll.convert(scroll.bounds, to: nil))
            #expect(visible.contains(icon.frame.insetBy(dx: 1, dy: 1)), "icon \(icon.frame), column \(visible)")
            icon.press()
            await mount.settle(rounds: 2)
            #expect(probe.presses == 1, "the press did not reach the icon's action")
        }
    #endif

    private func expectPinned(_ page: ScrolledProbePage.Measure) {
        #expect(page.scrolledBy > 200, "the page did not scroll: \(page)")
        #expect(abs(page.after.minY - page.before.minY) < 1, "the manşet moved: \(page)")
        #expect(page.after.minY >= 0, "the manşet left the top edge: \(page)")
    }

    private func expectScrolledAway(_ page: ScrolledProbePage.Measure) {
        #expect(page.scrolledBy > 200, "the page did not scroll: \(page)")
        #expect(page.after.minY < page.before.minY - 200, "the manşet stayed: \(page)")
    }
}

/// A page built like the app's `ScrollView` pages: the manşet (with one icon) defined once,
/// its slot first in the scrolled stack, the pinned strip on the scroll view.
private struct ScrolledProbePage: View {
    static let size = CGSize(width: 480, height: 400)
    static let distance: CGFloat = 300
    static let actionID = "probe.manset.add"

    @MainActor final class Probe {
        /// The icon's frame in the window (points, top-left origin).
        var frame: CGRect = .zero
        var presses = 0
    }

    struct Measure: CustomStringConvertible {
        let before: CGRect
        let after: CGRect
        let scrolledBy: CGFloat
        var description: String { "before \(before), after \(after), scrolled \(scrolledBy)" }
    }

    let probe: Probe

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                InkScrolledMasthead(masthead)
                ForEach(0..<40, id: \.self) { row in
                    Text(verbatim: "Satır \(row)")
                        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                        .padding(.horizontal, InkSpacing.margin)
                }
            }
        }
        .inkPinnedMasthead(masthead, spacing: 12)
        .inkPage()
    }

    private var masthead: InkPageTitle<some View> {
        InkPageTitle(verbatim: "Sayfa") {
            InkHeaderAction("Ekle", systemImage: "plus", role: .primary, identifier: Self.actionID) {
                probe.presses += 1
            }
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .global)
            } action: {
                probe.frame = $0
            }
        }
    }

    /// Lays the page out (`placement` nil: the platform's own), scrolls it by ``distance`` and
    /// reports where the icon was before and after.
    @MainActor static func measure(placement: InkMastheadPlacement?) async throws -> Measure {
        let probe = Probe()
        let page = ScrolledProbePage(probe: probe)
        #if os(macOS)
            let view = Group {
                if let placement { page.environment(\.inkMastheadPlacement, placement) } else { page }
            }
            let mount = HostedLayout.Mount(view, size: size)
            defer { mount.close() }
            await mount.settle()
            let before = probe.frame
            let scroll = try #require(mount.views(NSScrollView.self).first, "the page has no scroll view")
            let start = scroll.contentView.bounds.minY
            Self.scroll(scroll, by: distance)
            await mount.settle()
            return Measure(before: before, after: probe.frame, scrolledBy: scroll.contentView.bounds.minY - start)
        #else
            #expect(placement == nil, "iOS draws its own placement only")
            var measure: Measure?
            var failure: (any Error)?
            await SnapshotHostGate.exclusive {
                let host = UIHostingController(rootView: page)
                guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
                else {
                    Issue.record("The page needs a UIWindowScene (run under the Journal test host).")
                    return
                }
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(origin: .zero, size: size)
                window.rootViewController = host
                window.isHidden = false
                defer {
                    window.isHidden = true
                    window.rootViewController = nil
                    window.windowScene = nil
                }
                await settle(host.view)
                let before = probe.frame
                do {
                    let scroll = try #require(Self.firstScrollView(in: host.view), "the page has no scroll view")
                    let start = scroll.contentOffset.y
                    scroll.setContentOffset(CGPoint(x: 0, y: start + distance), animated: false)
                    await settle(host.view)
                    measure = Measure(before: before, after: probe.frame, scrolledBy: scroll.contentOffset.y - start)
                } catch {
                    failure = error
                }
            }
            if let failure { throw failure }
            return try #require(measure)
        #endif
    }

    #if os(macOS)
        /// Moves the scroll view's content up by `distance` the way the wheel does (the clip view).
        @MainActor static func scroll(_ scroll: NSScrollView, by distance: CGFloat) {
            let clip = scroll.contentView
            clip.scroll(to: NSPoint(x: clip.bounds.minX, y: clip.bounds.minY + distance))
            scroll.reflectScrolledClipView(clip)
        }
    #else
        @MainActor static func firstScrollView(in view: UIView) -> UIScrollView? {
            if let scroll = view as? UIScrollView { return scroll }
            for child in view.subviews {
                if let found = firstScrollView(in: child) { return found }
            }
            return nil
        }

        @MainActor static func settle(_ view: UIView) async {
            for _ in 0..<8 {
                view.setNeedsLayout()
                view.layoutIfNeeded()
                await Task.yield()
                // Frame pump: SwiftUI lays out on a later run-loop turn and reports no event to await.
                try? await Task.sleep(for: .milliseconds(30))
            }
        }
    #endif
}
