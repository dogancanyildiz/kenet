import Foundation
import Testing
import VaultFormat

@testable import VaultIndex
@testable import VaultStore

/// A scratch copy of `Fixtures/vaults/day-copies/source` with the modification times `cases.json` gives.
///
/// The index database lives beside the vault, outside it; `tree()` covers only the vault.
struct DayCopyVault {
    struct Outcome: Decodable {
        let copy: String
        let kind: String
        let conflicts: [String]
        let fellBack: Bool
    }

    struct Cases: Decodable {
        let times: [String: Int]
        let dayCopies: [String]
        let indexedFiles: [String]
        let outcomes: [Outcome]
    }

    static func fixture() throws -> URL { try Fixtures.root().appendingPathComponent("vaults/day-copies") }

    static func cases() throws -> Cases {
        try JSONDecoder().decode(Cases.self, from: Data(contentsOf: fixture().appendingPathComponent("cases.json")))
    }

    let scratch: URL
    let root: URL
    let index: VaultIndex
    let cases: Cases

    init() throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        root = scratch.appendingPathComponent("vault-root")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: Self.fixture().appendingPathComponent("source"), to: root)
        cases = try Self.cases()
        for (path, time) in cases.times {
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: TimeInterval(time))],
                ofItemAtPath: root.appendingPathComponent(path).path)
        }
        index = try VaultIndex(databaseURL: scratch.appendingPathComponent("index.sqlite"))
        try index.rebuild(vaultRoot: root)
    }

    func remove() { try? FileManager.default.removeItem(at: scratch) }

    func url(_ path: String) -> URL { root.appendingPathComponent(path) }

    func setTime(_ path: String, _ seconds: Int) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: TimeInterval(seconds))], ofItemAtPath: url(path).path)
    }

    /// A time later than every fixture time. A merged day file is written after both versions; tests
    /// set this instead of trusting the machine's clock, which merging compares against copy times.
    static let writtenLater = 1_800_000_000

    /// Marks a merged day file as written later than every version, as the real clock would.
    func settle(_ path: String) throws {
        if FileManager.default.fileExists(atPath: url(path).path) { try setTime(path, Self.writtenLater) }
    }

    func time(_ path: String) throws -> Int {
        let date = try #require(
            try FileManager.default.attributesOfItem(atPath: url(path).path)[.modificationDate] as? Date)
        return Int(date.timeIntervalSince1970.rounded(.down))
    }

    func version(_ path: String) throws -> MergeVersion {
        MergeVersion(bytes: Array(try Data(contentsOf: url(path))), modificationTime: try time(path))
    }

    func store(
        linkFile: @escaping @Sendable (URL, URL) throws -> Void = { try FileManager.default.linkItem(at: $0, to: $1) },
        moveFile: @escaping @Sendable (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) },
        readFile: @escaping @Sendable (URL) throws -> Data = { try Data(contentsOf: $0) },
        removeFile: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) },
        dayCopyStep: @escaping @Sendable (DayCopyMergeStep) throws -> Void = { _ in },
        fileCoordination: any FileCoordination = DirectFileCoordination()
    ) -> VaultStore {
        VaultStore(
            vaultRoot: root, index: index, linkFile: linkFile, moveFile: moveFile, readFile: readFile,
            removeFile: removeFile, dayCopyStep: dayCopyStep, fileCoordination: fileCoordination)
    }

    /// Every file and directory under the vault, hidden ones included; directories map to `nil`.
    func tree() throws -> [String: Data?] { try Self.tree(root) }

    static func tree(_ root: URL) throws -> [String: Data?] {
        var result: [String: Data?] = [:]
        for path in try FileManager.default.subpathsOfDirectory(atPath: root.path) {
            let url = root.appendingPathComponent(path)
            var directory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) else { continue }
            result.updateValue(
                directory.boolValue ? nil : try Data(contentsOf: url),
                forKey: path.precomposedStringWithCanonicalMapping)
        }
        return result
    }
}

/// An error a test injects into one file system step.
enum InjectedFailure: Error, Equatable { case failed }
