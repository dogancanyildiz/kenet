import SwiftUI
import VaultFormat

struct EntityTypedFieldEditor: View {
    let definition: EntityTypeField
    let model: EntityDetailModel
    @State private var text: String
    @State private var date: Date
    @State private var flag: Bool
    @State private var invalid = false
    @State private var deleteConfirmation = DestructiveConfirmation<DestructiveConfirmationToken>()

    init(definition: EntityTypeField, value: FrontmatterValue?, model: EntityDetailModel) {
        self.definition = definition
        self.model = model
        let scalar: FrontmatterScalar?
        if case .scalar(let value) = value { scalar = value } else { scalar = nil }
        _text = State(initialValue: scalar?.text ?? "")
        if case .date(let day) = scalar?.kind {
            _date = State(initialValue: LocalDay.instant(for: day))
        } else {
            _date = State(initialValue: Date())
        }
        if case .boolean(let value) = scalar?.kind {
            _flag = State(initialValue: value)
        } else {
            _flag = State(initialValue: false)
        }
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text(verbatim: definition.key).font(.headline)
            switch definition.kind {
            case .date: DatePicker("Değer", selection: $date, displayedComponents: .date)
            case .boolean: Toggle("Değer", isOn: $flag)
            case .text, .number, .link: TextField("Değer", text: $text).onSubmit { save() }
            }
            HStack {
                Button("Kaydet") { save() }
                Button("Alanı kaldır", role: .destructive) { deleteConfirmation.request(.pending) }
            }
            if invalid { Text("Alan için geçerli bir değer gir.").font(.caption).foregroundStyle(.red) }
        }
        .disabled(!model.canEdit)
        .destructiveConfirmationDialog(
            "Alanı kaldır?", confirmation: $deleteConfirmation, confirmTitle: "Alanı kaldır"
        ) { _ in
            Task { await model.remove(definition.key) }
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
        Task { await model.set(definition.key, to: value) }
    }
}
