/// Device-independent schema values; JSON I/O lives in the Foundation layers.
public struct EntityTypeDefinition: Codable, Hashable, Sendable {
    public let id: String
    public var folder: String
    public var name: EntityTypeName
    public var plural: EntityTypeName
    public var icon: String
    public var fields: [EntityTypeField]
    public var template: String?

    public init(
        id: String, folder: String, name: EntityTypeName, plural: EntityTypeName,
        icon: String, fields: [EntityTypeField] = [], template: String? = nil
    ) {
        self.id = id
        self.folder = folder
        self.name = name
        self.plural = plural
        self.icon = icon
        self.fields = fields
        self.template = template
    }

    public static let builtIns: [Self] = [
        Self(
            id: "person", folder: "people", name: .init(tr: "Kişi", en: "Person"),
            plural: .init(tr: "Kişiler", en: "People"), icon: "person"),
        Self(
            id: "place", folder: "places", name: .init(tr: "Konum", en: "Place"),
            plural: .init(tr: "Konumlar", en: "Places"), icon: "mappin.and.ellipse"),
    ]
}

public struct EntityTypeName: Codable, Hashable, Sendable {
    public var tr: String
    public var en: String
    public init(tr: String, en: String) {
        self.tr = tr
        self.en = en
    }
    public func localized(language: String) -> String { language.hasPrefix("tr") ? tr : en }
}

public struct EntityTypeField: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable { case text, date, number, boolean, link }
    public var key: String
    public var kind: Kind
    public init(key: String, kind: Kind) {
        self.key = key
        self.kind = kind
    }
}

public struct EntityTypeCatalog: Sendable {
    public enum Issue: Sendable { case invalid, unreadable }
    public let types: [EntityTypeDefinition]
    public let issue: Issue?
    public init(types: [EntityTypeDefinition] = [], issue: Issue? = nil) {
        self.types = types
        self.issue = issue
    }
    public var allTypes: [EntityTypeDefinition] { EntityTypeDefinition.builtIns + types }
}

public struct EntityTypesFile: Codable, Sendable {
    public let formatVersion: Int
    public let types: [EntityTypeDefinition]
    public init(types: [EntityTypeDefinition]) {
        formatVersion = 1
        self.types = types
    }
}

public enum EntityTypeError: Error, Equatable, Sendable {
    case invalidDefinition, invalidFile, unknownType, staleDefinition
}
