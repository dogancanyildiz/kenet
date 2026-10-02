/// A line terminator recognized by the vault format.
///
/// A line ends with LF, with CRLF, or with a CR that is not followed by LF, which is how
/// CommonMark and Obsidian split lines as well.
public enum LineEnding: Hashable, Sendable, CaseIterable {
    /// A single line feed (`\n`).
    case lf
    /// A carriage return followed by a line feed (`\r\n`).
    case crlf
    /// A carriage return that is not followed by a line feed (`\r`).
    case cr

    /// The bytes this line ending occupies in a file.
    public var bytes: [UInt8] {
        switch self {
        case .lf: [Self.lineFeed]
        case .crlf: [Self.carriageReturn, Self.lineFeed]
        case .cr: [Self.carriageReturn]
        }
    }

    static let lineFeed: UInt8 = 0x0A
    static let carriageReturn: UInt8 = 0x0D
}
