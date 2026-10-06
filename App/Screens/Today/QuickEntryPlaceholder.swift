import EntityRecognition
import SwiftUI
import VaultFormat
import VaultStore

struct QuickEntryBar: View {
    @Environment(\.locale) private var locale
    @Environment(\.clockNow) private var clockNow
    @Environment(LocationService.self) private var location
    @Environment(IntentNavigation.self) private var navigation: IntentNavigation?
    private let acceptsPeopleMentions: Bool
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
        model: QuickEntryModel? = nil, focusRequest: UUID? = nil, acceptsPeopleMentions: Bool = false
    ) {
        self.store = store
        self.isEnabled = isEnabled
        self.focusRequest = focusRequest
        self.acceptsPeopleMentions = acceptsPeopleMentions
        let initial = model ?? QuickEntryModel(store: store, day: day)
        if model == nil, let prefill = AppLaunchPolicy.uiTestQuickEntryText() { initial.text = prefill }
        _model = State(initialValue: initial)
    }

    private var insertionOffset: Int? {
        if let selection, case .selection(let range) = selection.indices {
            // XCUITest and other programmatic edits can leave a stale selection whose bounds
            // no longer lie inside `model.text`; subscripting then traps in String validation.
            guard range.lowerBound >= model.text.startIndex, range.lowerBound <= model.text.endIndex
            else { return nil }
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
                            Text(verbatim: LocationCopy.areYouAt(place.entity.name, locale: locale))
                            if let qualifier = place.entity.qualifier {
                                Text(verbatim: qualifier).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tapTarget()
                    }
                    Button {
                        model.dismissLocation()
                    } label: {
                        Label("Konum önerisini kapat", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                            .tapTarget()
                    }
                }
                .disabled(model.isCreating || model.isSubmitting)
            }
            QuickEntryTaskControls(model: model, showsPicker: $showsDatePicker)
                .disabled(!isEnabled || model.isSubmitting || model.isCreating || store.isWriting)
            resolutionStrip
                .disabled(model.isCreating || model.isSubmitting || !isEnabled)
            if !model.awaitingResolution {
                ForEach(model.projectSuggestions(at: insertionOffset), id: \.self) { project in
                    Button {
                        model.selectProjectSuggestion(project, at: insertionOffset)
                        selection = nil
                        isFocused = true
                    } label: {
                        Text(verbatim: "#project/" + project)
                            .tapTarget()
                    }
                    .buttonStyle(.plain)
                    .disabled(!isEnabled || !model.canSubmit)
                }
                ForEach(model.suggestions(at: insertionOffset), id: \.file) { entity in
                    Button {
                        model.selectSuggestion(entity, at: insertionOffset)
                        selection = nil
                        isFocused = true
                    } label: {
                        entityLabel(entity)
                            .tapTarget()
                    }
                    .buttonStyle(.plain)
                    .disabled(!isEnabled || !model.canSubmit)
                }
            }
            if !model.awaitingResolution, let range = model.suggestionRange(at: insertionOffset), range.count > 1 {
                HStack {
                    Button {
                        beginCreation(.person)
                    } label: {
                        Text("Yeni kişi oluştur")
                            .tapTarget()
                    }
                    Button {
                        beginCreation(.place)
                    } label: {
                        Text("Yeni konum oluştur")
                            .tapTarget()
                    }
                    Menu("Özel tip olarak ekle") {
                        ForEach(
                            EntityTypeChoices.choices(
                                store.entityTypes, language: locale.language.languageCode?.identifier ?? "en"
                            ).filter {
                                $0.id != "person" && $0.id != "place"
                            }
                        ) { type in
                            Button {
                                beginCreation(type.kind)
                            } label: {
                                Text("\(type.name) olarak ekle")
                            }
                        }
                    }.disabled(store.entityTypes.types.isEmpty)
                }
                .disabled(!isEnabled || !model.canSubmit)
            }
            if let error = model.errorText {
                Text(verbatim: error).font(.caption).foregroundStyle(.red)
            }
            entryField
        }
        .padding()
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bar.quickEntry")
        .onAppear { model.locationService = location }
        .onChange(of: navigation?.mentionRequest?.id, initial: true) { _, id in
            if id != nil { applyMention() }
        }
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
        .onChange(of: model.isSubmitting || model.isCreating || store.isWriting) { applyMention() }
        .onChange(of: isEnabled) { _, enabled in
            if enabled { applyMention() }
            if enabled && focusRequest != nil { isFocused = true }
        }
    }

    private func applyMention() {
        guard acceptsPeopleMentions, isEnabled, !model.isSubmitting, !model.isCreating, !store.isWriting,
            let entity = navigation?.takeMention(vault: store.vaultURL)
        else { return }
        model.prefillMention(entity)
        selection = nil
        isFocused = true
    }

    private var placeholder: LocalizedStringKey {
        model.mode == .task ? "Yapılacak bir şey…" : "Gününden bir an…"
    }

    /// Single-line when it fits; stacks controls above the field at large Dynamic Type sizes.
    private var entryField: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                modeButton
                timeButton
                textField
                sendButton
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    modeButton
                    timeButton
                    Spacer(minLength: 0)
                    sendButton
                }
                textField
            }
        }
    }

    private var textField: some View {
        @Bindable var model = model
        return TextField(placeholder, text: $model.text, selection: $selection)
            .textFieldStyle(.roundedBorder)
            .focused($isFocused)
            .disabled(!isEnabled)
            .onSubmit { submit() }
            // Identifier on the accessibility element VoiceOver/XCTest see for the field.
            .accessibilityLabel("Hızlı giriş")
            .accessibilityIdentifier("field.quickEntry")
    }

    private var sendButton: some View {
        Button {
            submit()
        } label: {
            Label("Gönder", systemImage: "arrow.up.circle.fill")
                .labelStyle(.iconOnly)
                .tapTarget()
        }
        .accessibilityIdentifier("button.quickEntrySend")
        .disabled(!isEnabled || !model.canSubmit)
    }

    @ViewBuilder private var timeButton: some View {
        if model.mode == .event {
            // TimelineView still ticks so production refreshes each minute; the displayed
            // instant comes from `clockNow` so snapshot tests can freeze the wall clock.
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                timeControl(now: clockNow())
            }
        }
    }

    private func timeControl(now: Date) -> some View {
        @Bindable var model = model
        return Button {
            if model.isHistorical {
                showsTimePicker = true
            } else {
                model.includesTime.toggle()
            }
        } label: {
            Group {
                if model.includesTime {
                    Text(
                        model.isHistorical ? model.selectedTime : now,
                        format: .dateTime.hour().minute()
                    )
                    .monospacedDigit()
                } else {
                    Image(systemName: "clock.badge.xmark")
                }
            }
            .tapTarget()
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
            .tapTarget()
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
                    Menu("Özel tip olarak ekle") {
                        ForEach(
                            EntityTypeChoices.choices(
                                store.entityTypes, language: locale.language.languageCode?.identifier ?? "en"
                            ).filter {
                                $0.id != "person" && $0.id != "place"
                            }
                        ) { type in
                            Button {
                                create(type.kind)
                            } label: {
                                Text("\(type.name) olarak ekle")
                            }
                        }
                    }.disabled(store.entityTypes.types.isEmpty)
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
