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

    private var capsuleMode: Binding<QuickEntryMode> {
        Binding(
            get: { model.mode == .task ? .task : .event },
            set: {
                model.mode = $0 == .task ? .task : .event
                isFocused = true
            }
        )
    }

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 8) {
            if isEnabled, let error = store.entryErrorText {
                InfoBand(kind: .error, verbatim: error)
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
                                .foregroundStyle(Color.ink.text)
                            if let qualifier = place.entity.qualifier {
                                Text(verbatim: qualifier)
                                    .font(.ink.meta)
                                    .foregroundStyle(Color.ink.secondaryText)
                            }
                        }
                        .tapTarget()
                    }
                    .buttonStyle(.plain)
                    Button {
                        model.dismissLocation()
                    } label: {
                        Label("Konum önerisini kapat", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(Color.ink.secondaryText)
                            .tapTarget()
                    }
                    .buttonStyle(.plain)
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
                            .font(.ink.meta)
                            .foregroundStyle(Color.ink.text)
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
                    .buttonStyle(InkTextButtonStyle())
                    Button {
                        beginCreation(.place)
                    } label: {
                        Text("Yeni konum oluştur")
                            .tapTarget()
                    }
                    .buttonStyle(InkTextButtonStyle())
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
                InfoBand(kind: .error, verbatim: error)
            }
            QuickEntryCapsule(
                mode: capsuleMode,
                canSubmit: isEnabled && model.canSubmit,
                onSubmit: submit,
                isModeEnabled: QuickEntryModeLock.isModeEnabled(
                    isEnabled: isEnabled, isSubmitting: model.isSubmitting,
                    isCreating: model.isCreating, isWriting: store.isWriting)
            ) {
                HStack(alignment: .center, spacing: 4) {
                    if model.mode == .event {
                        timeButton
                            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    }
                    textField
                }
            }
            #if os(macOS)
                Button("Kip değiştir") {
                    model.mode = model.mode == .task ? .event : .task
                    isFocused = true
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
                .disabled(!isEnabled || model.isSubmitting || model.isCreating || store.isWriting)
            #endif
        }
        .padding(.horizontal, InkSpacing.margin)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
        .inkPageColumn()
        // Opaque paper shelf under the capsule (safeAreaInset content draws over the list).
        .background {
            Color.ink.paper
                .ignoresSafeArea(edges: .bottom)
        }
        .compositingGroup()
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

    private var placeholder: String {
        let key: String.LocalizationValue =
            model.mode == .task ? "Yapılacak bir şey…" : "Gününden bir an…"
        return String(
            localized: key, bundle: PresentationLocalization.bundle(locale), locale: locale)
    }

    private var textField: some View {
        @Bindable var model = model
        return TextField(
            "",
            text: $model.text,
            selection: $selection,
            prompt: Text(verbatim: placeholder)
                .font(.ink.placeholder)
                .foregroundStyle(Color.ink.secondaryText)
        )
        .textFieldStyle(.plain)
        .font(.ink.content)
        .foregroundStyle(Color.ink.text)
        .focused($isFocused)
        .disabled(!isEnabled)
        .onSubmit { submit() }
        // Identifier on the accessibility element VoiceOver/XCTest see for the field.
        .accessibilityLabel("Hızlı giriş")
        .accessibilityIdentifier("field.quickEntry")
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
                    .font(.ink.time)
                    .foregroundStyle(Color.ink.secondaryText)
                    .monospacedDigit()
                } else {
                    Image(systemName: "clock.badge.xmark")
                        .foregroundStyle(Color.ink.secondaryText)
                }
            }
            .tapTarget()
        }
        .buttonStyle(.plain)
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

    private func entityLabel(_ entity: KnownEntity) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: entity.name)
                .font(.ink.meta)
                .foregroundStyle(entityColor(entity))
            if let qualifier = entity.qualifier {
                Text(verbatim: qualifier)
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
            }
        }
    }

    /// TextField cannot draw underlines; suggestion chips use InkLinkStyle color tokens.
    private func entityColor(_ entity: KnownEntity) -> Color {
        switch entity.kind {
        case .person: Color.ink.person
        case .place: Color.ink.place
        default: Color.ink.text
        }
    }

    @ViewBuilder private var resolutionStrip: some View {
        @Bindable var model = model
        if let mention = model.pendingAmbiguity {
            Text("\(mention.spelling): hangisi?")
                .font(.ink.meta)
                .foregroundStyle(Color.ink.text)
            ScrollView(.horizontal) {
                HStack {
                    ForEach(mention.candidates, id: \.file) { entity in
                        Button {
                            model.choose(entity, for: mention)
                            submit()
                        } label: {
                            entityLabel(entity)
                                .tapTarget()
                        }
                        .buttonStyle(.plain)
                    }
                    Button("Bağlamadan devam et") {
                        model.skip(mention)
                        submit()
                    }
                    .buttonStyle(InkTextButtonStyle())
                }
            }
        } else if let mention = model.pendingUnknown {
            Text(verbatim: mention.spelling)
                .font(.ink.meta)
                .foregroundStyle(Color.ink.text)
            if model.needsQualifier {
                TextField("Ayırt edici (ör. iş)", text: $model.qualifier)
                    .textFieldStyle(.plain)
                    .font(.ink.content)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.ink.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: InkSize.chipCorner, style: .continuous)
                            .strokeBorder(Color.ink.control, lineWidth: InkStroke.control)
                    }
                Button("Oluştur") {
                    if let kind = model.creationKind { create(kind) }
                }
                .buttonStyle(InkTextButtonStyle())
                .disabled(model.qualifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else {
                HStack {
                    Button("Kişi olarak ekle") { create(.person) }
                        .buttonStyle(InkTextButtonStyle())
                    Button("Konum olarak ekle") { create(.place) }
                        .buttonStyle(InkTextButtonStyle())
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
            .buttonStyle(InkTextButtonStyle())
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
