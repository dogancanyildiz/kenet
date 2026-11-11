import GoalTracking
import SwiftUI

/// The whole definition in one sheet: "Kaydet" writes only the changed fields. Deletion lives on
/// the detail page, not here.
struct GoalDefinitionForm: View {
    let store: IndexStore
    @State private var model: GoalDefinitionModel
    @State private var draft: GoalDefinitionDraft
    @State private var isSaved = false
    @State private var leavePrompt = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    init(store: IndexStore, goal: GoalDefinition) {
        self.store = store
        _model = State(initialValue: GoalDefinitionModel(store: store, goal: goal))
        _draft = State(initialValue: GoalDefinitionDraft(goal: goal))
    }

    private var isDirty: Bool { !isSaved && !model.changes(in: draft).isEmpty }

    var body: some View {
        List {
            InkPageTitleRow("Düzenle", byline: model.goal.name)
            Section {
                textField(.name, text: $draft.name, font: .ink.content)
                readOnlyRow(
                    PresentationLocalization.string(localized: "Anahtar", locale: locale), value: model.goal.key)
            }
            Section {
                scheduleRows
                if draft.kind != .milestone {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        textFieldColumn(
                            .target, text: $draft.target, font: .ink.value, isDecimal: true)
                        if model.showsUnit(draft) {
                            textFieldColumn(
                                .unit, text: $draft.unit, font: .ink.content,
                                prompt: PresentationLocalization.string(
                                    localized: "Birim (isteğe bağlı)", locale: locale))
                        }
                    }
                    .inkListRow()
                }
            }
            if let error = model.errorText {
                Section {
                    InfoBand(kind: .error, verbatim: error)
                        .inkListRow()
                }
            }
        }
        .listStyle(.plain)
        .inkPageScrollColumn()
        .disabled(model.isWriting || isSaved)
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
        .frame(minWidth: 320, minHeight: 420)
        .task(id: store.lastUpdated) { await model.load() }
        // The target is read the way the app's language writes numbers ("7.500" in Turkish).
        .onChange(of: locale, initial: true) { _, locale in model.locale = locale }
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
                    items: [GoalPeriod.day, .week, .year].map {
                        InkTabItem(
                            verbatim: GoalListPresentation.periodChip($0, locale: locale), value: $0)
                    },
                    identifier: "goal.form.period",
                    accessibilityLabelPrefix: GoalEditableField.period.title
                )
            }
            labeled(.kind) {
                InkTabs(
                    selection: $draft.kind,
                    items: [GoalKind.boolean, .number].map {
                        InkTabItem(
                            verbatim: GoalListPresentation.kindTab($0, locale: locale), value: $0)
                    },
                    identifier: "goal.form.kind",
                    accessibilityLabelPrefix: GoalEditableField.kind.title
                )
                Text("Tür değişikliği geçmiş kayıtları dönüştürmez.")
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
            }
        }
    }

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

    private func textFieldColumn(
        _ field: GoalEditableField, text: Binding<String>, font: Font, prompt: String? = nil,
        isDecimal: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: field.title)
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
                .accessibilityHidden(true)
            TextField(prompt ?? field.title, text: text)
                .font(font)
                .accessibilityLabel(Text(verbatim: field.title))
                .accessibilityIdentifier("goal.form." + field.rawValue)
                #if os(iOS)
                    .keyboardType(isDecimal ? .decimalPad : .default)
                #endif
            if let error = model.error(for: field, in: draft) {
                Text(verbatim: error)
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.danger)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

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
