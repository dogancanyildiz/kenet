import EntityRecognition
import SwiftUI
import VaultFormat
import VaultStore

struct QuickEntryBar: View {
    @Environment(LocationService.self) private var location
    let store: IndexStore
    let isEnabled: Bool
    private let focusRequest: UUID?
    @State private var model: QuickEntryModel
    @State private var showsTimePicker = false
    @State private var showsDatePicker = false
    @State private var selection: TextSelection?
    @FocusState private var isFocused: Bool

    init(
        store: IndexStore, isEnabled: Bool, day: CalendarDate? = nil,
        model: QuickEntryModel? = nil, focusRequest: UUID? = nil
    ) {
        self.store = store
        self.isEnabled = isEnabled
        self.focusRequest = focusRequest
        _model = State(initialValue: model ?? QuickEntryModel(store: store, day: day))
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
            if isEnabled, let place = model.suggestedPlace {
                HStack {
                    Button {
                        model.selectLocation()
                        selection = nil
                        isFocused = true
                    } label: {
                        VStack(alignment: .leading) {
                            Text("📍 \(place.entity.name)'te misin?")
                            if let qualifier = place.entity.qualifier {
                                Text(verbatim: qualifier).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button("Konum önerisini kapat", systemImage: "xmark") { model.dismissLocation() }
                        .labelStyle(.iconOnly)
                }
                .disabled(model.isCreating || model.isSubmitting)
            }
            QuickEntryTaskControls(model: model, showsPicker: $showsDatePicker)
                .disabled(!isEnabled || model.isSubmitting || model.isCreating || store.isWriting)
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
                modeButton
                if model.mode == .event {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        Button {
                            if model.isHistorical {
                                showsTimePicker = true
                            } else {
                                model.includesTime.toggle()
                            }
                        } label: {
                            if model.includesTime {
                                Text(
                                    model.isHistorical ? model.selectedTime : context.date,
                                    format: .dateTime.hour().minute()
                                )
                                .monospacedDigit()
                            } else {
                                Image(systemName: "clock.badge.xmark")
                            }
                        }
                        .accessibilityLabel(model.includesTime ? Text("Saati kaldır") : Text("Şu anki saati ekle"))
                        .disabled(!isEnabled || store.isWriting)
                        .popover(isPresented: $showsTimePicker) {
                            VStack {
                                DatePicker("Saat", selection: $model.selectedTime, displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                                    .onChange(of: model.selectedTime) { model.includesTime = true }
                                Button("Saati ekle") {
                                    model.includesTime = true
                                    showsTimePicker = false
                                }
                                Button("Saati kaldır") {
                                    model.includesTime = false
                                    showsTimePicker = false
                                }
                            }
                            .padding()
                            .presentationCompactAdaptation(.popover)
                        }
                    }
                }
                TextField(placeholder, text: $model.text, selection: $selection)
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
        .onAppear { model.locationService = location }
        .onChange(of: isFocused) { _, focused in
            model.locationService = location
            if focused { model.focusLocation() }
        }
        .onChange(of: location.authorization) { if isFocused { model.focusLocation() } }
        .onChange(of: location.isEnabled) { if isFocused { model.focusLocation() } }
        .onChange(of: focusRequest, initial: true) { _, request in
            if request != nil {
                model.locationService = location
                model.focusLocation()
                isFocused = true
            }
        }
        .onChange(of: showsDatePicker) { _, presented in
            if !presented { isFocused = true }
        }
        .onChange(of: isEnabled) { _, enabled in
            if enabled && focusRequest != nil { isFocused = true }
        }
    }

    private var placeholder: LocalizedStringKey {
        model.mode == .task ? "Yapılacak bir şey…" : "Gününden bir an…"
    }

    private var modeButton: some View {
        Button {
            model.mode = model.mode == .event ? .task : .event
            isFocused = true
        } label: {
            Label {
                if model.mode == .task { Text("Görev") } else { Text("Olay") }
            } icon: {
                Image(systemName: model.mode == .task ? "checkmark.square" : "text.bubble")
            }
        }
        .disabled(!isEnabled || model.isSubmitting || model.isCreating || store.isWriting)
        #if os(macOS)
            .keyboardShortcut("t", modifiers: [.command, .shift])
        #endif
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
            await model.submit(time: model.entryTime)
            selection = nil
            isFocused = true
        }
    }
}
