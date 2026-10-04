import Foundation
import VaultFormat
import VaultIndex

/// Applies patches from right to left so every untouched byte keeps its original position/order.
struct EntityTypeJSONEdit {
    let data: Data
    let root: JSONSource

    init(_ data: Data) throws {
        self.data = data
        root = try JSONSource.parse(data)
    }

    func replacing(_ definition: EntityTypeDefinition, at node: JSONSource) throws -> Data {
        let encoder = JSONEncoder()
        let object = try JSONSerialization.jsonObject(with: encoder.encode(definition)) as! [String: Any]
        return try patchObject(node, values: object, removeTemplate: true)
    }

    private func patchObject(_ node: JSONSource, values: [String: Any], removeTemplate: Bool = false) throws -> Data {
        var edits: [(Range<Int>, Data)] = []
        var additions: [String] = []
        for key in values.keys.sorted() {
            let value = values[key]!
            if let target = node.members[key] {
                let replacement: Data
                if let dictionary = value as? [String: Any] {
                    replacement = try patchObject(target, values: dictionary)
                } else if key == "fields", let fields = value as? [[String: Any]] {
                    let originalFields = try JSONDecoder().decode(
                        [EntityTypeField].self, from: data.subdata(in: target.range))
                    let newFields = try JSONDecoder().decode([EntityTypeField].self, from: encoded(fields))
                    if originalFields == newFields { continue }
                    let pieces = try fields.map { field -> Data in
                        if let existing = target.elements.first(where: {
                            guard let keyNode = $0.members["key"] else { return false }
                            return (try? JSONDecoder().decode(String.self, from: data.subdata(in: keyNode.range)))
                                == field["key"] as? String
                        }) {
                            return try patchObject(existing, values: field)
                        }
                        return try encoded(field)
                    }
                    replacement =
                        Data("[".utf8)
                        + pieces.enumerated().reduce(into: Data()) { result, pair in
                            if pair.offset > 0 { result.append(contentsOf: ",".utf8) }
                            result.append(pair.element)
                        } + Data("]".utf8)
                } else {
                    let original = try JSONSerialization.jsonObject(
                        with: data.subdata(in: target.range), options: .fragmentsAllowed)
                    if try encoded(original) == encoded(value) { continue }
                    replacement = try encoded(value)
                }
                if replacement != data.subdata(in: target.range) { edits.append((target.range, replacement)) }
            } else {
                additions.append(
                    String(decoding: try encoded(key), as: UTF8.self) + ":"
                        + String(decoding: try encoded(value), as: UTF8.self))
            }
        }
        // Optional template removal changes only its value; JSON null decodes as absent.
        if removeTemplate, values["template"] == nil, let template = node.members["template"] {
            edits.append((template.range, Data("null".utf8)))
        }
        if !additions.isEmpty {
            edits.append(
                (
                    (node.range.upperBound - 1)..<(node.range.upperBound - 1),
                    Data(((node.members.isEmpty ? "" : ",") + additions.joined(separator: ",")).utf8)
                ))
        }
        var result = data.subdata(in: node.range)
        for (range, bytes) in edits.sorted(by: { $0.0.lowerBound > $1.0.lowerBound }) {
            result.replaceSubrange(
                (range.lowerBound - node.range.lowerBound)..<(range.upperBound - node.range.lowerBound), with: bytes)
        }
        return result
    }

    func upserting(_ definition: EntityTypeDefinition, replacing id: String?) throws -> Data {
        guard let array = root.members["types"] else { throw EntityTypeError.invalidFile }
        let nodes = array.elements
        var result = data
        if let id, let node = nodes.first(where: { nodeID($0) == id }) {
            result.replaceSubrange(node.range, with: try replacing(definition, at: node))
        } else {
            let bytes = try JSONEncoder().encode(definition)
            let offset = array.range.upperBound - 1
            result.insert(contentsOf: Data((nodes.isEmpty ? "" : ",").utf8) + bytes, at: offset)
        }
        return result
    }

    func deleting(_ id: String) throws -> Data {
        guard let array = root.members["types"], let index = array.elements.firstIndex(where: { nodeID($0) == id })
        else { throw EntityTypeError.unknownType }
        let nodes = array.elements
        let range: Range<Int>
        if index + 1 < nodes.count {
            range = nodes[index].range.lowerBound..<nodes[index + 1].range.lowerBound
        } else if index > 0 {
            range = nodes[index - 1].range.upperBound..<nodes[index].range.upperBound
        } else {
            range = nodes[index].range
        }
        var result = data
        result.removeSubrange(range)
        return result
    }

    private func nodeID(_ node: JSONSource) -> String? {
        node.members["id"].flatMap { try? JSONDecoder().decode(String.self, from: data.subdata(in: $0.range)) }
    }
    private func encoded(_ value: Any) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes])
    }
}
