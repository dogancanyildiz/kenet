import SwiftUI

/// One run of linked (or plain) text. Turkish suffixes stay in a separate `.plain` segment
/// so underlines never cover them (vault already keeps `[[Ev]]'de` as link + following text).
struct InkLinkSegment: Equatable, Sendable, Identifiable {
    enum Kind: Equatable, Sendable {
        case plain
        case person
        case place
        case other
        case unresolved
    }

    let id: String
    let text: String
    let kind: Kind
    /// Wiki / entity target name used in the `journal-entity` URL.
    var target: String? = nil
    /// Resolved vault-relative path when known.
    var path: String? = nil

    init(
        id: String = UUID().uuidString, text: String, kind: Kind, target: String? = nil,
        path: String? = nil
    ) {
        self.id = id
        self.text = text
        self.kind = kind
        self.target = target
        self.path = path
    }
}

/// Linked text drawn with ``InkLinkStyle``. Does not open pages — reports taps via `openURL`
/// (same scheme as ``LinkedTextView``) so the caller decides navigation.
struct InkLinkedText: View {
    let segments: [InkLinkSegment]
    /// Linked text is vault content, so it is serif unless the caller says otherwise.
    var font: Font = .ink.content
    var openURL: ((URL) -> Void)? = nil

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorSchemeContrast) private var contrast

    private var highContrast: Bool {
        contrast == .increased || differentiateWithoutColor
    }

    var body: some View {
        Text(attributed)
            .font(font)
            .environment(
                \.openURL,
                OpenURLAction { url in
                    guard url.scheme == "journal-entity" else { return .systemAction }
                    if let openURL {
                        openURL(url)
                        return .handled
                    }
                    return .systemAction
                }
            )
    }

    var attributed: AttributedString {
        InkLinkTextBuilder.attributed(segments: segments, highContrast: highContrast)
    }
}

/// Pure attributed-string builder (not MainActor) so unit tests can call it freely.
enum InkLinkTextBuilder {
    static func attributed(
        segments: [InkLinkSegment], highContrast: Bool
    ) -> AttributedString {
        var result = AttributedString()
        for segment in segments {
            var value = AttributedString(segment.text)
            switch segment.kind {
            case .plain:
                value.foregroundColor = Color.ink.text
            case .person:
                InkLinkStyle.apply(.person, to: &value, highContrast: highContrast)
                attachLink(&value, target: segment.target ?? segment.text, path: segment.path)
            case .place:
                InkLinkStyle.apply(.place, to: &value, highContrast: highContrast)
                attachLink(&value, target: segment.target ?? segment.text, path: segment.path)
            case .other:
                InkLinkStyle.apply(.other, to: &value, highContrast: highContrast)
                attachLink(&value, target: segment.target ?? segment.text, path: segment.path)
            case .unresolved:
                InkLinkStyle.apply(.unresolved, to: &value, highContrast: highContrast)
                attachLink(&value, target: segment.target ?? segment.text, path: nil)
            }
            result.append(value)
        }
        return result
    }

    private static func attachLink(
        _ value: inout AttributedString, target: String, path: String?
    ) {
        var components = URLComponents()
        components.scheme = "journal-entity"
        components.host = "open"
        var items = [URLQueryItem(name: "name", value: target)]
        if let path { items.append(URLQueryItem(name: "path", value: path)) }
        components.queryItems = items
        value.link = components.url
    }
}
