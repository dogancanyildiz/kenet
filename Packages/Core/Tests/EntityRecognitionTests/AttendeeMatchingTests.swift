import EntityRecognition
import Foundation
import Testing

private struct AttendeeFixture: Decodable {
    struct Item: Decodable {
        let name: String
        let isCurrentUser: Bool
    }
    let attendees: [Item]
}

private struct ExpectedAttendees: Codable, Equatable {
    struct Certain: Codable, Equatable {
        let spelling: String
        let file: String
    }
    struct Ambiguous: Codable, Equatable {
        let spelling: String
        let candidates: [String]
    }
    let certain: [Certain]
    let ambiguous: [Ambiguous]
    let unknown: [String]
}

@Test func attendeeFixture() throws {
    let root = try fixtureRoot().appendingPathComponent("recognition/attendees")
    let entities = try JSONDecoder().decode(
        RecognitionFixture.self, from: Data(contentsOf: root.appendingPathComponent("entities.json"))
    ).entities.map(\.value)
    let attendees = try JSONDecoder().decode(
        AttendeeFixture.self, from: Data(contentsOf: root.appendingPathComponent("attendees.json"))
    ).attendees.map { Attendee(name: $0.name, isCurrentUser: $0.isCurrentUser) }
    let match = AttendeeMatching.match(attendees, entities: entities)
    let actual = ExpectedAttendees(
        certain: match.certain.map { .init(spelling: $0.spelling, file: $0.entity.file) },
        ambiguous: match.ambiguous.map { .init(spelling: $0.spelling, candidates: $0.candidates.map(\.file)) },
        unknown: match.unknown)
    let expected = try JSONDecoder().decode(
        ExpectedAttendees.self, from: Data(contentsOf: root.appendingPathComponent("expected.json")))
    #expect(actual == expected)
    // Canonically equal spellings compare equal; the bytes show which side's spelling was kept.
    for (item, wanted) in zip(actual.certain, expected.certain) {
        #expect(Array(item.spelling.utf8) == Array(wanted.spelling.utf8))
    }
}

@Test func attendeesWithoutEntitiesAreAllUnknown() {
    let match = AttendeeMatching.match([Attendee(name: "Deniz Arıkan"), Attendee(name: "Deniz Arıkan")], entities: [])
    #expect(match.certain.isEmpty && match.ambiguous.isEmpty)
    #expect(match.unknown == ["Deniz Arıkan"])
}
