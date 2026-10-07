import VaultFormat

extension IndexStore {
    func setField(at path: String, key: String, value: FrontmatterLiteral) async throws {
        try await performEdit(path: path) { try await $0.settingFrontmatterValue(at: path, key: key, value: value) }
    }
    func setList(at path: String, key: String, values: [FrontmatterLiteral]) async throws {
        try await performEdit(path: path) { try await $0.settingFrontmatterList(at: path, key: key, values: values) }
    }
    func setEntry(at path: String, key: String, entry: String, value: FrontmatterLiteral) async throws {
        try await performEdit(path: path) {
            try await $0.settingFrontmatterEntry(at: path, key: key, entry: entry, value: value)
        }
    }
    func removeField(at path: String, key: String) async throws {
        try await performEdit(path: path) { try await $0.removingFrontmatterField(at: path, key: key) }
    }
}
