/// Pure filename mapping for system download placeholders; spelling is preserved.
///
/// Matching uses UTF-8 bytes, not characters: a name whose first scalar combines with the
/// leading dot would otherwise fail the prefix test, and slicing by character could drop bytes.
public enum PlaceholderName {
    private static let suffix = Array(".icloud".utf8)

    public static func isPlaceholder(fileName: String) -> Bool {
        originalName(ofPlaceholder: fileName) != nil
    }

    public static func originalName(ofPlaceholder fileName: String) -> String? {
        let bytes = fileName.utf8
        guard bytes.count > suffix.count + 1, bytes.first == UInt8(ascii: "."),
            bytes.reversed().starts(with: suffix.reversed()),
            let original = String(bytes.dropFirst().dropLast(suffix.count)), original != ".", original != ".."
        else { return nil }
        return original
    }

    public static func placeholderName(for fileName: String) -> String {
        "." + fileName + ".icloud"
    }
}
