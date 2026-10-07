import Foundation
import VaultFormat

public enum EntityTypeReader {
    /// Missing means built-ins only; a damaged schema is never partially accepted.
    public static func read(vaultRoot: URL) -> EntityTypeCatalog {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL(vaultRoot: vaultRoot))
        } catch CocoaError.fileReadNoSuchFile {
            return EntityTypeCatalog()
        } catch {
            return EntityTypeCatalog(issue: .unreadable)
        }
        return decode(data)
    }

    public static func decode(_ data: Data) -> EntityTypeCatalog {
        do {
            _ = try JSONSource.parse(data)
            let file = try JSONDecoder().decode(EntityTypesFile.self, from: data)
            try file.validate()
            return EntityTypeCatalog(types: file.types)
        } catch { return EntityTypeCatalog(issue: .invalid) }
    }

    /// The sole exception to hidden path exclusion: this particular settings file.
    public static func fileURL(vaultRoot: URL) throws -> URL {
        var url = vaultRoot.resolvingSymlinksInPath().standardizedFileURL
        for part in [".app", "types.json"] {
            url.appendPathComponent(part)
            if let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey]) {
                if values.isSymbolicLink == true || (part == ".app" && values.isDirectory != true) {
                    throw EntityTypeError.invalidFile
                }
            }
        }
        return url
    }
}
