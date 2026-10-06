import SwiftUI
import VaultFormat

struct EntityScalarEditor: View {
    let scalar: FrontmatterScalar
    let save: (FrontmatterLiteral) async -> Void
    @State private var text: String
    @State private var flag: Bool
    @State private var date: Date
    @State private var invalid = false

    init(scalar: FrontmatterScalar, save: @escaping (FrontmatterLiteral) async -> Void) {
        self.scalar = scalar
        self.save = save
        _text = State(initialValue: scalar.text)
        if case .boolean(let value) = scalar.kind {
            _flag = State(initialValue: value)
        } else {
            _flag = State(initialValue: false)
        }
        if case .date(let day) = scalar.kind {
            _date = State(initialValue: LocalDay.instant(for: day))
        } else {
            _date = State(initialValue: Date())
        }
    }

    var body: some View {
        HStack {
            switch scalar.kind {
            case .boolean:
                Toggle("Değer", isOn: $flag).labelsHidden()
                    .onChange(of: flag) { Task { await save(.boolean(flag)) } }
            case .date:
                DatePicker("Değer", selection: $date, displayedComponents: .date).labelsHidden()
                    .onChange(of: date) { Task { await save(.date(LocalDay.today(at: date))) } }
            case .text, .empty, .number:
                TextField("Değer", text: $text).onSubmit { submit() }
                Button("Kaydet") { submit() }.buttonStyle(.borderless)
            }
        }
        if invalid { Text("Geçerli bir sayı gir.").font(.ink.meta).foregroundStyle(.ink.danger) }
    }

    private func submit() {
        let value: FrontmatterLiteral
        if scalar.kind == .number && !text.isEmpty {
            let document = RawDocument(bytes: ("---\nvalue: " + text + "\n---\n").utf8)
            guard case .parsed(let fields) = document.frontmatter,
                case .scalar(let number) = fields.field(named: "value")?.value,
                number.kind == .number, !text.contains(where: { $0.isWhitespace })
            else {
                invalid = true
                return
            }
            value = .number(text)
        } else {
            value = .text(text)
        }
        invalid = false
        Task { await save(value) }
    }
}
