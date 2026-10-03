import DateParsing
import Testing
import VaultFormat

@Test func randomTextPreservesRangesAndUntouchedBytes() throws {
    var state: UInt64 = 42
    func next(_ count: Int) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        return Int((state >> 32) % UInt64(count))
    }
    let pieces = [
        "yarın", "öbür gün", "friday", "5 ekim", "2026-10-05", "@Cuma", "[[yarın]]", "`tomorrow`", "😊", "a", "ç", "İ",
        "ı", " ", "  ", "\t", "\r\n", "/", "_", "31 şubat",
    ]
    for _ in 0..<2000 {
        let text = (0..<next(20)).map { _ in pieces[next(pieces.count)] }.joined()
        let bytes = Array(text.utf8)
        if let result = DateExpressionParser.parse(
            text, today: CalendarDate("2026-10-03")!, language: [.turkish, .english])
        {
            let range = result.byteRange
            #expect(range.lowerBound >= 0 && range.upperBound <= bytes.count && !range.isEmpty)
            let expression = String(decoding: bytes[range], as: UTF8.self)
            #expect(expression.utf8.count == range.count)
            #expect(result.remainder.utf8.count <= bytes.count - range.count + 1)
            let repeated = DateExpressionParser.parse(
                text, today: CalendarDate("2026-10-03")!, language: [.turkish, .english])
            #expect(repeated == result)
            var lower = range.lowerBound
            var upper = range.upperBound
            while lower > 0 && [UInt8(32), 9].contains(bytes[lower - 1]) { lower -= 1 }
            while upper < bytes.count && [UInt8(32), 9].contains(bytes[upper]) { upper += 1 }
            #expect(Array(result.remainder.utf8).starts(with: bytes[..<lower]))
            #expect(Array(result.remainder.utf8).suffix(bytes.count - upper).elementsEqual(bytes[upper...]))
        }
    }
}
