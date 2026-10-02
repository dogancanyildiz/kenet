/// UTF-8 decoding that refuses ill-formed input instead of repairing it.
enum StrictUTF8 {
    /// Returns the bytes as a string, or `nil` when they are not well-formed UTF-8.
    static func decode(_ bytes: [UInt8]) -> String? {
        // The repairing decoder always produces well-formed UTF-8, so its output can only
        // equal the input when the input was well-formed and nothing had to be replaced.
        let repaired = String(decoding: bytes, as: UTF8.self)
        return repaired.utf8.elementsEqual(bytes) ? repaired : nil
    }
}
