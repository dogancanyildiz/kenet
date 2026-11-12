import EntityRecognition
import SwiftUI
import VaultFormat
import VaultStore

private struct MentionNoticeLifetimeKey: EnvironmentKey {
    static let defaultValue: Duration? = .seconds(2)
}

extension EnvironmentValues {
    /// How long a creation confirmation stays visible; nil disables automatic dismissal.
    var mentionNoticeLifetime: Duration? {
        get { self[MentionNoticeLifetimeKey.self] }
        set { self[MentionNoticeLifetimeKey.self] = newValue }
    }
}

/// Shared @ suggestion chips and ambiguity / unknown resolution strip (quick entry, event, journal).
struct MentionAssistStrip: View {
    @Bindable var composer: MentionComposer
    let store: IndexStore
    var insertionOffset: Int? = nil
    var isEnabled: Bool = true
    /// Invoked after a suggestion or creation edits text; argument is the caret UTF-8 offset when known.
    /// The hosts keep the focus in the field here, also after a creation that keeps the text.
    var onDidChangeText: ((Int?) -> Void)? = nil
    /// Completes the send or save the user asked for; never called for a creation made while writing.
    var onResolved: (() -> Void)? = nil

    @Environment(\.locale) private var locale
    @Environment(\.mentionNoticeLifetime) private var noticeLifetime

    /// Whether the strip should appear in a parent stack (empty strip must not consume spacing).
    var hasContent: Bool {
        composer.pendingAmbiguity != nil
            || composer.pendingUnknown != nil
            || composer.errorText != nil
            || composer.creationNotice != nil
            || (!composer.awaitingResolution && !composer.suggestions(at: insertionOffset).isEmpty)
            || (!composer.awaitingResolution && (composer.suggestionRange(at: insertionOffset)?.count ?? 0) > 1)
    }

    var body: some View {
        if hasContent {
            VStack(alignment: .leading, spacing: 8) {
                interactiveContent
                    .disabled(composer.isCreating || !isEnabled)
                if let error = composer.errorText {
                    InfoBand(kind: .error, verbatim: error)
                }
                if let notice = composer.creationNotice {
                    creationNoticeRow(notice)
                }
            }
            // A card of its own: the strip sits over the page's content (the goal cards on
            // Bugün, a calendar card on iPad), never transparently on top of it.
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .inkSurface(bordered: true, cornerRadius: InkCorner.md)
            .onAppear { announceResolutionIfNeeded() }
            .onChange(of: announcementKey) { _, _ in announceResolutionIfNeeded() }
        }
    }

    private func creationNoticeRow(_ notice: MentionComposer.CreationNotice) -> some View {
        Text(verbatim: noticeText(notice))
            .font(.ink.meta)
            .foregroundStyle(Color.ink.secondaryText)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .task(id: notice) {
                guard let noticeLifetime else { return }
                try? await Task.sleep(for: noticeLifetime)
                guard !Task.isCancelled, composer.creationNotice == notice else { return }
                composer.creationNotice = nil
            }
    }

    private func noticeText(_ notice: MentionComposer.CreationNotice) -> String {
        Self.noticeText(notice, types: store.entityTypes, language: locale.language.languageCode?.identifier ?? "en")
    }

    static func noticeText(
        _ notice: MentionComposer.CreationNotice, types: EntityTypeCatalog, language: String
    ) -> String {
        switch notice.kind {
        case .person:
            return String(localized: "\(notice.name) kişi olarak eklendi")
        case .place:
            return String(localized: "\(notice.name) konum olarak eklendi")
        case .custom(let id):
            let type = EntityTypeChoices.choices(types, language: language).first { $0.id == id }?.name ?? id
            return String(localized: "\(notice.name) \(type) olarak eklendi")
        }
    }

    private func announceResolutionIfNeeded() {
        guard let announcementKey else { return }
        AccessibilityNotification.Announcement(announcementKey).post()
    }

    @ViewBuilder private var interactiveContent: some View {
        resolutionStrip
        if !composer.awaitingResolution {
            ForEach(composer.suggestions(at: insertionOffset), id: \.file) { entity in
                Button {
                    let caret = composer.selectSuggestion(entity, at: insertionOffset)
                    onDidChangeText?(caret)
                } label: {
                    // The suggestion list does not scroll sideways: a long name stays in the strip.
                    MentionEntityLabel(entity: entity, fit: .wraps)
                        .tapTarget()
                }
                .buttonStyle(.plain)
            }
        }
        if !composer.awaitingResolution, let range = composer.suggestionRange(at: insertionOffset),
            range.count > 1
        {
            InkFlowLayout(spacing: 16, lineSpacing: 0) {
                Button {
                    beginCreation(.person)
                } label: {
                    Text("Yeni kişi oluştur")
                        .tapTarget()
                }
                .buttonStyle(StripActionStyle())
                Button {
                    beginCreation(.place)
                } label: {
                    Text("Yeni konum oluştur")
                        .tapTarget()
                }
                .buttonStyle(StripActionStyle())
                Menu("Özel tip olarak ekle") {
                    ForEach(
                        EntityTypeChoices.choices(
                            store.entityTypes, language: locale.language.languageCode?.identifier ?? "en"
                        ).filter {
                            $0.id != "person" && $0.id != "place"
                        }
                    ) { type in
                        Button {
                            beginCreation(type.kind)
                        } label: {
                            Text("\(type.name) olarak ekle")
                        }
                    }
                }
                .font(.ink.meta.weight(.semibold))
                .lineLimit(1)
                .fixedSize()
                .frame(minHeight: InkButtonChrome.minimumHeight)
                .disabled(store.entityTypes.types.isEmpty)
            }
        }
    }

