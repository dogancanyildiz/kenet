import EntityRecognition
import SwiftUI
import VaultStore

struct QuickEntryBar: View {
    let store: IndexStore
    let isEnabled: Bool
    @State private var model: QuickEntryModel
    @State private var selection: TextSelection?
    @FocusState private var isFocused: Bool

    init(store: IndexStore, isEnabled: Bool) {
        self.store = store
        self.isEnabled = isEnabled
        _model = State(initialValue: QuickEntryModel(store: store))
    }

    private var insertionOffset: Int? {
        if let selection, case .selection(let range) = selection.indices {
            return model.text[..<range.lowerBound].utf8.count
        }
        return nil
    }

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 8) {
            if isEnabled, let error = store.entryErrorText {
                Text(verbatim: error).font(.caption).foregroundStyle(.red)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            resolutionStrip
                .disabled(model.isCreating || model.isSubmitting || !isEnabled)
            if !model.awaitingResolution {
                ForEach(model.suggestions(at: insertionOffset), id: \.file) { entity in
                    Button {
                        model.selectSuggestion(entity, at: insertionOffset)
                        selection = nil
                        isFocused = true
                    } label: {
                        entityLabel(entity)
                    }
                    .buttonStyle(.plain)
                    .disabled(!isEnabled || !model.canSubmit)
                }
            }
            if !model.awaitingResolution, let range = model.suggestionRange(at: insertionOffset), range.count > 1 {
                HStack {
                    Button("Yeni kişi oluştur") { beginCreation(.person) }
                    Button("Yeni konum oluştur") { beginCreation(.place) }
                }
                .disabled(!isEnabled || !model.canSubmit)
            }
            if let error = model.errorText {
                Text(verbatim: error).font(.caption).foregroundStyle(.red)
            }
            HStack {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Button {
                        model.includesTime.toggle()
                    } label: {
                        if model.includesTime {
                            Text(context.date, format: .dateTime.hour().minute())
                                .monospacedDigit()
                        } else {
                            Image(systemName: "clock.badge.xmark")
                        }
                    }
                    .accessibilityLabel(model.includesTime ? Text("Saati kaldır") : Text("Şu anki saati ekle"))
                    .disabled(!isEnabled || store.isWriting)
                }
                TextField("Gününden bir an…", text: $model.text, selection: $selection)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Hızlı giriş")
                    .focused($isFocused)
                    .disabled(!isEnabled)
                    .onSubmit { submit() }
                Button("Gönder", systemImage: "arrow.up.circle.fill") { submit() }
                    .labelStyle(.iconOnly)
                    .disabled(!isEnabled || !model.canSubmit)
            }
        }
        .padding()
        .background(.bar)
    }

    private func entityLabel(_ entity: KnownEntity) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: entity.name)
            if let qualifier = entity.qualifier {
                Text(verbatim: qualifier).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var resolutionStrip: some View {
        @Bindable var model = model
        if let mention = model.pendingAmbiguity {
            Text("\(mention.spelling): hangisi?").font(.caption)
            ScrollView(.horizontal) {
                HStack {
                    ForEach(mention.candidates, id: \.file) { entity in
                        Button {
                            model.choose(entity, for: mention)
                            submit()
                        } label: {
                            entityLabel(entity)
                        }
                    }
                    Button("Bağlamadan devam et") {
                        model.skip(mention)
                        submit()
                    }
                }
            }
        } else if let mention = model.pendingUnknown {
            Text(verbatim: mention.spelling).font(.caption)
            if model.needsQualifier {
                TextField("Ayırt edici (ör. iş)", text: $model.qualifier)
                    .textFieldStyle(.roundedBorder)
                Button("Oluştur") {
                    if let kind = model.creationKind { create(kind) }
                }
                .disabled(model.qualifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else {
                HStack {
                    Button("Kişi olarak ekle") { create(.person) }
                    Button("Konum olarak ekle") { create(.place) }
                }
            }
            Button("Vazgeç") {
                model.dismissUnknown(mention)
                submit()
            }
        }
    }

    private func beginCreation(_ kind: VaultEntityKind) {
        let offset = insertionOffset
        Task { @MainActor in
            await model.beginCreation(kind, at: offset)
            isFocused = true
            if !model.needsQualifier && model.errorText == nil { submit() }
        }
    }

    private func create(_ kind: VaultEntityKind) {
        Task { @MainActor in
            await model.create(kind)
            isFocused = true
            if !model.needsQualifier && model.errorText == nil { submit() }
        }
    }

    private func submit() {
        guard isEnabled && model.canSubmit else { return }
        isFocused = true
        Task { @MainActor in
            await model.submit(time: model.includesTime ? LocalDay.clock() : nil)
            selection = nil
            isFocused = true
        }
    }
}
