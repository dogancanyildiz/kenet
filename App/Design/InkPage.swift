import SwiftUI

extension View {
    /// Page chrome: paper background and hidden list/scroll system fill.
    /// Screens adopt this in a later Stage 9 pass; defined here as the shared entry point.
    func inkPage() -> some View {
        self
            .background(Color.ink.paper.ignoresSafeArea())
            .scrollContentBackground(.hidden)
    }

    /// Reading column: content is centered and at most ``InkSpacing/macPageWidth`` wide.
    /// Page-like screens (day, journal, entity, goal detail) use this on Mac and wide layouts;
    /// on a phone the limit is never reached, so it is safe to apply everywhere.
    func inkPageColumn() -> some View {
        self
            .frame(maxWidth: InkSpacing.macPageWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    /// Serif page manşet above content, plus system navigation title (inline on iOS).
    /// Inline bar title stays for scroll / back-history; manşet is the large serif title.
    /// For `List`, prefer ``InkPageTitleRow`` as the first row and this modifier for chrome only
    /// via ``inkPageNavigationTitle``.
    func inkPageTitle(_ title: LocalizedStringKey, byline: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeadline(title, byline: byline)
                .padding(.horizontal, InkSpacing.margin)
                .padding(.top, 4)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.ink.paper)
            self
        }
        .inkPageNavigationTitle(title)
    }

    /// Verbatim page manşet (vault-sourced or already localized).
    func inkPageTitle(verbatim title: String, byline: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeadline(title: title, byline: byline)
                .padding(.horizontal, InkSpacing.margin)
                .padding(.top, 4)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.ink.paper)
            self
        }
        .inkPageNavigationTitle(verbatim: title)
    }

    /// Navigation title chrome without a second manşet (use with ``InkPageTitleRow`` in a `List`).
    func inkPageNavigationTitle(_ title: LocalizedStringKey) -> some View {
        self
            .navigationTitle(title)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
    }

    func inkPageNavigationTitle(verbatim title: String) -> some View {
        self
            .navigationTitle(title)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
    }
}

/// First `List` row for a serif page manşet: no separator, paper background, page margins.
struct InkPageTitleRow: View {
    private enum Title {
        case key(LocalizedStringKey)
        case verbatim(String)
    }

    private let title: Title
    var byline: String? = nil

    init(_ title: LocalizedStringKey, byline: String? = nil) {
        self.title = .key(title)
        self.byline = byline
    }

    init(verbatim title: String, byline: String? = nil) {
        self.title = .verbatim(title)
        self.byline = byline
    }

    var body: some View {
        Group {
            switch title {
            case .key(let key):
                PageHeadline(key, byline: byline)
            case .verbatim(let text):
                PageHeadline(title: text, byline: byline)
            }
        }
        .listRowInsets(
            EdgeInsets(top: 8, leading: InkSpacing.margin, bottom: 4, trailing: InkSpacing.margin)
        )
        .listRowSeparator(.hidden)
        .listRowBackground(Color.ink.paper)
    }
}