    private var announcementKey: String? {
        if let mention = composer.pendingAmbiguity {
            return String(localized: "\(mention.spelling): hangisi?")
        }
        if let mention = composer.pendingUnknown {
            return String(localized: "Bilinmeyen anma: \(mention.spelling)")
        }
        if let notice = composer.creationNotice {
            return noticeText(notice)
        }
        return nil
    }

    @ViewBuilder private var resolutionStrip: some View {
        if let mention = composer.pendingAmbiguity {
            Text("\(mention.spelling): hangisi?")
                .font(.ink.meta)
                .foregroundStyle(Color.ink.text)
            ScrollView(.horizontal) {
                HStack {
                    ForEach(mention.candidates, id: \.file) { entity in
                        Button {
                            composer.choose(entity, for: mention)
                            onResolved?()
                        } label: {
                            MentionEntityLabel(entity: entity, fit: .oneLine)
                                .modifier(CandidatePill())
                                .tapTarget()
                        }
                        .buttonStyle(.plain)
                    }
                    Button("Bağlamadan devam et") {
                        composer.skip(mention)
                        onResolved?()
                    }
                    .buttonStyle(StripActionStyle())
                }
            }
        } else if let mention = composer.pendingUnknown {
            Text(verbatim: mention.spelling)
                .font(.ink.meta)
                .foregroundStyle(Color.ink.text)
            if composer.needsQualifier {
                TextField("Ayırt edici (ör. iş)", text: $composer.qualifier)
                    .textFieldStyle(.plain)
                    .font(.ink.content)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.ink.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: InkSize.chipCorner, style: .continuous)
                            .strokeBorder(Color.ink.control, lineWidth: InkStroke.control)
                    }
                Button("Oluştur") {
                    if let kind = composer.creationKind { create(kind) }
                }
                .buttonStyle(StripActionStyle())
                .disabled(composer.qualifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else {
                // One line per action, wrapping to the next row when the strip is narrow.
                InkFlowLayout(spacing: 16, lineSpacing: 0) {
                    Button("Kişi olarak ekle") { create(.person) }
                        .buttonStyle(StripActionStyle())
                    Button("Konum olarak ekle") { create(.place) }
                        .buttonStyle(StripActionStyle())
                    Menu("Özel tip olarak ekle") {
                        ForEach(
                            EntityTypeChoices.choices(
                                store.entityTypes, language: locale.language.languageCode?.identifier ?? "en"
                            ).filter {
                                $0.id != "person" && $0.id != "place"
                            }
                        ) { type in
                            Button {
                                create(type.kind)
                            } label: {
                                Text("\(type.name) olarak ekle")
                            }
                        }
                    }
                    .font(.ink.meta.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .frame(minHeight: InkButtonChrome.minimumHeight)
                    .disabled(store.entityTypes.types.isEmpty)
                }
            }
            Button("Vazgeç") {
                let followUp = composer.dismissCreation(mention)
                onDidChangeText?(nil)
                Self.finish(followUp, onResolved: onResolved)
            }
            .buttonStyle(StripActionStyle())
        }
    }

    private func beginCreation(_ kind: VaultEntityKind) {
        let offset = insertionOffset
        Task { @MainActor in
            let followUp = await composer.beginCreation(kind, at: offset)
            onDidChangeText?(nil)
            Self.finish(followUp, onResolved: onResolved)
        }
    }

    private func create(_ kind: VaultEntityKind) {
        Task { @MainActor in
            let followUp = await composer.create(kind)
            onDidChangeText?(nil)
            Self.finish(followUp, onResolved: onResolved)
        }
    }

    /// Hands a finished step back to the host: only a send or save the user asked for goes on.
    static func finish(_ followUp: MentionComposer.CreationFollowUp?, onResolved: (() -> Void)?) {
        guard followUp == .commit else { return }
        onResolved?()
    }
}

/// The outline of a "hangisi?" candidate, as the quick entry's chips are drawn.
private struct CandidatePill: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 8 - InkStroke.control).padding(.vertical, 4 - InkStroke.control)
            .background(Color.ink.well, in: Capsule())
            .padding(InkStroke.control)
            .background(Color.ink.control, in: Capsule())
    }
}

/// The strip's text actions: the text button's colors at the strip's meta size, on one line,
/// so "Kişi olarak ekle" never breaks inside the card.
private struct StripActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let role = InkButtonChrome.text.role(isPressed: configuration.isPressed, isEnabled: isEnabled)
        return configuration.label
            .font(.ink.meta.weight(.semibold))
            .foregroundStyle(InkButtonChrome.color(for: role.foreground))
            .lineLimit(1)
            .fixedSize()
            .frame(minHeight: InkButtonChrome.minimumHeight)
            .contentShape(Rectangle())
    }
}

/// The name, then its qualifier in parentheses in the secondary color ("Mert Aksu (iş)"), as the
/// file is named.
struct MentionEntityLabel: View {
    enum Fit {
        /// Its full width on one line: the candidate row scrolls sideways.
        case oneLine
        /// Held to the strip's width: cut with "…", wrapped at accessibility sizes.
        case wraps
    }

    let entity: KnownEntity
    let fit: Fit
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        switch fit {
        case .oneLine:
            label.lineLimit(1).fixedSize()
        case .wraps:
            label
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var label: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(verbatim: entity.name)
                .foregroundStyle(color)
                // The name keeps its room; the qualifier gives way first.
                .layoutPriority(1)
            if let qualifier = entity.qualifier {
                Text(verbatim: "(\(qualifier))")
                    .foregroundStyle(Color.ink.secondaryText)
            }
        }
        .font(.ink.meta)
    }

    private var color: Color {
        switch entity.kind {
        case .person: Color.ink.person
        case .place: Color.ink.place
        default: Color.ink.text
        }
    }
}
