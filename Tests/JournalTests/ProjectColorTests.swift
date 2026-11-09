import SwiftUI
import Testing

@testable import Journal

@Suite struct ProjectColorTests {
    @Test func projectNamesMapToOneOfFiveStableColors() {
        #expect(ProjectColor.index(for: "Kenet") == 1)
        #expect(ProjectColor.index(for: "Altyapı") == 2)
        #expect(ProjectColor.index(for: "Kenet") == ProjectColor.index(for: "Kenet"))
    }

    /// design.md palette order: accent, person, place, warning, control (hash mod 5).
    @Test func paletteFollowsTheDesignOrder() {
        #expect(ProjectColor.color(for: "İş") == .ink.accent)
        #expect(ProjectColor.color(for: "Kenet") == .ink.person)
        #expect(ProjectColor.color(for: "Altyapı") == .ink.place)
        #expect(ProjectColor.color(for: "Ev") == .ink.warning)
        #expect(ProjectColor.color(for: "Kitap") == .ink.control)
    }

    @Test func noProjectUsesControlColorSlot() {
        #expect(ProjectColor.color(for: nil) == .ink.control)
        #expect(ProjectColor.color(for: "") == .ink.control)
    }
}
