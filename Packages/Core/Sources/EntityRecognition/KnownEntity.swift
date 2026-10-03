/// A person or place supplied by the caller, without index or filesystem access.
public struct KnownEntity: Hashable, Sendable {
    /// The supported entity kinds.
    public enum Kind: String, Sendable, Codable { case person, place }
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
