import Testing

@testable import Journal

@Suite struct InkCardSegmentTests {
    @Test func rowsOfASectionCardRoundOnlyItsEnds() {
        #expect(InkCardSegment.position(0, of: 1) == .single)
        #expect((0..<3).map { InkCardSegment.position($0, of: 3) } == [.first, .middle, .last])
        #expect((0..<2).map { InkCardSegment.position($0, of: 2) } == [.first, .last])
        #expect(InkCardSegment.single.roundsTop && InkCardSegment.single.roundsBottom)
        #expect(!InkCardSegment.middle.roundsTop && !InkCardSegment.middle.roundsBottom)
    }

    /// Gün and Hafta boards have no groups, so the Mac manşet hides "Grupla" there.
    @Test func onlyTheBarChartScalesShowGrouping() {
        #expect(TimelineModel.Scale.allCases.filter(\.showsGrouping) == [.month, .quarter])
    }
}
