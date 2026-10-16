import GoalTracking
import SwiftUI

/// The whole definition in one sheet: "Kaydet" writes only the changed fields. "Hedefi sil" is
/// the last row; after it the sheet closes and the detail behind it goes too (`GoalDetailView`).
struct GoalDefinitionForm: View {
    let store: IndexStore
    /// Owned by the detail page, which closes after the sheet once the file is gone.
    @Bindable var deletion: DefinitionDeletionModel
    @State private var model: GoalDefinitionModel
    @State private var draft: GoalDefinitionDraft
    @State private var isSaved = false
    @State private var leavePrompt = false
    @Environment(\.dismiss) private var dismiss

    init(store: IndexStore, goal: GoalDefinition, deletion: DefinitionDeletionModel) {
        self.store = store
        self.deletion = deletion
        _model = State(initialValue: GoalDefinitionModel(store: store, goal: goal))
        _draft = State(initialValue: GoalDefinitionDraft(goal: goal))
    }

    private var isDirty: Bool { !isSaved && !model.changes(in: draft).isEmpty }

    var body: some View {
        List {
            InkPageTitleRow("Düzenle", byline: model.goal.name)
            Section {
                SectionHeader("Hedef")
                    .inkListRow()
                textField(.name, text: $draft.name, font: .ink.content)
                readOnlyRow(String(localized: "Anahtar"), value: model.goal.key)
            }
            Section {
                SectionHeader("Ayarlar")
                    .inkListRow()
                scheduleRows
                if draft.kind != .milestone {
                    textField(.target, text: $draft.target, font: .ink.value, isDecimal: true)
                }
                if model.showsUnit(draft) {
                    textField(
                        .unit, text: $draft.unit, font: .ink.content,
                        prompt: String(localized: "Birim (isteğe bağlı)"))
                }
            }
            if let error = model.errorText {
                Section {
                    InfoBand(kind: .error, verbatim: error)
                        .inkListRow()
                }
            }
            deleteRow
        }
        .listStyle(.plain)
        .inkPageScrollColumn()
        .disabled(model.isWriting || isSaved || deletion.isDeleting)
        .inkSheet(
            "Düzenle", isConfirmEnabled: !isSaved && model.canSave(draft), isBusy: model.isWriting,
            isCancelEnabled: !model.isWriting, cancelIdentifier: "button.goal.form.cancel",
            confirmIdentifier: "button.goal.form.save", onCancel: requestLeave,
            onConfirm: {
                Task {
                    isSaved = await model.apply(draft)
                    if isSaved && model.errorText == nil { dismiss() }
                }
            }
        )
        .interactiveDismissDisabled(model.isWriting || isDirty)
        .confirmationDialog("Kaydedilmemiş değişiklikler", isPresented: $leavePrompt) {
            Button("Değişiklikleri at", role: .destructive) { dismiss() }
            Button("Düzenlemeye devam et", role: .cancel) {}
        }
        .destructiveConfirmationDialog(
            "Hedefi sil", confirmation: $deletion.confirmation,
            confirmTitle: "Hedefi sil", message: "\(model.goal.name) silinsin mi? Gün kayıtları kalır."
        ) { path in
            Task { if await deletion.delete(store: store, path: path, goal: true) { dismiss() } }
        }
        .frame(minWidth: 320, minHeight: 420)
    }

    /// Period and kind: tabs (two or three choices), or plain rows on a milestone, which keeps both.
    @ViewBuilder private var scheduleRows: some View {
        if model.isScheduleLocked {
            readOnlyRow(GoalEditableField.period.title, value: model.goal.period.title)
            readOnlyRow(GoalEditableField.kind.title, value: model.goal.kind.title)
            Text("Kilometre taşının dönemi ve türü değişmez.")
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
                .inkListRow()
        } else {
            labeled(.period) {
                InkTabs(
                    selection: $draft.period,
                    items: [GoalPeriod.day, .week, .year].map { InkTabItem(verbatim: $0.title, value: $0) },
                    identifier: "goal.form.period",
                    accessibilityLabelPrefix: GoalEditableField.period.title
                )
            }
            labeled(.kind) {
                InkTabs(
                    selection: $draft.kind,
                    items: [GoalKind.boolean, .number].map { InkTabItem(verbatim: $0.title, value: $0) },
                    identifier: "goal.form.kind",
                    accessibilityLabelPrefix: GoalEditableField.kind.title
                )
                Text("Tür değişikliği geçmiş kayıtları dönüştürmez.")
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
            }
        }
    }

    private var deleteRow: some View {
        VStack(alignment: .leading, spacing: InkSpacing.section) {
            Button("Hedefi sil", role: .destructive) { deletion.request(path: model.goal.id) }
                .buttonStyle(InkDestructiveButtonStyle())
                .disabled(!model.canEdit || deletion.isDeleting || deletion.isDeleted)
                .accessibilityIdentifier("button.goal.delete")
            if let error = deletion.errorText {
                InfoBand(kind: .error, verbatim: error)
            }
        }
        .padding(.top, InkSpacing.section)
        .inkListRow()
    }

    /// Visible label above the control; VoiceOver reads the control with the same label.
    private func labeled<Content: View>(
        _ field: GoalEditableField, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: field.title)
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
                .accessibilityHidden(true)
            content()
            if let error = model.error(for: field, in: draft) {
                Text(verbatim: error)
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.danger)
            }
        }
        .inkListRow()
    }

    private func textField(
        _ field: GoalEditableField, text: Binding<String>, font: Font, prompt: String? = nil,
        isDecimal: Bool = false
    ) -> some View {
        labeled(field) {
            TextField(prompt ?? field.title, text: text)
                .font(font)
                .accessibilityLabel(Text(verbatim: field.title))
                .accessibilityIdentifier("goal.form." + field.rawValue)
                #if os(iOS)
                    .keyboardType(isDecimal ? .decimalPad : .default)
                #endif
        }
    }

    /// A value the form shows but does not edit: the key, and a milestone's period and kind.
    private func readOnlyRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: title)
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
            Spacer(minLength: 12)
            Text(verbatim: value)
                .font(.ink.content)
                .foregroundStyle(Color.ink.secondaryText)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
        .inkListRow()
    }

    private func requestLeave() {
        guard !model.isWriting else { return }
        if UnsavedDraftDecision.canLeaveImmediately(isDirty: isDirty, isSaving: model.isWriting) {
            dismiss()
        } else {
            leavePrompt = true
        }
    }
}
