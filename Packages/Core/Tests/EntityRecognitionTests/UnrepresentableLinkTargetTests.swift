import EntityRecognition
import Testing

struct UnrepresentableLinkTargetTests {
    @Test func forbiddenCharactersAreSharedConstant() {
        #expect(EntityRecognizer.unrepresentableLinkTargetCharacters == Set("\\:*?\"<>|#^[]\n\r"))
        #expect("notes/a:b".contains(where: { EntityRecognizer.unrepresentableLinkTargetCharacters.contains($0) }))
        #expect(!"notes/ok".contains(where: { EntityRecognizer.unrepresentableLinkTargetCharacters.contains($0) }))
    }
}
