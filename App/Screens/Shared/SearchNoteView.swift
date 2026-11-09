import SwiftUI
import VaultFormat

struct FreeNoteComposerView: View {
    let store: IndexStore
    @State private var name = ""
    @State private var text = ""
    @State private var createdPath: String?
    @State private var errorText: String?
    @State private var isSaving = false

    var body: some View {
        Group {
            if let createdPath {
                SearchNoteView(store: store, file: createdPath)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: InkSpacing.section) {
                        InkPageTitle("Serbest not")
                        InkFilterField("Ad", text: $name, showsClearButton: false)
                        InkCard {
                            TextEditor(text: $text)
                                .font(.ink.content)
                                .foregroundStyle(.ink.text)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 220)
                        }
                        if let errorText {
                            Text(verbatim: errorText).font(.ink.meta).foregroundStyle(.ink.danger)
                        }
                        Button("Notu oluştur") { Task { await save() } }
                            .buttonStyle(InkPrimaryButtonStyle())
                            .disabled(isSaving || !store.canAddEvent || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal, InkSpacing.margin)
                    .padding(.bottom, InkSpacing.section)
                    .inkPageColumn()
                }
                .inkPage()
                .inkPageNavigationTitle("Serbest not")
            }
        }
    }

    @MainActor private func save() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            createdPath = try await store.createNote(name: name, body: text)
        } catch {
            errorText = DayEditError.message(for: error)
        }
    }
}

/// Reads the original body for display; wikilink markup and block ids are hidden in the UI only.
struct SearchNoteView: View {
    let store: IndexStore
    let file: String
    @State private var bodyText = ""
    @State private var draft = ""
    @State private var isEditing = false
    @State private var isSaving = false
    @State private var errorText: String?
    @State private var isLoaded = false
    @State private var linkedEntities: [EntitySummary] = []
    @Environment(\.inkSheetDismissAction) private var sheetDismiss
    @Environment(\.dismiss) private var dismiss

    private var noteTitle: String { SearchPreviewText.noteDisplayName(file) }

    private var masthead: some View {
        HStack(spacing: 12) {
            Text(verbatim: noteTitle).font(.ink.content).foregroundStyle(.ink.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            if file.hasPrefix("notes/"), store.canAddEvent {
                InkHeaderAction("Düzenle", systemImage: "pencil", role: .primary) {
                    draft = bodyText
                    isEditing = true
                }
            }
            SearchButton()
        }
        .frame(minHeight: TapTarget.minimumLength)
        .padding(.horizontal, InkSpacing.margin)
        .background(Color.ink.paper)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                InkScrolledMasthead(masthead)
                Group {
                    if let errorText {
                        Text(verbatim: errorText).foregroundStyle(.ink.danger)
                    } else if isLoaded {
                        VStack(alignment: .leading, spacing: InkSpacing.section) {
                            if isEditing {
                                InkCard {
                                    TextEditor(text: $draft)
                                        .font(.ink.content)
                                        .foregroundStyle(.ink.text)
                                        .scrollContentBackground(.hidden)
                                        .frame(minHeight: 220)
                                }
                                HStack {
                                    Button("Vazgeç") { isEditing = false }
                                        .buttonStyle(InkTextButtonStyle())
                                    Spacer()
                                    Button("Kaydet") { Task { await saveDraft() } }
                                        .buttonStyle(InkPrimaryButtonStyle())
                                        .disabled(isSaving || !store.canAddEvent)
                                }
                            } else {
                                InkCard {
                                    Text(verbatim: bodyText).textSelection(.enabled)
                                        .font(.ink.content)
                                        .inkJournalParagraph()
                                        .foregroundStyle(.ink.text)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            if !linkedEntities.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    SectionHeader("Bu nota bağlananlar")
                                    InkCard {
                                        ForEach(linkedEntities) { entity in
                                            NavigationLink {
                                                EntityView(store: store, entity: entity)
                                            } label: {
                                                HStack {
                                                    Text(verbatim: entity.name).foregroundStyle(.ink.text)
                                                    Spacer()
                                                    Image(systemName: "arrow.up.right").foregroundStyle(.ink.secondaryText)
                                                }.frame(minHeight: TapTarget.minimumLength)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        ProgressView("Yükleniyor…")
                    }
                }
                .padding(.horizontal, InkSpacing.margin)
            }
            .inkPageColumn()
        }
        .inkPinnedMasthead(masthead, spacing: 12)
        .inkPage()
        // Mac: keep the sheet action bar ("Kapat") on nested search destinations. iPhone keeps
        // the pushed page chrome only (back to results); adding a second "Kapat" would change it.
        #if os(macOS)
            .inkSheet(
                verbatim: noteTitle, closeIdentifier: "button.search.note.close",
                onClose: { if let sheetDismiss { sheetDismiss() } else { dismiss() } }
            )
            // System Back paints the note name beside the chevron; replace it with a title-free
            // chevron that only pops to search results ("Kapat" still dismisses the sheet).
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button("Geri", systemImage: "chevron.backward") { dismiss() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.ink.secondaryText)
                    .inkAccessibilityIdentifier("button.search.note.back")
                }
            }
        #else
            .inkPageNavigationTitle(verbatim: noteTitle)
        #endif
        .task(id: store.lastUpdated) {
            isLoaded = false
            errorText = nil
            bodyText = ""
            do {
                let document = try await store.document(at: file)
                try Task.checkCancellation()
                let raw = document.lines.dropFirst(document.frontmatterLineRange?.upperBound ?? 0)
                    .map(\.displayText).joined(separator: "\n")
                bodyText = VaultDisplayText.multiline(raw)
                draft = raw
                let targets = document.links.filter { $0.source == .body && !$0.target.isEmpty }
                linkedEntities = targets.compactMap { link in
                    store.content.entities.first { entity in
                        let normalized = link.target.lowercased().replacingOccurrences(of: ".md", with: "")
                        entity.id.lowercased().hasSuffix(normalized + ".md")
                            || entity.name.lowercased() == normalized
                            || entity.aliases.contains { $0.lowercased() == normalized }
                    }
                }.reduce(into: [EntitySummary]()) { result, entity in
                    if !result.contains(where: { $0.id == entity.id }) { result.append(entity) }
                }
                isLoaded = true
            } catch is CancellationError {
            } catch {
                errorText = DayEditError.message(for: error)
            }
        }
    }

    @MainActor private func saveDraft() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await store.saveNote(path: file, body: draft)
            bodyText = draft
            isEditing = false
        } catch {
            errorText = DayEditError.message(for: error)
        }
    }
}
