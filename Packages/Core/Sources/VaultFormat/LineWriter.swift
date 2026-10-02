/// A valid clock time for writing an event.
public struct LineClock: Hashable, Sendable {
    /// The hour, from zero through 23.
    public let hour: Int
    /// The minute, from zero through 59.
    public let minute: Int

    /// Validates a local clock time.
    public init(hour: Int, minute: Int) throws(EditError) {
        guard (0...23).contains(hour), (0...59).contains(minute) else { throw .invalidValue }
        self.hour = hour
        self.minute = minute
    }

    var token: String { (hour < 10 ? "0" : "") + String(hour) + ":" + (minute < 10 ? "0" : "") + String(minute) }
    var eventTime: EventTime { EventTime(hour: hour, minute: minute, raw: token) }
}

/// Generates bounded, caller-checked six-character block identifiers.
public enum BlockIDGenerator {
    /// Tries at most `attempts` candidates; exhaustion throws `identifierExhausted`.
    public static func generate(
        using random: inout some RandomNumberGenerator, attempts: Int = 128,
        isTaken: (String) -> Bool
    ) throws(EditError) -> String {
        guard attempts > 0 else { throw .invalidValue }
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789".utf8)
        for _ in 0..<attempts {
            // Modulo keeps even a pathological supplied generator bounded.
            let id = String(decoding: (0..<6).map { _ in alphabet[Int(random.next() % 36)] }, as: UTF8.self)
            if !isTaken(id) { return id }
        }
        throw .identifierExhausted
    }
}

/// Shared first-line ranges obtained from the reader's syntax routines.
struct LineParts: Sendable {
    let text: Range<Int>
    let id: Range<Int>?
    let status: Range<Int>?
    let needsTextSeparator: Bool
    let needsIDSuffix: Bool
    let clockStart: Int
    let clockToken: Range<Int>?
    let clockRemoval: Range<Int>?

    init(_ bytes: [UInt8]) {
        let split = BodyLineParser.splitID(Syntax.string(bytes))
        let end = split.text.utf8.count
        id = split.id.map { (end + 2)..<(end + 2 + $0.utf8.count) }
        let checkbox = BodyLineParser.task(Array(bytes[..<end]))
        status = checkbox?.statusRange
        if let checkbox {
            needsTextSeparator = !checkbox.hasSeparator
            needsIDSuffix = false
            clockStart = 0
            clockToken = nil
            clockRemoval = nil
            text = checkbox.textStart..<end
        } else {
            let parsed = BodyLineParser.event(bytes)
            needsTextSeparator = parsed.tokenRange.map { $0.upperBound == parsed.textRange.lowerBound } == true
            needsIDSuffix = parsed.needsIDSuffix
            clockStart = parsed.clockStart
            clockToken = parsed.tokenRange
            clockRemoval = parsed.removalRange
            text = parsed.textRange
        }
    }

    static func validateID(_ id: String?) throws(EditError) {
        if let id, id.isEmpty || !id.utf8.allSatisfy(BodyLineParser.isIDByte) { throw .invalidValue }
    }

    static func clean(_ text: String) throws(EditError) -> String {
        let bytes = Array(text.utf8)
        guard !bytes.contains(10), !bytes.contains(13) else { throw .lineBreakInContent }
        let start = bytes.prefix(while: Syntax.isBlank).count
        let end = bytes.count - bytes.reversed().prefix(while: Syntax.isBlank).count
        guard start < end else { throw .emptyText }
        return Syntax.string(bytes[start..<end])
    }

    func changing(_ bytes: [UInt8], range: Range<Int>?, value: String?, newID: String?) -> String {
        var result = bytes
        // Identifier is last, so modifying it first leaves the earlier offsets valid.
        if let newID {
            if let id {
                result.replaceSubrange(id, with: newID.utf8)
            } else {
                result.append(contentsOf: (" ^" + newID).utf8)
            }
        }
        if let range, let value { result.replaceSubrange(range, with: value.utf8) }
        return Syntax.string(result)
    }
}
