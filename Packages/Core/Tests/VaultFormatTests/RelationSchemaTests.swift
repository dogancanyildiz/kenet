import Testing
import VaultFormat

struct RelationSchemaTests {
    @Test func relatedIsReservedInCustomSchemas() throws {
        var type = EntityTypeDefinition(
            id: "book", folder: "books",
            name: .init(tr: "Kitap", en: "Book"), plural: .init(tr: "Kitaplar", en: "Books"), icon: "book")
        type.fields = [.init(key: "related", kind: .link)]
        #expect(throws: EntityTypeError.invalidDefinition) { try type.validate() }
        type.fields = [.init(key: "Related", kind: .link)]
        try type.validate()
    }
}
