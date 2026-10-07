import Foundation

/// Locates and loads the language-independent fixture files at the repository root.
enum Fixtures {
    /// The environment variable that overrides where the `Fixtures` directory is looked up.
    static let overrideVariable = "FIXTURES_DIR"

    static let directoryName = "Fixtures"

    /// The `Fixtures` directory: the override when set, otherwise the nearest one above this source file.
    static func root(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        searchFrom sourcePath: String = #filePath
    ) throws -> URL {
        if let override = environment[overrideVariable], !override.isEmpty {
            let url = URL(fileURLWithPath: override, isDirectory: true)
            guard isDirectory(url) else { throw FixtureError.overrideIsNotADirectory(path: override) }
            return url
        }

        var directory = URL(fileURLWithPath: sourcePath).deletingLastPathComponent()
        while true {
            let candidate = directory.appendingPathComponent(directoryName, isDirectory: true)
            if isDirectory(candidate) { return candidate }
            let parent = directory.deletingLastPathComponent()
            guard parent.path != directory.path else { throw FixtureError.rootNotFound(searchedFrom: sourcePath) }
            directory = parent
        }
    }

    /// Paths of every Markdown fixture, relative to the fixture root and sorted.
    ///
    /// - Parameter subdirectory: Limits the search to one category such as `roundtrip`.
    static func markdownPaths(in subdirectory: String? = nil) throws -> [String] {
        let prefix = subdirectory.map { $0 + "/" } ?? ""
        let directory = try root().appendingPathComponent(prefix, isDirectory: true)
        return try FileManager.default.subpathsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".md") }
            .map { prefix + $0 }
            .sorted()
    }

    /// The exact bytes of a fixture file.
    static func bytes(at relativePath: String) throws -> [UInt8] {
        let url = try root().appendingPathComponent(relativePath)
        do {
            return Array(try Data(contentsOf: url))
        } catch {
            throw FixtureError.unreadable(path: url.path, reason: String(describing: error))
        }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

enum FixtureError: Error, Equatable, CustomStringConvertible {
    case rootNotFound(searchedFrom: String)
    case overrideIsNotADirectory(path: String)
    case unreadable(path: String, reason: String)

    var description: String {
        switch self {
        case .rootNotFound(let searchedFrom):
            "No \(Fixtures.directoryName) directory found above \(searchedFrom). "
                + "Set \(Fixtures.overrideVariable) to the directory that holds the fixture files."
        case .overrideIsNotADirectory(let path):
            "\(Fixtures.overrideVariable) is set to \(path), which is not a directory."
        case .unreadable(let path, let reason):
            "Cannot read fixture \(path): \(reason)"
        }
    }
}
