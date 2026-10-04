import VaultFormat

/// A person or place supplied by the caller, without index or filesystem access.
public struct KnownEntity: Hashable, Sendable {
    /// The supported entity kinds.
    public enum Kind: Hashable, Sendable, Codable {
        case person, place
        case custom(String)
        public init?(rawValue: String) {
            switch rawValue {
            case "person": self = .person
            case "place": self = .place
            default:
                guard EntityTypeDefinition.isValidID(rawValue),
                    !["goal", "journal", "day", "note"].contains(rawValue)
                else { return nil }
                self = .custom(rawValue)
            }
        }
        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let kind = Self(rawValue: value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown entity kind")
            }
            self = kind
        }
        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
        public var rawValue: String {
            switch self {
            case .person: "person"
            case .place: "place"
            case .custom(let id): id
            }
        }
    }
    /// The vault-relative Markdown path.
    public let file: String
    /// The entity kind.
    public let kind: Kind
    /// The visible name, independently of its filename.
    public let name: String
    /// The optional distinguishing label.
    public let qualifier: String?
    /// The aliases in source order.
    public let aliases: [String]
    /// Locale-independent lowercase keys, compared with Swift's canonical Unicode equality.
    public var comparisonKeys: [String] { ([name] + aliases).map { $0.lowercased() } }

    /// Creates an immutable recognition input.
    public init(file: String, kind: Kind, name: String, qualifier: String? = nil, aliases: [String] = []) {
        self.file = file
        self.kind = kind
        self.name = name
        self.qualifier = qualifier
        self.aliases = aliases
    }

    /// The filename without its directory or Markdown extension.
    public var fileStem: String {
        let filename = String(file.split(separator: "/").last ?? "")
        return filename.hasSuffix(".md") ? String(filename.dropLast(3)) : filename
    }
}
