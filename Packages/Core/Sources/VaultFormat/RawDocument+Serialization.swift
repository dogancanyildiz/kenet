extension RawDocument {
    /// The bytes of the file this document represents.
    ///
    /// The output is the byte order mark, when present, followed by the stored bytes of every
    /// line. Nothing is re-encoded, so an unmodified document yields exactly the bytes it was
    /// read from.
    public func serialized() -> [UInt8] {
        var output: [UInt8] = []
        if hasByteOrderMark {
            output.append(contentsOf: Self.byteOrderMark)
        }
        for line in lines {
            output.append(contentsOf: line.content)
            if let ending = line.ending {
                output.append(contentsOf: ending.bytes)
            }
        }
        return output
    }
}
