import SwiftUI
import VaultFormat

struct EntityTypedFieldEditor: View {
    let definition: EntityTypeField
    let model: EntityDetailModel
    @Environment(\.entityEditorDraft) private var draft
    @State private var text: String
    @State private var date: Date
    @State private var flag: Bool
    @State private var invalid = false
    @State private var saveFailed = false
    @State private var savedText: String
    @State private var savedDate: Date
    @State private var savedFlag: Bool
    @State private var deleteConfirmation = DestructiveConfirmation<DestructiveConfirmationToken>()

    private var draftID: String { "typed:" + definition.key }

    init(definition: EntityTypeField, value: FrontmatterValue?, model: EntityDetailModel) {
        self.definition = definition
        self.model = model
        let scalar: FrontmatterScalar?
        if case .scalar(let value) = value { scalar = value } else { scalar = nil }
        let initialText = scalar?.text ?? ""
        _text = State(initialValue: initialText)
        _savedText = State(initialValue: initialText)
        let initialDate: Date
        if case .date(let day) = scalar?.kind {
            initialDate = LocalDay.instant(for: day)
        } else {
            initialDate = Date()
        }
        _date = State(initialValue: initialDate)
        _savedDate = State(initialValue: initialDate)
        let initialFlag: Bool
        if case .boolean(let value) = scalar?.kind {
            initialFlag = value
        } else {
            initialFlag = false
        }
        _flag = State(initialValue: initialFlag)
        _savedFlag = State(initialValue: initialFlag)
    }

    private var isDirty: Bool {
        switch definition.kind {
        case .text, .number, .link: text != savedText
        case .date: LocalDay.today(at: date) != LocalDay.today(at: savedDate)
        case .boolean: flag != savedFlag
        }
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text(verbatim: definition.key).font(.ink.section).foregroundStyle(.ink.text)
            switch definition.kind {
            case .date: DatePicker("Değer", selection: $date, displayedComponents: .date)
            case .boolean: Toggle("Değer", isOn: $flag)
            case .text, .number, .link: TextField("Değer", text: $text).onSubmit { save() }
            }
            HStack {
                Button("Kaydet") { save() }
                Button("Alanı kaldır", role: .destructive) { deleteConfirmation.request(.pending) }
            }
            if invalid {
                Text("Alan için geçerli bir değer gir.").font(.ink.meta).foregroundStyle(.ink.danger)
            } else if saveFailed {
                Text(
                    verbatim: model.errorText
                        ?? String(localized: "Değişiklik kaydedilemedi. Kasayı kontrol edip yeniden dene.")
                )
                .font(.ink.meta).foregroundStyle(.ink.danger)
            }
        }
        .disabled(!model.canEdit)
        .onAppear { draft?.report(id: draftID, dirty: isDirty) }
        .onChange(of: text) { draft?.report(id: draftID, dirty: isDirty) }
        .onChange(of: date) { draft?.report(id: draftID, dirty: isDirty) }
        .onChange(of: flag) { draft?.report(id: draftID, dirty: isDirty) }
        .onChange(of: savedText) { draft?.report(id: draftID, dirty: isDirty) }
        .onChange(of: savedDate) { draft?.report(id: draftID, dirty: isDirty) }
        .onChange(of: savedFlag) { draft?.report(id: draftID, dirty: isDirty) }
        .destructiveConfirmationDialog(
            "Alanı kaldır?", confirmation: $deleteConfirmation, confirmTitle: "Alanı kaldır"
        ) { _ in
            Task {
                if await model.remove(definition.key) {
                    draft?.clear(id: draftID)
                    // Schema-defined fields stay on screen with a nil value; reset local state
                    // so typed text does not linger after a successful remove.
                    text = ""
                    savedText = ""
                    date = Date()
                    savedDate = date
                    flag = false
                    savedFlag = false
                    invalid = false
                    saveFailed = false
                }
            }
        }
    }

    private func save() {
        let value: FrontmatterLiteral
        do {
            switch definition.kind {
            case .date: value = .date(LocalDay.today(at: date))
            case .boolean: value = .boolean(flag)
            default: value = try EntityTypedField.literal(text, kind: definition.kind)
            }
        } catch {
            invalid = true
            return
        }
        invalid = false
        let committedText = text
        let committedDate = date
        let committedFlag = flag
        Task {
            let success = await model.set(definition.key, to: value)
            saveFailed = !success
            var nextText = savedText
            var nextDate = savedDate
            var nextFlag = savedFlag
            EntityEditorSaveMark.commitIfSaved(committedText, success: success, into: &nextText)
            EntityEditorSaveMark.commitIfSaved(committedDate, success: success, into: &nextDate)
            EntityEditorSaveMark.commitIfSaved(committedFlag, success: success, into: &nextFlag)
            savedText = nextText
            savedDate = nextDate
            savedFlag = nextFlag
            draft?.report(id: draftID, dirty: isDirty)
        }
    }
}
