import EntityRecognition
import SwiftUI
import VaultFormat
import VaultStore

/// Shared @ suggestion chips and ambiguity / unknown resolution strip (quick entry, event, journal).
struct MentionAssistStrip: View {
    @Bindable var composer: MentionComposer
    let store: IndexStore
    var insertionOffset: Int? = nil
    var isEnabled: Bool = true
    /// Invoked after a suggestion or creation edits text; argument is the caret UTF-8 offset when known.
    var onDidChangeText: ((Int?) -> Void)? = nil
    var onResolved: (() -> Void)? = nil

    @Environment(\.locale) private var locale

    /// Whether the strip should appear in a parent stack (empty strip must not consume spacing).
    var hasContent: Bool {
        composer.pendingAmbiguity != nil
            || composer.pendingUnknown != nil
            || composer.errorText != nil
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
            }
            .onAppear { announceResolutionIfNeeded() }
            .onChange(of: announcementKey) { _, _ in announceResolutionIfNeeded() }
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
                    entityLabel(entity)
                        .tapTarget()
                }
                .buttonStyle(.plain)
            }
        }
        if !composer.awaitingResolution, let range = composer.suggestionRange(at: insertionOffset),
            range.count > 1
        {
            HStack {
                Button {
                    beginCreation(.person)
                } label: {
                    Text("Yeni kişi oluştur")
                        .tapTarget()
                }
                .buttonStyle(InkTextButtonStyle())
                Button {
                    beginCreation(.place)
                } label: {
                    Text("Yeni konum oluştur")
                        .tapTarget()
                }
                .buttonStyle(InkTextButtonStyle())
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
                }.disabled(store.entityTypes.types.isEmpty)
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
                            entityLabel(entity)
                                .tapTarget()
                        }
                        .buttonStyle(.plain)
                    }
                    Button("Bağlamadan devam et") {
                        composer.skip(mention)
                        onResolved?()
                    }
                    .buttonStyle(InkTextButtonStyle())
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
                .buttonStyle(InkTextButtonStyle())
                .disabled(composer.qualifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else {
                HStack {
                    Button("Kişi olarak ekle") { create(.person) }
                        .buttonStyle(InkTextButtonStyle())
                    Button("Konum olarak ekle") { create(.place) }
                        .buttonStyle(InkTextButtonStyle())
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
                    }.disabled(store.entityTypes.types.isEmpty)
                }
            }
            Button("Vazgeç") {
                composer.dismissUnknown(mention)
                onDidChangeText?(nil)
                onResolved?()
            }
            .buttonStyle(InkTextButtonStyle())
        }
    }

    private func entityLabel(_ entity: KnownEntity) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: entity.name)
                .font(.ink.meta)
                .foregroundStyle(entityColor(entity))
            if let qualifier = entity.qualifier {
                Text(verbatim: qualifier)
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
            }
        }
    }

    private func entityColor(_ entity: KnownEntity) -> Color {
        switch entity.kind {
        case .person: Color.ink.person
        case .place: Color.ink.place
        default: Color.ink.text
        }
    }

    private func beginCreation(_ kind: VaultEntityKind) {
        let offset = insertionOffset
        Task { @MainActor in
            await composer.beginCreation(kind, at: offset)
            onDidChangeText?(nil)
            if !composer.needsQualifier && composer.errorText == nil { onResolved?() }
        }
    }

    private func create(_ kind: VaultEntityKind) {
        Task { @MainActor in
            await composer.create(kind)
            onDidChangeText?(nil)
            if !composer.needsQualifier && composer.errorText == nil { onResolved?() }
        }
    }
}
