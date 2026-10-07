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

        var entity = AttributedString("Cam")
        InkLinkStyle.apply(.other, to: &entity, highContrast: false)
        #expect(entity.underlineStyle != nil)

        var colored = AttributedString("Ece")
        InkLinkStyle.apply(.person, to: &colored, highContrast: false, using: .coloredText)
        #expect(colored.underlineStyle == nil)
        #expect(colored.foregroundColor != nil)
    }

    @Test func linkedTextInkDedupesPathsAndStylesCustomTypes() {
        let entities = [
            EntitySummary(
                id: "books/Cam.md", kind: "book", name: "Cam", qualifier: nil, aliases: [],
                incomingLinks: 1),
            EntitySummary(
                id: "books/Cam.md", kind: "book", name: "Cam kopya", qualifier: nil, aliases: [],
                incomingLinks: 0),
            EntitySummary(
                id: "people/Ada.md", kind: "person", name: "Ada", qualifier: nil, aliases: [],
                incomingLinks: 1),
        ]
        let text = LinkedText(spans: [
            .init(text: "Cam", destination: "books/Cam.md", target: "Cam"),
            .init(text: " ve ", destination: nil),
            .init(text: "Ada", destination: "people/Ada.md", target: "Ada"),
        ])
        let segments = LinkedTextInk.segments(text, entities: entities)
        #expect(segments.map(\.kind) == [.other, .plain, .person])
    }

    @Test func daysCalendarMarkDiameterCapsToCellWidth() {
        // AX3 scales the 32 pt base above a ~45 pt grid cell; the mark must shrink.
        let preferred: CGFloat = 32 * 1.8
        #expect(preferred > 45)
        #expect(DaysCalendarMarkLayout.markDiameter(preferred: preferred, cellWidth: 45) == 45)
        #expect(DaysCalendarMarkLayout.markDiameter(preferred: 32, cellWidth: 45) == 32)
        #expect(DaysCalendarMarkLayout.markDiameter(preferred: 40, cellWidth: 0) == 0)
    }

    @Test func mutedLinkedTextFadesPlainRunsAndKeepsLinkUnderline() {
        let segments: [InkLinkSegment] = [
            .init(id: "1", text: "Ara: ", kind: .plain),
            .init(id: "2", text: "Deniz", kind: .person, target: "Deniz", path: "people/Deniz.md"),
        ]
        let normal = InkLinkTextBuilder.attributed(segments: segments, highContrast: false)
        let muted = InkLinkTextBuilder.attributed(
            segments: segments, highContrast: false, isMuted: true)
        func plainColor(_ value: AttributedString) -> Color? {
            value.runs.first { $0.link == nil }?.foregroundColor
        }
        #expect(plainColor(normal) == Color.ink.text)
        #expect(plainColor(muted) == Color.ink.secondaryText)
        let link = muted.runs.first { $0.link != nil }
        #expect(link?.underlineStyle == Text.LineStyle(pattern: .solid, color: .ink.person))
        #expect(String(muted.characters) == String(normal.characters))
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
