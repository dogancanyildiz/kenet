import SwiftUI
import VaultFormat

struct QuickEntryBar: View {
    @Environment(\.locale) private var locale
    @Environment(\.clockNow) private var clockNow
    @Environment(LocationService.self) private var location
    @Environment(IntentNavigation.self) private var navigation: IntentNavigation?
    @Environment(\.journalingSuggestionsAvailable) private var suggestionsAvailable
    private let acceptsPeopleMentions: Bool
    let store: IndexStore
    let isEnabled: Bool
    private let focusRequest: UUID?
    /// Only a day page's own bar takes a calendar draft; a bar handed its model sits elsewhere.
    private let acceptsCalendarDrafts: Bool
    /// The bridge that keeps a day page's model while the shell is rebuilt; nil for a bar that
    /// was handed its model or is hosted without a shell.
    private let drafts: ShellNavigationState?
    @State private var model: QuickEntryModel
    @State private var showsTimePicker = false
    @State private var showsDatePicker = false
    @State private var showsSuggestions = false
    @State private var selection: TextSelection?
    @FocusState private var isFocused: Bool

    /// - Parameter drafts: a day page passes the shell's bridge, which keeps the model (and so
    ///   the text being typed) for the day: the iPhone Duo rebuilds the page when it opens or closes.
    init(
        store: IndexStore, isEnabled: Bool, day: CalendarDate? = nil,
        model: QuickEntryModel? = nil, focusRequest: UUID? = nil, acceptsPeopleMentions: Bool = false,
        drafts: ShellNavigationState? = nil
    ) {
        self.store = store
        self.isEnabled = isEnabled
        self.focusRequest = focusRequest
        self.acceptsPeopleMentions = acceptsPeopleMentions
        acceptsCalendarDrafts = model == nil
        self.drafts = model == nil ? drafts : nil
        let make = {
            let fresh = QuickEntryModel(store: store, day: day)
            if let prefill = AppLaunchPolicy.uiTestQuickEntryText() { fresh.text = prefill }
            return fresh
        }
        let initial = model ?? self.drafts?.quickEntryDraft(for: day, store: store, make: make) ?? make()
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

    /// ⌘⇧T switches the mode (Mac, and iPad with a hardware keyboard). Off-screen and inert for
    /// touch, so iPhone looks and behaves as before.
    private var modeShortcutButton: some View {
        Button("Kip değiştir") {
            model.mode = model.mode == .task ? .event : .task
            isFocused = true
        }
        .keyboardShortcut(JournalShortcut.switchMode.key, modifiers: JournalShortcut.switchMode.modifiers)
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
        .disabled(!isEnabled || model.isSubmitting || model.isCreating || store.isWriting)
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
            if isEnabled,
                let note = SuggestionCopy.note(
                    day: model.suggestionDay, today: model.today(),
                    remaining: model.suggestionQueue?.remaining.count ?? 0,
                    skippedMedia: model.suggestionQueue?.skippedMedia ?? 0, locale: locale)
            {
                // "Sıradaki" only into an empty field: a typed draft is never replaced. ✕ drops the
                // waiting lines; the day stays in sight while its line is in the field.
                let queue = model.suggestionQueue
                let canTake = queue?.remaining.isEmpty == false && model.text.allSatisfy(\.isWhitespace)
                InfoBand(
                    kind: .info, verbatim: note, actionTitle: canTake ? "Sıradaki" : nil,
                    action: canTake ? { takeNextSuggestion() } : nil,
                    onDismiss: queue == nil ? nil : { model.dropSuggestions() })
            }
            QuickEntryTaskControls(model: model, showsPicker: $showsDatePicker) {
                selection = nil
                isFocused = true
            }
            .disabled(!isEnabled || model.isSubmitting || model.isCreating || store.isWriting)
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
            }
            MentionAssistStrip(
                composer: model.composer, store: store, insertionOffset: insertionOffset,
                isEnabled: isEnabled && model.canSubmit && !model.isCreating && !model.isSubmitting,
                onDidChangeText: { caret in
                    if let caret,
                        let next = MentionComposer.textSelection(atByteOffset: caret, in: model.text)
                    {
                        selection = next
                    }
                    isFocused = true
                },
                onResolved: submit
            )
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
                    if suggestionsAvailable ?? JournalingSuggestionsAvailability.current(), model.mode == .event,
                        model.text.isEmpty
                    {
                        SuggestionsButton(isEnabled: isEnabled && !store.isWriting) { showsSuggestions = true }
                            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    }
                }
            }
            #if os(macOS)
                modeShortcutButton
            #endif
        }
        .padding(.horizontal, InkSpacing.margin)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
        .inkPageColumn()
        #if os(iOS)
            // iPad hardware keyboard: in the background, so it adds no row to the stack's spacing.
            .background { modeShortcutButton }
        #endif
        // Opaque paper shelf under the capsule (safeAreaInset content draws over the list).
        .background {
            Color.ink.paper
                .ignoresSafeArea(edges: [.horizontal, .bottom])
        }
        .compositingGroup()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bar.quickEntry")
        .onAppear { model.locationService = location }
        .suggestionsPicker(isPresented: $showsSuggestions) { pick in applySuggestion(pick) }
        .task(id: store.lastUpdated) { await model.loadProjects() }
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
        .onChange(of: CalendarDraftInbox.shared.request?.id) { applyCalendarDraft() }
        .onChange(of: model.isSubmitting || model.isCreating || store.isWriting) {
            applyMention()
            applyCalendarDraft()
        }
        .onChange(of: isEnabled) { _, enabled in
            if enabled { applyMention() }
            if enabled && focusRequest != nil { isFocused = true }
        }
        // A past day's page went with nothing typed: the bridge lets its model go. Today's
        // stays for the shell's lifetime (its dismissed location suggestion stays dismissed).
        .onDisappear {
            if model.day != nil, model.text.isEmpty, !model.isSubmitting, !model.isCreating {
                drafts?.releaseQuickEntryDraft(model)
            }
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

    private func applyCalendarDraft() {
        guard acceptsCalendarDrafts, isEnabled, !model.isSubmitting, !model.isCreating, !store.isWriting,
            let event = CalendarDraftInbox.shared.take(on: model.day ?? model.today())
        else { return }
        model.applyCalendarDraft(event)
        selection = nil
        isFocused = true
    }

    private func applySuggestion(_ pick: SuggestionPick) {
        guard isEnabled else { return }
        model.applySuggestion(pick, locale: locale)
        selection = nil
        isFocused = true
    }

    private func takeNextSuggestion() {
        model.takeNextSuggestion()
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
                        model.isHistorical ? model.selectedTime : model.calendarDraft?.time ?? now,
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
