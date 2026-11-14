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
                        ForEach(Array(shown.enumerated()), id: \.offset) { _, alias in
                            TagChip(
                                title: alias, onDismiss: { Task { await model.removeAlias(alias) } },
                                dismissLabel: Text("Takma adı kaldır: \(alias)"))
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

    private func add() {
        let text = draft
        Task {
            if await model.addAlias(text, name: name) { draft = "" }
            isFocused = true
        }
    }
}
