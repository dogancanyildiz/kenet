import Foundation
import GoalTracking
import SwiftUI
import Testing
import VaultFormat

@testable import Journal

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Touch targets on iPhone must be at least 44×44 pt (HIG); the Mac pointer keeps the drawn size.
/// Measured on the laid-out views. Where the modifier sits on a button (its label, not outside
/// it) is a placement rule in `SourcePatternRuleTests`.
@MainActor struct TapTargetTests {
    /// iPhone: anything smaller grows to 44 × 44 pt, and the floor stays fixed at the largest
    /// text size (a scaled metric would pass 100 pt at AX5). Mac: no change.
    @Test func tapTargetIsAFixedFortyFourPointFloorOnTouchOnly() {
        let dot = Color.clear.frame(width: 4, height: 4).tapTarget()
        for size in [DynamicTypeSize.large, .accessibility5] {
            let measured = Self.fittingSize(dot.dynamicTypeSize(size))
            #if os(iOS)
                #expect(measured == CGSize(width: TapTarget.minimumLength, height: TapTarget.minimumLength), "\(size)")
            #else
                #expect(measured == CGSize(width: 4, height: 4), "\(size): the Mac pointer keeps the drawn size")
            #endif
        }
        #expect(TapTarget.minimumLength == 44)
        // Larger content keeps its own size.
        let wide = Self.fittingSize(Color.clear.frame(width: 120, height: 60).tapTarget())
        #expect(wide == CGSize(width: 120, height: 60))
    }

    /// The manşet icons keep the touch floor on iPhone (the button style and the menu put it on
    /// their label); the Mac keeps its pointer target.
    @Test func headerIconsKeepTheTouchFloor() {
        let icon = Self.fittingSize(
            Button {
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(InkHeaderButtonStyle()))
        let menu = Self.fittingSize(
            InkHeaderMenu("Sırala", systemImage: "arrow.up.arrow.down") { Button("Ada göre") {} })
        for size in [icon, menu] {
            #if os(iOS)
                #expect(size.width >= TapTarget.minimumLength && size.height >= TapTarget.minimumLength, "\(size)")
            #else
                let side = InkHeaderActionChrome.macMinimumSide
                #expect(size.width >= side && size.height >= side, "\(size)")
            #endif
        }
    }

    /// The heatmap stays a dense grid: each row is one cell plus its gap, never a 44 pt row that
    /// would spill into the next day.
    @Test func heatmapRowsAreOneGridStepNotATapFloor() throws {
        let goal = try #require(GoalDefinition(id: "a", key: "a", name: "Su", period: .day, kind: .boolean))
        let today = try #require(CalendarDate("2026-10-03"))
        let height = Self.fittingSize(
            GoalHeatmap(goal: goal, logs: [], today: today, select: { _ in }).frame(width: 358)
        )
        .height
        let cell = GoalHeatmapMetrics.cellSize(availableWidth: 358, weekCount: 12)
        let step = GoalHeatmapMetrics.step(cellSize: cell)
        #expect(GoalHeatmapMetrics.tapSize(cellSize: cell) == step, "a cell's tap frame is the grid step")
        #expect(height >= 7 * step, "seven weekday rows: \(height)")
        #expect(height < 7 * TapTarget.minimumLength, "rows at the 44 pt floor would overlap: \(height)")
    }

    @Test func quickEntryReflowsForLargeDynamicType() {
        #expect(QuickEntryCapsuleLayout.resolve(dynamicTypeSize: .large) == .singleRow)
        #expect(QuickEntryCapsuleLayout.resolve(dynamicTypeSize: .xxxLarge) == .singleRow)
        #expect(QuickEntryCapsuleLayout.resolve(dynamicTypeSize: .accessibility1) == .stacked)
        #expect(QuickEntryCapsuleLayout.resolve(dynamicTypeSize: .accessibility3) == .stacked)
        #expect(QuickEntryCapsuleLayout.resolve(dynamicTypeSize: .accessibility5) == .stacked)
        #expect(
            QuickEntryModeLock.isModeEnabled(
                isEnabled: true, isSubmitting: false, isCreating: false, isWriting: false))
        #expect(
            !QuickEntryModeLock.isModeEnabled(
                isEnabled: true, isSubmitting: true, isCreating: false, isWriting: false))
    }

    /// A finger gets the full 44 pt target around a small graph node; a pointer is precise.
    @Test func graphNodeTapRadiusFollowsThePlatform() {
        let nodes = [GraphNode(id: "a", name: "a", kind: .person, count: 1)]
        let points = [GraphPoint.zero]
        let size = CGSize(width: 300, height: 300)
        let viewport = GraphViewport(
            size: size, camera: GraphCamera(), zoom: 1 / GraphCamera().scale(in: size), pan: .zero)
        func tap(_ offset: CGFloat) -> Int? {
            viewport.nodeIndex(
                at: CGPoint(x: 150 + offset, y: 150), nodes: nodes, points: points,
                minimumRadius: GraphCanvas.minimumHitRadius)
        }
        #if os(iOS)
            #expect(GraphCanvas.minimumHitRadius * 2 >= Double(TapTarget.minimumLength))
            #expect(tap(TapTarget.minimumLength / 2 - 1) == 0, "inside the 44 pt target")
        #else
            #expect(tap(TapTarget.minimumLength / 2 - 1) == nil, "the pointer hits what is drawn")
        #endif
        #expect(tap(TapTarget.minimumLength) == nil)
    }

    private static func fittingSize(_ view: some View) -> CGSize {
        #if os(iOS)
            let host = UIHostingController(rootView: view)
            return host.sizeThatFits(in: CGSize(width: 2000, height: 2000))
        #else
            return NSHostingView(rootView: view).fittingSize
        #endif
    }
}
