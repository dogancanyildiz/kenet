import Foundation

/// Isolates bookmark serialization from folder access and recovery policy.
struct VaultBookmarks {
    var resolve: (Data) throws -> (url: URL, isStale: Bool) = { data in
        var stale = false
        #if os(macOS)
            let options: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI]
        #else
            let options: URL.BookmarkResolutionOptions = [.withoutUI]
        #endif
        let url = try URL(resolvingBookmarkData: data, options: options, bookmarkDataIsStale: &stale)
        return (url, stale)
    }
    var create: (URL) throws -> Data = { url in
        #if os(macOS)
            let options: URL.BookmarkCreationOptions = [.withSecurityScope]
        #else
            let options: URL.BookmarkCreationOptions = [.minimalBookmark]
        #endif
        return try url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
    }
    var isMalformed: (Data) -> Bool = { data in
        URL.resourceValues(forKeys: [.pathKey], fromBookmarkData: data) == nil
    }
}
