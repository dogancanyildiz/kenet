import SwiftUI

/// Quick alias sheet of the entity page: one field that adds, and the current aliases as chips
/// that remove. Each action writes at once, so the sheet has a single "Kapat".
struct EntityAliasSheet: View {
    let model: EntityDetailModel
    let name: String
    @State private var draft: String
    @FocusState private var isFocused: Bool

    /// `draft`: text already in the field (a test draws the sheet mid-entry).
    init(model: EntityDetailModel, name: String, draft: String = "") {
        self.model = model
        self.name = name
        _draft = State(initialValue: draft)
    }

    private var shown: [String] { model.aliases.filter { !EntityAliasRules.cleaned($0).isEmpty } }

    /// Names the draft and the saved aliases share with another record.
    private var conflictNotes: [String] {
        ([draft] + shown).flatMap { text in
            EntityAliasRules.conflicts(text, path: model.path, entities: model.store.content.entities).map {
                String(
                    localized:
                        "“\(EntityAliasRules.cleaned(text))” \($0.name) ile de eşleşiyor. Uygulama bu adı sen seçmeden bağlamaz."
                )
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                InkPageTitleRow("Takma adlar")
                Text("Uygulama bu adları yazarken tanır ve \(name) kaydına bağlar.")
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .inkListRow()
                HStack(spacing: InkSpacing.section) {
                    TextField("Takma ad", text: $draft)
                        .font(.ink.content)
                        .focused($isFocused)
                        .submitLabel(.done)
                        .autocorrectionDisabled()
                        .onSubmit(add)
                        .accessibilityIdentifier("field.alias.new")
                        .modifier(InkFieldBox(isFocused: isFocused))
                    Button("Ekle", action: add)
                        .buttonStyle(EntityEditorLinkStyle())
                        .disabled(EntityAliasRules.cleaned(draft).isEmpty || !model.canEdit)
                        .accessibilityLabel("Takma ad ekle")
                        .accessibilityIdentifier("button.alias.add")
                }
                .inkListRow()
                if let error = model.aliasErrorText {
                    InfoBand(kind: .error, verbatim: error)
                        .accessibilityIdentifier("band.alias.error")
                        .inkListRow()
                }
                ForEach(conflictNotes, id: \.self) { note in
                    InfoBand(kind: .info, verbatim: note).inkListRow()
                }
                if !shown.isEmpty {
                    InkFlowLayout {
                        ForEach(EntityAliasRules.chips(model.aliases), id: \.id) { chip in
                            TagChip(
                                title: chip.text, onDismiss: { Task { await model.removeAlias(chip.text) } },
                                dismissLabel: Text("Takma adı kaldır: \(chip.text)"))
                        }
                    }
                    .disabled(!model.canEdit)
                    .inkListRow()
                }
            }
            .listStyle(.plain)
            .inkPageScrollColumn()
            .inkSheet("Takma adlar", closeIdentifier: "button.alias.close")
            .accessibilityIdentifier("sheet.alias")
            .interactiveDismissDisabled(model.isWriting)
            .onAppear { isFocused = true }
            .onDisappear { model.clearAliasError() }
        }
    }

    /// The field empties only when it still holds the text that was added: what the user typed
    /// while the write ran stays.
    static func draft(_ current: String, afterAdding text: String, added: Bool) -> String {
        added && current == text ? "" : current
    }

    private func add() {
        let text = draft
        guard !EntityAliasRules.cleaned(text).isEmpty else { return }
        Task {
            let added = await model.addAlias(text, name: name)
            draft = Self.draft(draft, afterAdding: text, added: added)
            isFocused = true
        }
    }
}
