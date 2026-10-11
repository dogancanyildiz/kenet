import SwiftUI

/// One shipped package's license. The text is the upstream LICENSE file, bundled and not translated.
struct ThirdPartyNotice: Identifiable, Equatable, Sendable {
    /// Package name as shown. Matches the `Package.resolved` identity ignoring case (`GRDB.swift`).
    let name: String
    /// SPDX identifier. A proper name, so it is not translated.
    let license: String
    /// Unmodified license text. Empty when the bundled file cannot be read.
    let text: String

    var id: String { name }
}

/// Packages linked into the app. Test-target packages are not listed; `ThirdPartyLicenseTests`
/// checks the set against `Package.resolved` and `project.yml`.
enum ThirdPartyNotices {
    struct Source: Equatable, Sendable {
        let name: String
        let license: String
        /// Bundle resource of the unmodified LICENSE file (`name.extension`).
        let resourceName: String
        let resourceExtension: String
    }

    static let sources: [Source] = [
        Source(
            name: "GRDB.swift", license: "MIT", resourceName: "GRDB.swift.LICENSE", resourceExtension: "txt")
    ]

    static func load(from bundle: Bundle = .main) -> [ThirdPartyNotice] {
        sources.map { source in
            ThirdPartyNotice(
                name: source.name, license: source.license, text: text(for: source, in: bundle))
        }
    }

    /// The host `.app` when unit tests are running inside the plug-in; the app itself otherwise.
    static func applicationBundle(_ bundle: Bundle = .main) -> Bundle {
        var url = bundle.bundleURL
        for _ in 0..<6 {
            if url.pathExtension == "app", let app = Bundle(url: url) { return app }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { break }
            url = parent
        }
        return bundle
    }

    static func text(for source: Source, in bundle: Bundle = .main) -> String {
        guard let url = resourceURL(source, in: bundle),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return text
    }

    private static func resourceURL(_ source: Source, in bundle: Bundle) -> URL? {
        let app = applicationBundle(bundle)
        if let url = app.url(forResource: source.resourceName, withExtension: source.resourceExtension) {
            return url
        }
        return app.url(
            forResource: "\(source.resourceName).\(source.resourceExtension)", withExtension: nil)
    }
}

/// Read-only list of shipped third-party licenses. Pushed on iPhone; shown in place of the
/// Tanılama tab on Mac.
struct ThirdPartyLicensesView: View {
    private let notices: [ThirdPartyNotice]

    init(bundle: Bundle = .main) {
        notices = ThirdPartyNotices.load(from: bundle)
    }

    var body: some View {
        List {
            #if os(iOS)
                InkPageTitleRow("Üçüncü taraf lisansları")
            #endif
            ForEach(notices) { notice in
                Section {
                    SectionHeader(title: notice.name)
                        .inkListRow()
                    LabeledContent("Lisans") {
                        Text(verbatim: notice.license)
                            .font(.ink.value)
                    }
                    .inkListRow()
                    Text(verbatim: notice.text)
                        .font(.ink.byline)
                        .foregroundStyle(Color.ink.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .inkListRow()
                }
            }
        }
        .listStyle(.plain)
        .inkPageNavigationTitle("Üçüncü taraf lisansları")
        .inkPageScrollColumn()
        .inkPage()
        .accessibilityIdentifier("screen.settings.licenses")
    }
}
