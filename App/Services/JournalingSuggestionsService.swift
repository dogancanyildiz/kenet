import EntityRecognition
import Foundation
import SwiftUI
import VaultFormat

#if os(iOS)
    import UIKit
#endif
#if canImport(JournalingSuggestions)
    import HealthKit
    @preconcurrency import JournalingSuggestions
#endif

/// The system's journaling suggestions picker (Journaling Suggestions): iPhone only. The picker
/// runs in its own process; the app sees only the suggestion the user picks, copied into
/// ``SuggestionPick``. Photos and videos are never loaded.
enum JournalingSuggestionsAvailability {
    /// The framework is in the device SDK (iPhone and iPad builds); the simulator and the Mac lack it.
    static let isFrameworkPresent: Bool = {
        #if canImport(JournalingSuggestions)
            return true
        #else
            return false
        #endif
    }()

    #if os(iOS)
        /// The picker opens only on an iPhone that has the framework: iPad has it too, but leaving
        /// it out there is a product decision. The entitlement is in the iOS signature
        /// (`Journal-iOS.entitlements`) of every build that has the framework.
        @MainActor static func current(
            idiom: UIUserInterfaceIdiom = UIDevice.current.userInterfaceIdiom,
            frameworkPresent: Bool = isFrameworkPresent
        ) -> Bool {
            frameworkPresent && idiom == .phone
        }
    #else
        static func current() -> Bool { false }
    #endif
}

extension EnvironmentValues {
    /// Overrides ``JournalingSuggestionsAvailability/current`` for the quick entry; tests set it to
    /// draw both states on a simulator that lacks the framework. `nil` asks the device.
    @Entry var journalingSuggestionsAvailable: Bool? = nil
}

/// A picked suggestion with only what the event text needs: the framework's types stay behind
/// `canImport`, and tests build this value directly.
struct SuggestionPick: Equatable, Sendable {
    var title: String
    var date: DateInterval?
    var items: [SuggestionContent]
}

/// One item of a picked suggestion.
enum SuggestionContent: Equatable, Sendable {
    case location(name: String?, city: String?, date: Date?)
    case contact(name: String)
    case workout(name: String?, duration: TimeInterval?, start: Date?)
    case song(title: String?, artist: String?, date: Date?)
    case podcast(episode: String?, show: String?, date: Date?)
    case media(title: String?, artist: String?, date: Date?)
    case motion(steps: Int, start: Date?)
    case reflection(prompt: String)
    case mood(MoodValence)
    case event(title: String, start: Date?, place: String?)
    /// A photo, live photo or video: the vault format has no attachments, so none is written.
    case attachment(AttachmentKind)

    enum AttachmentKind: Equatable, Sendable { case photo, livePhoto, video }

    /// HealthKit's seven valence classes, most unpleasant first.
    enum MoodValence: Int, CaseIterable, Sendable {
        case veryUnpleasant = 1
        case unpleasant, slightlyUnpleasant, neutral, slightlyPleasant, pleasant, veryPleasant
    }
}

/// One event line made from a suggestion, before it reaches the field: its words, the people
/// and places it names (`@Name` in the text, or a chip beside it) and the moment it happened.
struct SuggestionLine: Equatable, Sendable {
    struct Mention: Hashable, Sendable {
        let name: String
        let kind: KnownEntity.Kind
    }

    var text: String
    var mentions: [Mention]
    var start: Date?
}

/// What a pick turns into: one line per selected item that has words of its own; the people and
/// places join the first line. Photos and videos are counted, not written.
struct SuggestionDraft: Equatable, Sendable {
    var lines: [SuggestionLine]
    var skippedMedia: Int
}

