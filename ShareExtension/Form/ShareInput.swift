import Foundation
import UniformTypeIdentifiers

// The app compiles this file too (ShareExtension/Form), so its tests read shared items as the
// extension does.

/// What the host app shared: Safari gives the page's link and its title, other apps their text as
/// an attachment or only as the item's content text.
@MainActor enum ShareInput {
    static func text(from items: [Any]) async -> String {
        var title: String?
        var link: URL?
        var text: String?
        for case let item as NSExtensionItem in items {
            if title == nil { title = item.attributedTitle?.string ?? item.attributedContentText?.string }
            for provider in item.attachments ?? [] {
                if link == nil, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                    let url = await load(URL.self, from: provider), !url.isFileURL
                {
                    link = url
                } else if text == nil, provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    text = await load(String.self, from: provider)
                }
            }
        }
        return EntryWriting.prefill(title: title, url: link, text: text)
    }

    private static func load<T: _ObjectiveCBridgeable & Sendable>(_ type: T.Type, from provider: NSItemProvider) async
        -> T? where T._ObjectiveCType: NSItemProviderReading
    {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: type) { value, _ in continuation.resume(returning: value) }
        }
    }
}
