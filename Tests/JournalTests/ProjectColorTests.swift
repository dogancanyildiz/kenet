import SwiftUI
import Testing

@testable import Journal

@Suite struct ProjectColorTests {
    @Test func projectNamesMapToOneOfFiveStableColors() {
        #expect(ProjectColor.index(for: "Kenet") == 1)
        #expect(ProjectColor.index(for: "Altyapı") == 2)
        #expect(ProjectColor.index(for: "Kenet") == ProjectColor.index(for: "Kenet"))
    }

    @Test func noProjectUsesControlColorSlot() {
        #expect(ProjectColor.color(for: nil) == .ink.control)
        #expect(ProjectColor.color(for: "") == .ink.control)
    }
}
