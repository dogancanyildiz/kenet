/// Ready-made custom entity types offered when the user adds a type. Each item is an ordinary
/// `.app/types.json` definition plus the contents of its `templates/<id>.md` file: the gallery
/// adds no format. Field keys are Turkish words with Turkish letters: the entity page shows them
/// as the field names (vault-format.md: template field names are in the user's language).
public struct EntityTypeGalleryItem: Hashable, Sendable {
    public let definition: EntityTypeDefinition

    public init(definition: EntityTypeDefinition) {
        self.definition = definition
    }

    /// The contents of the item's template file.
    public var template: String { definition.starterTemplate }

    /// An existing type already uses this id or folder; adding the item again would collide.
    public func isTaken(by types: [EntityTypeDefinition]) -> Bool {
        let folder = definition.folder.lowercased()
        return types.contains { $0.id == definition.id || $0.folder.lowercased() == folder }
    }
}

public enum EntityTypeGallery {
    /// Ten types, three to four fields each; `link` fields point at people, places or other
    /// entities (the format stores no link target type).
    public static let items: [EntityTypeGalleryItem] = [
        item(
            "book", "books", ("Kitap", "Book"), ("Kitaplar", "Books"), "book.closed.fill",
            [("yazar", .link), ("sayfa", .number), ("puan", .number), ("bitirme", .date)]),
        item(
            "film", "films", ("Film", "Film"), ("Filmler", "Films"), "film.fill",
            [("yönetmen", .text), ("yıl", .number), ("puan", .number), ("izlendi", .date)]),
        item(
            "organization", "organizations", ("Kurum", "Organization"), ("Kurumlar", "Organizations"),
            "building.2.fill", [("tür", .text), ("kişiler", .link), ("web", .text)]),
        item(
            "project", "projects", ("Proje", "Project"), ("Projeler", "Projects"), "folder.fill",
            [("durum", .text), ("başlangıç", .date), ("kurum", .link)]),
        item(
            "event", "events", ("Etkinlik", "Event"), ("Etkinlikler", "Events"), "calendar",
            [("başlangıç", .date), ("bitiş", .date), ("konum", .link)]),
        item(
            "trip", "trips", ("Seyahat", "Trip"), ("Seyahatler", "Trips"), "airplane",
            [("başlangıç", .date), ("bitiş", .date), ("konum", .link)]),
        item(
            "recipe", "recipes", ("Tarif", "Recipe"), ("Tarifler", "Recipes"), "fork.knife",
            [("mutfak", .text), ("süre", .number), ("puan", .number)]),
        item(
            "product", "products", ("Ürün", "Product"), ("Ürünler", "Products"), "shippingbox.fill",
            [("marka", .text), ("fiyat", .number), ("alındı", .date)]),
        item(
            "pet", "pets", ("Evcil hayvan", "Pet"), ("Evcil hayvanlar", "Pets"), "pawprint.fill",
            [("tür", .text), ("doğum", .date), ("aşı", .date)]),
        item(
            "vehicle", "vehicles", ("Araç", "Vehicle"), ("Araçlar", "Vehicles"), "car.fill",
            [("plaka", .text), ("muayene", .date), ("sigorta", .date)]),
    ]

    private static func item(
        _ id: String, _ folder: String, _ name: (String, String), _ plural: (String, String), _ icon: String,
        _ fields: [(String, EntityTypeField.Kind)]
    ) -> EntityTypeGalleryItem {
        EntityTypeGalleryItem(
            definition: EntityTypeDefinition(
                id: id, folder: folder, name: .init(tr: name.0, en: name.1),
                plural: .init(tr: plural.0, en: plural.1), icon: icon,
                fields: fields.map { EntityTypeField(key: $0.0, kind: $0.1) }, template: "templates/\(id).md"))
    }
}

extension EntityTypeDefinition {
    /// A first template for a new type: `type`, an empty `name` and every field as an empty
    /// value, so a new entity starts with each field present (`name` is replaced, the rest kept).
    public var starterTemplate: String {
        (["---", "type: " + id, "name:"] + fields.map { $0.key + ":" } + ["---", ""]).joined(separator: "\n")
    }
}
