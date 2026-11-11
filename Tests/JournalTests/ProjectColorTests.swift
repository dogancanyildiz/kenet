import SwiftUI
import Testing

@testable import Journal

@Suite struct ProjectColorTests {
    @Test func projectNamesMapToOneOfFourStableColors() {
        #expect(ProjectColor.index(for: "Kenet") == 0)
        #expect(ProjectColor.index(for: "Altyapı") == 1)
        #expect(ProjectColor.index(for: "Kenet") == ProjectColor.index(for: "Kenet"))
    }

    /// design.md palette order: accent, person, place, control (hash mod 4).
    @Test func paletteFollowsTheDesignOrder() {
        #expect(ProjectColor.color(for: "Kenet") == .ink.accent)
        #expect(ProjectColor.color(for: "İş") == .ink.person)
        #expect(ProjectColor.color(for: "Ev") == .ink.place)
        #expect(ProjectColor.color(for: "Ev işleri") == .ink.control)
    }

    /// Amber is the carried-over color; no project may be drawn in it (fark3).
    @Test func paletteNeverUsesTheWarningColor() {
        let names = ["İş", "Kenet", "Altyapı", "Ev", "Kitap", "mobil", "Ev işleri", "Okuma", "Sağlık", "Kişisel"]
        for name in names {
            #expect(ProjectColor.color(for: name) != .ink.warning)
        }
    }

    @Test func noProjectUsesControlColorSlot() {
        #expect(ProjectColor.color(for: nil) == .ink.control)
        #expect(ProjectColor.color(for: "") == .ink.control)
    }
}
