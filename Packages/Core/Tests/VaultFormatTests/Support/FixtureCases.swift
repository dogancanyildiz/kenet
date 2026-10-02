import Foundation

extension Fixtures {
    /// The names of the case directories in a category such as `parse`, sorted.
    ///
    /// Each case is a directory, so adding one needs no code change.
    static func caseNames(in category: String) throws -> [String] {
        let directory = try root().appendingPathComponent(category, isDirectory: true)
        return try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { name in
                var isDirectory: ObjCBool = false
                let path = directory.appendingPathComponent(name).path
                return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
            }
            .sorted()
    }

    /// The names of the files directly inside a fixture directory, sorted. Hidden files that the
    /// operating system leaves behind are not fixture files.
    static func fileNames(in relativeDirectory: String) throws -> [String] {
        let directory = try root().appendingPathComponent(relativeDirectory, isDirectory: true)
        return try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { !$0.hasPrefix(".") }
            .sorted()
    }

    /// A fixture file parsed as JSON.
    static func json(at relativePath: String) throws -> JSONValue {
        do {
            return try JSONValue(parsing: try bytes(at: relativePath))
        } catch let error as FixtureError {
            throw error
        } catch {
            throw FixtureError.unreadable(path: relativePath, reason: String(describing: error))
        }
    }
}

/// Bytes as text with line endings, the byte order mark and other invisible bytes spelled out.
func visible(_ bytes: [UInt8]) -> String {
    var output = ""
    for scalar in String(decoding: bytes, as: UTF8.self).unicodeScalars {
        switch scalar {
        case "\n": output += "\\n\n"
        case "\r": output += "\\r"
        case "\t": output += "\\t"
        case "\u{FEFF}": output += "<BOM>"
        default: output.unicodeScalars.append(scalar)
        }
    }
    return output
}