enum SuggestionText {
    static func draft(from pick: SuggestionPick, locale: Locale = .current) -> SuggestionDraft {
        let bundle = PresentationLocalization.bundle(locale)
        var lines: [SuggestionLine] = []
        var mentions: [SuggestionLine.Mention] = []
        var mentionDate: Date?
        var skipped = 0

        func mention(_ raw: String?, _ kind: KnownEntity.Kind) {
            guard let name = mentionName(raw) else { return }
            let key = nameComparisonFold(name)
            guard !mentions.contains(where: { $0.kind == kind && nameComparisonFold($0.name) == key }) else { return }
            mentions.append(.init(name: name, kind: kind))
        }
        func line(_ text: String?, start: Date?, place: String? = nil, timed: Bool = true) {
            guard let text = plainWords(text), !text.isEmpty else { return }
            var made = SuggestionLine(text: text, mentions: [], start: timed ? start ?? pick.date?.start : nil)
            if let name = mentionName(place) {
                made.mentions.append(.init(name: name, kind: .place))
            }
            lines.append(made)
        }
        func joined(_ first: String?, _ second: String?) -> String? {
            let parts = [first, second].compactMap(oneLine).filter { !$0.isEmpty }
            // The first part names the thing; a second alone (an artist) says too little.
            guard oneLine(first)?.isEmpty == false else { return nil }
            return parts.joined(separator: " – ")
        }

        for item in pick.items {
            switch item {
            case .location(let name, let city, let date):
                mention(oneLine(name)?.isEmpty == false ? name : city, .place)
                mentionDate = mentionDate ?? date
            case .contact(let name):
                mention(name, .person)
            case .workout(let name, let duration, let start):
                let named = oneLine(name) ?? ""
                let title = named.isEmpty ? String(localized: "Egzersiz", bundle: bundle, locale: locale) : named
                let minutes = duration.map { max(1, Int(($0 / 60).rounded())) }
                let length = minutes.map { String(localized: "\($0) dk", bundle: bundle, locale: locale) }
                line(length.map { title + " " + $0 } ?? title, start: start)
            case .song(let title, let artist, let date), .media(let title, let artist, let date):
                line(joined(title, artist), start: date)
            case .podcast(let episode, let show, let date):
                line(joined(episode, show), start: date)
            case .motion(let steps, let start):
                guard steps > 0 else { continue }
                line(String(localized: "\(steps) adım", bundle: bundle, locale: locale), start: start)
            case .reflection(let prompt):
                line(prompt, start: nil)
            case .mood(let valence):
                line(moodText(valence, bundle: bundle, locale: locale), start: nil)
            case .event(let title, let start, let place):
                // As a calendar draft writes it: the event's start is the entry's time, not words.
                line(title, start: start, place: place)
            case .attachment:
                skipped += 1
            }
        }

        if lines.isEmpty {
            guard !mentions.isEmpty else { return SuggestionDraft(lines: [], skippedMedia: skipped) }
            // Names alone say little: the suggestion's title leads, unless it is one of the names.
            let title = plainWords(pick.title) ?? ""
            let titleKey = nameComparisonFold(title)
            let named = mentions.contains { nameComparisonFold($0.name) == titleKey }
            lines = [
                SuggestionLine(
                    text: named ? "" : title, mentions: mentions, start: mentionDate ?? pick.date?.start)
            ]
        } else {
            for extra in mentions
            where !lines[0].mentions.contains(where: {
                $0.kind == extra.kind && nameComparisonFold($0.name) == nameComparisonFold(extra.name)
            }) {
                lines[0].mentions.append(extra)
            }
        }
        return SuggestionDraft(lines: lines, skippedMedia: skipped)
    }

    /// The name as contact import would file it, without the characters a link cannot hold
    /// (`[`, `|`, `#` …); an address is no name, as for calendar attendees.
    static func mentionName(_ raw: String?) -> String? {
        guard let raw, !raw.contains("@") else { return nil }
        return ContactImportPlan.validatedName(raw)?.fileStem
    }

    /// An entry is one line: line breaks and runs of blanks become single blanks.
    static func oneLine(_ text: String?) -> String? {
        text.map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
    }

    /// A title is words, not markup: `[[`/`]]` lose a bracket so no link forms, and an `@` or `#`
    /// at a word's start becomes its full-width form, which neither mentions nor tags.
    static func plainWords(_ text: String?) -> String? {
        guard var words = oneLine(text) else { return nil }
        while words.contains("[[") { words = words.replacingOccurrences(of: "[[", with: "[") }
        while words.contains("]]") { words = words.replacingOccurrences(of: "]]", with: "]") }
        return
            words
            .split(separator: " ", omittingEmptySubsequences: false)
            .map { word in
                guard let first = word.first, first == "@" || first == "#" else { return String(word) }
                return (first == "@" ? "＠" : "＃") + word.dropFirst()
            }
            .joined(separator: " ")
    }

