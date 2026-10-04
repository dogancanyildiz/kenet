extension EntityTypeDefinition {
    public static func isValidID(_ id: String) -> Bool {
        let bytes = Array(id.utf8)
        return bytes.first.map { (97...122).contains($0) } == true
            && bytes.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }
    }

    public static func isRelativePath(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return !parts.isEmpty && parts.allSatisfy { !$0.isEmpty && !$0.hasPrefix(".") }
            && !path.contains("\\")
            && path.unicodeScalars.allSatisfy {
                $0.value >= 32 && !(127...159).contains($0.value) && $0.value != 0x2028 && $0.value != 0x2029
            }
    }

    public func validate() throws {
        let reserved = ["person", "place", "goal", "journal", "day", "note"]
        let names = [name.tr, name.en, plural.tr, plural.en, icon]
        guard Self.isValidID(id), !reserved.contains(id), Self.isRelativePath(folder),
            !["templates", "conflicts", "journal"].contains(String(folder.split(separator: "/")[0]).lowercased()),
            names.allSatisfy({
                !$0.allSatisfy(\.isWhitespace)
                    && $0.unicodeScalars.allSatisfy {
                        $0.value >= 32 && !(127...159).contains($0.value) && $0.value != 0x2028 && $0.value != 0x2029
                    }
            }),
            template.map({ Self.isRelativePath($0) && $0.hasSuffix(".md") }) ?? true
        else { throw EntityTypeError.invalidDefinition }
        var keys: Set<[UInt8]> = []
        for field in fields {
            guard !["type", "name", "qualifier", "aliases"].contains(field.key),
                keys.insert(Array(field.key.utf8)).inserted,
                (try? RawDocument(bytes: []).settingFrontmatterValue(.text(""), forKey: field.key)) != nil
            else { throw EntityTypeError.invalidDefinition }
        }
    }
}

extension EntityTypesFile {
    public func validate() throws {
        guard formatVersion == 1 else { throw EntityTypeError.invalidFile }
        var ids: Set<String> = []
        for type in types {
            try type.validate()
            guard ids.insert(type.id).inserted else { throw EntityTypeError.invalidFile }
        }
    }
}
