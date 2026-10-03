extension EntityRecognizer {
    static func ranked(
        _ mentions: [Mention], usage: [EntityUsage], context: RecognitionContext,
        onScoring: ((KnownEntity) -> Void)? = nil
    ) -> [Mention] {
        var statistics: [String: EntityUsage] = [:]
        for item in usage { statistics[item.file] = item }
        var established: [String: KnownEntity] = [:]
        for entity in context.entities { established[entity.file] = entity }
        for mention in mentions where mention.isCertain {
            let entity = mention.candidates[0]
            established[entity.file] = entity
        }
        func score(_ candidate: KnownEntity) -> UInt64 {
            onScoring?(candidate)
            var sum: UInt64 = 0
            for other in established.values where other.file != candidate.file {
                let count = UInt64(max(0, statistics[candidate.file]?.cooccurrences[other.file] ?? 0))
                let weight: UInt64 = other.kind == .place ? 4 : 1
                let (product, overflow) = count.multipliedReportingOverflow(by: weight)
                let (total, additionOverflow) = sum.addingReportingOverflow(overflow ? .max : product)
                sum = additionOverflow ? .max : total
            }
            return sum
        }
        var scores: [String: UInt64] = [:]
        for mention in mentions where mention.isAmbiguous {
            for candidate in mention.candidates where scores[candidate.file] == nil {
                scores[candidate.file] = score(candidate)
            }
        }
        return mentions.map { mention in
            let candidates = mention.candidates.sorted { lhs, rhs in
                let left = statistics[lhs.file]
                let right = statistics[rhs.file]
                let leftScore = scores[lhs.file] ?? 0
                let rightScore = scores[rhs.file] ?? 0
                if leftScore != rightScore { return leftScore > rightScore }
                if left?.lastDate != right?.lastDate {
                    guard let first = left?.lastDate else { return false }
                    guard let second = right?.lastDate else { return true }
                    return first > second
                }
                let leftCount = max(0, left?.totalCount ?? 0)
                let rightCount = max(0, right?.totalCount ?? 0)
                if leftCount != rightCount { return leftCount > rightCount }
                return lhs.file.unicodeScalars.lexicographicallyPrecedes(rhs.file.unicodeScalars) {
                    $0.value < $1.value
                }
            }
            return Mention(
                position: mention.position, spelling: mention.spelling, candidates: candidates,
                isCaseMismatch: mention.isCaseMismatch, isExplicit: mention.isExplicit, isAlias: mention.isAlias)
        }
    }
}