    private static func moodText(_ valence: SuggestionContent.MoodValence, bundle: Bundle, locale: Locale) -> String {
        switch valence {
        case .veryUnpleasant: String(localized: "Ruh hali: çok kötü", bundle: bundle, locale: locale)
        case .unpleasant: String(localized: "Ruh hali: kötü", bundle: bundle, locale: locale)
        case .slightlyUnpleasant: String(localized: "Ruh hali: biraz kötü", bundle: bundle, locale: locale)
        case .neutral: String(localized: "Ruh hali: ne iyi ne kötü", bundle: bundle, locale: locale)
        case .slightlyPleasant: String(localized: "Ruh hali: biraz iyi", bundle: bundle, locale: locale)
        case .pleasant: String(localized: "Ruh hali: iyi", bundle: bundle, locale: locale)
        case .veryPleasant: String(localized: "Ruh hali: çok iyi", bundle: bundle, locale: locale)
        }
    }
}

#if canImport(JournalingSuggestions)
    extension SuggestionPick {
        /// Copies what the text needs. Each item is read as its first matching representation, the
        /// text ones first; a photo, live photo or video is only counted, its file is never opened.
        @MainActor static func make(from suggestion: JournalingSuggestion) async -> SuggestionPick {
            var items: [SuggestionContent] = []
            for item in suggestion.items {
                items += await contents(of: item)
            }
            return SuggestionPick(title: suggestion.title, date: suggestion.date, items: items)
        }

        @MainActor private static func contents(of item: JournalingSuggestion.ItemContent) async
            -> [SuggestionContent]
        {
            typealias S = JournalingSuggestion
            if let value = try? await item.content(forType: S.Workout.self) { return [workout(value)] }
            if let value = try? await item.content(forType: S.WorkoutGroup.self) {
                return value.workouts.map(workout)
            }
            if let value = try? await item.content(forType: S.Location.self) { return [location(value)] }
            if let value = try? await item.content(forType: S.LocationGroup.self) {
                return value.locations.map(location)
            }
            if let value = try? await item.content(forType: S.Contact.self) { return [.contact(name: value.name)] }
            if let value = try? await item.content(forType: S.Song.self) {
                return [.song(title: value.song, artist: value.artist, date: value.date)]
            }
            if let value = try? await item.content(forType: S.Podcast.self) {
                return [.podcast(episode: value.episode, show: value.show, date: value.date)]
            }
            if let value = try? await item.content(forType: S.GenericMedia.self) {
                return [.media(title: value.title, artist: value.artist, date: value.date)]
            }
            if let value = try? await item.content(forType: S.MotionActivity.self) {
                return [.motion(steps: value.steps, start: value.date?.start)]
            }
            if let value = try? await item.content(forType: S.StateOfMind.self) {
                return SuggestionContent.MoodValence(rawValue: value.state.valenceClassification.rawValue)
                    .map { [.mood($0)] } ?? []
            }
            if let value = try? await item.content(forType: S.Reflection.self) {
                return [.reflection(prompt: value.prompt)]
            }
            if let value = try? await item.content(forType: S.EventPoster.self) {
                return [
                    .event(title: String(value.title.characters), start: value.eventStart, place: value.placeName)
                ]
            }
            // Last: an item that also has words keeps them; its photo is never written either way.
            if item.hasContent(ofType: S.Photo.self) { return [.attachment(.photo)] }
            if item.hasContent(ofType: S.LivePhoto.self) { return [.attachment(.livePhoto)] }
            if item.hasContent(ofType: S.Video.self) { return [.attachment(.video)] }
            return []
        }

        private nonisolated static func workout(_ value: JournalingSuggestion.Workout) -> SuggestionContent {
            .workout(
                name: value.details?.localizedName, duration: value.details?.date?.duration,
                start: value.details?.date?.start)
        }

        private nonisolated static func location(_ value: JournalingSuggestion.Location) -> SuggestionContent {
            .location(name: value.place, city: value.city, date: value.date)
        }
    }
#endif
