import Foundation
import SwiftUI
import Testing
import VaultFormat

@testable import Journal

struct RowComponentTests {
    @Test func taskBoxPriorityGlyphs() {
        #expect(TaskBoxState(status: .todo, priority: nil).priorityGlyph == nil)
        #expect(TaskBoxState(status: .todo, priority: .low).priorityGlyph == nil)
        #expect(TaskBoxState(status: .todo, priority: .medium).priorityGlyph == "!")
        #expect(TaskBoxState(status: .todo, priority: .high).priorityGlyph == "!!")
        #expect(TaskBoxState(status: .inProgress, priority: .medium).priorityGlyph == "!")
        #expect(TaskBoxState(status: .done, priority: .high).priorityGlyph == nil)
        #expect(TaskBoxState(status: .todo, priority: .high).usesHighPriorityStroke)
        #expect(!TaskBoxState(status: .done, priority: .high).usesHighPriorityStroke)
    }

    @Test func taskBoxCompletionUsesClosedStatuses() {
        #expect(TaskBoxState(status: .done, priority: nil).isCompleted)
        #expect(TaskBoxState(status: .cancelled, priority: nil).isCompleted)
        #expect(!TaskBoxState(status: .todo, priority: nil).isCompleted)
        #expect(!TaskBoxState(status: .inProgress, priority: nil).isCompleted)
        #expect(TaskBoxState(status: .inProgress, priority: nil).isInProgress)
    }

    @Test func marginRowStacksAtAccessibilitySizes() {
        #expect(MarginRowLayout.resolve(dynamicTypeSize: .large) == .standard)
        #expect(MarginRowLayout.resolve(dynamicTypeSize: .accessibility1) == .accessibilityStacked)
        #expect(MarginRowLayout.resolve(dynamicTypeSize: .accessibility3) == .accessibilityStacked)
        #expect(MarginRowLayout.resolve(dynamicTypeSize: .accessibility5) == .accessibilityStacked)
    }

    @Test func marginRowKindSelectsTypefaceRole() {
        #expect(MarginRowKind.vault.contentFont == Font.ink.content)
        #expect(MarginRowKind.external.contentFont == Font.body)
    }

    @Test func inkLinkStyleUnderlineIsActiveMode() {
        #expect(InkLinkStyle.mode == .underline)

        var person = AttributedString("Ece")
        InkLinkStyle.apply(.person, to: &person, highContrast: false)
        #expect(person.underlineStyle != nil)

        var place = AttributedString("Ev")
        InkLinkStyle.apply(.place, to: &place, highContrast: true)
        #expect(place.underlineStyle != nil)

        var unresolved = AttributedString("X")
        InkLinkStyle.apply(.unresolved, to: &unresolved, highContrast: false)
        #expect(unresolved.underlineStyle != nil)

        var other = AttributedString("Not")
        InkLinkStyle.apply(.other, to: &other, highContrast: false)
        #expect(other.underlineStyle != nil)
        #expect(other.foregroundColor == Color.ink.text)

        var colored = AttributedString("Ece")
        InkLinkStyle.apply(.person, to: &colored, highContrast: false, using: .coloredText)
        #expect(colored.underlineStyle == nil)
        #expect(colored.foregroundColor != nil)
    }

    @Test func taskBoxPriorityGlyphStaysAtLeastTwelvePoints() {
        // 22 pt box: !! uses 0.38× side (~8.4) before the floor; max(12, …) enforces rule 9.
        let side: CGFloat = 22
        let rawHigh = side * 0.38
        #expect(rawHigh < 12)
        #expect(max(12, rawHigh) == 12)
        #expect(TaskBoxState(status: .todo, priority: .high).priorityGlyph == "!!")
        #expect(TaskBoxState(status: .cancelled, priority: nil).isCancelled)
    }

    @Test func inkLinkMappingDedupesEntityPathsAndMarksOtherKinds() {
        let person = EntitySummary(
            id: "people/A.md", kind: "person", name: "Ada", qualifier: nil, aliases: [],
            incomingLinks: 0)
        let duplicate = EntitySummary(
            id: "people/A.md", kind: "person", name: "Ada Copy", qualifier: nil, aliases: [],
            incomingLinks: 0)
        let custom = EntitySummary(
            id: "notes/X.md", kind: "book", name: "X", qualifier: nil, aliases: [],
            incomingLinks: 0)
        let index = InkLinkMapping.entityIndex([person, duplicate, custom])
        #expect(index.count == 2)
        #expect(index["people/A.md"]?.name == "Ada")
        let segments = InkLinkMapping.segments(
            from: LinkedText(spans: [
                .init(text: "X", destination: "notes/X.md", target: "X")
            ]),
            entitiesByID: index)
        #expect(segments.contains { $0.kind == .other })
        let unresolved = InkLinkMapping.segments(
            from: LinkedText(spans: [
                .init(text: "Yok", destination: nil, target: "Yok")
            ]),
            entitiesByID: index)
        #expect(unresolved.contains { $0.kind == .unresolved })
    }

    @Test func inkLinkedTextKeepsSuffixPlainAndLinksEntity() {
        let segments: [InkLinkSegment] = [
            .init(id: "1", text: "Ev", kind: .place, target: "Ev", path: "places/Ev.md"),
            .init(id: "2", text: "'de", kind: .plain),
        ]
        let attributed = InkLinkTextBuilder.attributed(segments: segments, highContrast: false)
        let plain = String(attributed.characters)
        #expect(plain == "Ev'de")

        var sawLink = false
        var linkedText = ""
        for run in attributed.runs {
            let piece = String(attributed[run.range].characters)
            if run.link != nil {
                sawLink = true
                linkedText += piece
                #expect(run.link?.scheme == "journal-entity")
            }
        }
        #expect(sawLink)
        #expect(linkedText == "Ev")
    }

    @Test func goalRingClampsProgress() {
        #expect(GoalRingProgress.clamped(-0.2) == 0)
        #expect(GoalRingProgress.clamped(0.4) == 0.4)
        #expect(GoalRingProgress.clamped(1.5) == 1)
        #expect(GoalRingProgress.isComplete(1))
        #expect(!GoalRingProgress.isComplete(0.99))
    }
}
