import VaultFormat

extension VaultStore {
    /// Edits a single scalar field through the serialized file-first gateway.
    @discardableResult
    public func settingFrontmatterValue(at path: String, key: String, value: FrontmatterLiteral) async throws
        -> RawDocument
    {
        try await perform { try self.edit(path) { try $0.settingFrontmatterValue(value, forKey: key) } }
    }

    /// Preserves the existing list style and all unrelated bytes.
    @discardableResult
    public func settingFrontmatterList(at path: String, key: String, values: [FrontmatterLiteral]) async throws
        -> RawDocument
    {
        try await perform { try self.edit(path) { try $0.settingFrontmatterList(values, forKey: key) } }
    }

    /// Changes a list in one read–write step, so the change is made to the list the file holds at
    /// that moment and not to one read earlier. `change` gets the field's items: empty for a missing
    /// key or a file with no frontmatter, `nil` for a mapping, raw text or an unreadable frontmatter.
    /// What it throws leaves the file untouched; what it returns is written like ``settingFrontmatterList``.
    @discardableResult
    public func changingFrontmatterList(
        at path: String, key: String,
        change: @escaping @Sendable ([FrontmatterScalar]?) throws -> [FrontmatterLiteral]
    ) async throws -> RawDocument {
        try await perform {
            try self.edit(path) { document in
                let items: [FrontmatterScalar]?
                switch document.frontmatter {
                case .absent: items = []
                case .unreadable: items = nil
                case .parsed(let frontmatter):
                    if let field = frontmatter.field(named: key) { items = field.value.listItems } else { items = [] }
                }
                return try document.settingFrontmatterList(try change(items), forKey: key)
            }
        }
    }

    /// Edits one resolved mapping entry without rewriting its neighbours.
    @discardableResult
    public func settingFrontmatterEntry(at path: String, key: String, entry: String, value: FrontmatterLiteral)
        async throws -> RawDocument
    {
        try await perform {
            try self.edit(path) { try $0.settingFrontmatterEntry(value, forKey: entry, inMapping: key) }
        }
    }

    /// Removes only the selected resolved field; raw fields remain protected.
    @discardableResult
    public func removingFrontmatterField(at path: String, key: String) async throws -> RawDocument {
        try await perform { try self.edit(path) { try $0.removingFrontmatterField(forKey: key) } }
    }
}
