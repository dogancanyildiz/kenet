enum DateWords {
    static let weekdays: [Language: [[String]]] = [
        .turkish: [
            ["pazartesi", "pzt"], ["salı", "sal"], ["çarşamba", "çar"], ["perşembe", "per"], ["cuma", "cum"],
            ["cumartesi", "cmt"], ["pazar", "paz"],
        ],
        .english: [
            ["monday", "mon"], ["tuesday", "tue", "tues"], ["wednesday", "wed"], ["thursday", "thu", "thur", "thurs"],
            ["friday", "fri"], ["saturday", "sat"], ["sunday", "sun"],
        ],
    ]
    static let months: [Language: [[String]]] = [
        .turkish: [
            ["ocak"], ["şubat"], ["mart"], ["nisan"], ["mayıs"], ["haziran"], ["temmuz"], ["ağustos"], ["eylül"],
            ["ekim"], ["kasım"], ["aralık"],
        ],
        .english: [
            ["january", "jan"], ["february", "feb"], ["march", "mar"], ["april", "apr"], ["may"], ["june", "jun"],
            ["july", "jul"], ["august", "aug"], ["september", "sep", "sept"], ["october", "oct"], ["november", "nov"],
            ["december", "dec"],
        ],
    ]

    static func number(_ token: String) -> Int? {
        guard !token.isEmpty, token.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return Int(token)
    }

    static func day(_ token: String, language: Language) -> Int? {
        if let number = number(token) { return number }
        guard language == .english, token.count > 2, let value = number(String(token.dropLast(2))) else { return nil }
        let suffix: String
        if (11...13).contains(value % 100) {
            suffix = "th"
        } else {
            switch value % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return token.hasSuffix(suffix) ? value : nil
    }
}
