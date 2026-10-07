import Foundation
import VaultFormat

/// Writes the frontmatter blocks the reader accepts to files, for showing them to other YAML readers.
///
/// Nothing is written unless `FRONTMATTER_SAMPLES_DIR` names a directory. The developer script
/// `.github/scripts/check-frontmatter-yaml.rb --samples` then checks that other readers accept
/// every block and find the same values in it.
struct SampleWriter {
    static let directoryVariable = "FRONTMATTER_SAMPLES_DIR"

    private let directory: URL?

    init(environment: [String: String] = ProcessInfo.processInfo.environment) throws {
        let path = environment[Self.directoryVariable] ?? ""
        directory = path.isEmpty ? nil : URL(fileURLWithPath: path, isDirectory: true)
        if let directory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    /// Stores the lines between the delimiters when the reader accepts the block, with every
    /// line ending written as LF so that the other reader sees the same lines, and next to
    /// them the values the reader found, in the form of a `parse` fixture.
    func add(_ document: RawDocument) throws {
        guard let directory, case .parsed(let frontmatter) = document.frontmatter else { return }
        let body = document.lines[frontmatter.lineRange].dropFirst().dropLast()
        let bytes = Array(body.map { $0.content + [0x0A] }.joined())

        // The name is a hash of the block (FNV-1a), so the same block is written once.
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in bytes {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        let name = String(hash, radix: 16)
        let expected: JSONValue = .object(["frontmatter": FrontmatterSnapshot.json(document.frontmatter)])
        try Data(bytes).write(to: directory.appendingPathComponent(name + ".yaml"))
        try Data(expected.description.utf8).write(to: directory.appendingPathComponent(name + ".json"))
    }
}
