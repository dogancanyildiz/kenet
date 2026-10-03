import Foundation
import GRDB

enum IndexDatabase {
    static func open(_ url: URL?) throws -> DatabaseQueue {
        func prepared() throws -> DatabaseQueue {
            let database = try url.map { try DatabaseQueue(path: $0.path) } ?? DatabaseQueue()
            try IndexSchema.prepare(database)
            return database
        }
        do {
            return try prepared()
        } catch let error as DatabaseError
            where error.resultCode == .SQLITE_NOTADB || error.resultCode == .SQLITE_CORRUPT
        {
            guard let url else { throw error }
            // The failed queue has been released before replacing the disposable database files.
            for suffix in ["", "-wal", "-shm"] {
                let path = url.path + suffix
                if FileManager.default.fileExists(atPath: path) { try FileManager.default.removeItem(atPath: path) }
            }
            return try prepared()
        }
    }
}

func searchExpression(_ text: String) -> String? {
    let terms = text.precomposedStringWithCanonicalMapping.split(whereSeparator: \.isWhitespace).map {
        "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    guard !terms.isEmpty else { return nil }
    return terms.joined(separator: " ") + "*"
}
