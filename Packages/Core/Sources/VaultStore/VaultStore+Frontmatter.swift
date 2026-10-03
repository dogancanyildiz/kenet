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
