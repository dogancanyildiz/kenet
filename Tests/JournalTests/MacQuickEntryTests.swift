#if os(macOS)
    import Carbon
    import Foundation
    import Testing
    import VaultFormat

    @testable import Journal

    @MainActor
    struct MacShortcutTests {
        @Test func defaultIsControlOptionSpaceAndRegistersOnce() throws {
            let defaults = try TestDefaults()
            defer { defaults.clean() }
            var calls: [HotKeyShortcut] = []
            let model = HotKeySettingsModel(defaults: defaults.defaults) {
                calls.append($0)
                return true
            }
            #expect(model.shortcut.keyCode == UInt32(kVK_Space))
            #expect(model.shortcut.modifiers == UInt32(controlKey | optionKey))
            #expect(model.shortcut.isValid)
            model.start()
            model.start()
            #expect(calls == [.defaultShortcut])
            #expect(model.errorText == nil)
        }

        @Test func captureIsPendingUntilSaveAndSavedShortcutRestores() throws {
            let defaults = try TestDefaults()
            defer { defaults.clean() }
            var calls: [HotKeyShortcut] = []
            let model = HotKeySettingsModel(defaults: defaults.defaults) {
                calls.append($0)
                return true
            }
            let replacement = HotKeyShortcut(
                keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(cmdKey | shiftKey), keyLabel: "J")
            model.candidate = replacement
            #expect(model.shortcut == .defaultShortcut)
            #expect(calls.isEmpty)
            #expect(
                HotKeySettingsModel(defaults: defaults.defaults, register: { _ in true }).shortcut == .defaultShortcut)
            #expect(model.save())
            let restored = HotKeySettingsModel(defaults: defaults.defaults) {
                calls.append($0)
                return true
            }
            #expect(restored.shortcut == replacement)
            #expect(restored.candidate == replacement)
            restored.start()
            #expect(calls == [replacement, replacement])
            #expect(restored.shortcut.display == "⇧⌘J")
        }

        @Test func conflictKeepsTheWorkingShortcutAndPersistence() throws {
            let defaults = try TestDefaults()
            defer { defaults.clean() }
            var shouldSucceed = true
            let model = HotKeySettingsModel(defaults: defaults.defaults) { _ in shouldSucceed }
            model.start()
            #expect(model.save())
            shouldSucceed = false
            model.candidate = HotKeyShortcut(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(controlKey), keyLabel: "J")
            #expect(!model.save())
            #expect(model.errorText != nil)
            #expect(model.isRegistered)
            #expect(model.shortcut == .defaultShortcut)
            #expect(
                HotKeySettingsModel(defaults: defaults.defaults, register: { _ in true }).shortcut == .defaultShortcut)
            shouldSucceed = true
            #expect(model.save())
            #expect(model.errorText == nil)
        }

        @Test func invalidShortcutDoesNotRegister() throws {
            let defaults = try TestDefaults()
            defer { defaults.clean() }
            var calls = 0
            let model = HotKeySettingsModel(defaults: defaults.defaults) { _ in
                calls += 1
                return true
            }
            for candidate in [
                HotKeyShortcut(keyCode: 38, modifiers: 0, keyLabel: "J"),
                HotKeyShortcut(keyCode: 38, modifiers: UInt32(shiftKey), keyLabel: "J"),
                HotKeyShortcut(keyCode: 55, modifiers: UInt32(cmdKey), keyLabel: "⌘"),
                HotKeyShortcut(keyCode: 256, modifiers: UInt32(cmdKey), keyLabel: "J"),
            ] {
                model.candidate = candidate
                #expect(!model.save())
                #expect(model.errorText != nil)
            }
            #expect(calls == 0)
        }

        @Test func registrationFailureCanBeRetried() throws {
            let defaults = try TestDefaults()
            defer { defaults.clean() }
            var succeeds = false
            let model = HotKeySettingsModel(defaults: defaults.defaults) { _ in succeeds }
            model.start()
            #expect(!model.isRegistered)
            #expect(model.errorText != nil)
            succeeds = true
            model.start()
            #expect(model.isRegistered)
            #expect(model.errorText == nil)
        }

        @Test func recordingSuspendsAndRestoresTheCurrentShortcut() throws {
            let defaults = try TestDefaults()
            defer { defaults.clean() }
            var calls: [HotKeyShortcut] = []
            var pauses = 0
            let model = HotKeySettingsModel(
                defaults: defaults.defaults,
                register: {
                    calls.append($0)
                    return true
                }, pause: { pauses += 1 })
            model.start()
            model.beginRecording()
            model.beginRecording()
            #expect(model.isRecording)
            #expect(!model.isRegistered)
            #expect(pauses == 1)
            model.candidate = HotKeyShortcut(keyCode: 38, modifiers: UInt32(cmdKey), keyLabel: "J")
            model.endRecording()
            model.endRecording()
            #expect(!model.isRecording)
            #expect(model.isRegistered)
            #expect(calls == [.defaultShortcut, .defaultShortcut])
            #expect(model.shortcut == .defaultShortcut)
        }
    }

    @MainActor
    struct MacQuickEntryWindowTests {
        @Test func openingRequestsFocusAndClosingKeepsDraft() throws {
            let context = try EntityPageTestContext()
            defer { context.clean() }
            let model = QuickEntryWindowModel(store: context.store)
            let firstFocus = model.focusRequest
            #expect(!model.isPresented)
            model.open()
            #expect(model.isPresented)
            #expect(model.focusRequest != firstFocus)
            model.entry.text = "Unsent draft"
            model.close()
            #expect(!model.isPresented)
            #expect(model.entry.text == "Unsent draft")
            let lastFocus = model.focusRequest
            model.open()
            #expect(model.focusRequest != lastFocus)
            #expect(model.entry.text == "Unsent draft")
        }

        @Test func noVaultHasAWarningAndCannotSubmit() async throws {
            let context = try EntityPageTestContext()
            defer { context.clean() }
            let model = QuickEntryWindowModel(store: context.store)
            model.open()
            model.entry.text = "Draft"
            #expect(model.statusText != nil)
            #expect(!model.entry.canSubmit)
            #expect(await !model.entry.submit(time: nil))
            #expect(model.entry.text == "Draft")
        }

        @Test func submissionClearsDraftAndPublishesTodayWithoutClosing() async throws {
            let context = try EntityPageTestContext()
            defer { context.clean() }
            await context.start()
            let model = QuickEntryWindowModel(store: context.store)
            model.open()
            #expect(model.statusText == nil)
            model.entry.text = "Deniz ile Liman Ofis'te"
            #expect(await model.entry.submit(time: try LineClock(hour: 13, minute: 0)))
            #expect(model.entry.text.isEmpty)
            #expect(model.isPresented)
            let day = LocalDay.today()
            let file = context.root.appendingPathComponent("journal/\(day).md")
            let data = try Data(contentsOf: file)
            #expect(
                String(decoding: data, as: UTF8.self).contains("- 13:00 [[Deniz Arıkan|Deniz]] ile [[Liman Ofis]]'te ^")
            )
            #expect(context.store.content.day(on: day).events.count == 1)
            #expect(
                context.store.content.day(on: day).events.first?.text.spans.filter { $0.destination != nil }.count == 2)
            model.entry.text = "Second event"
            #expect(await model.entry.submit(time: nil))
            #expect(context.store.content.day(on: day).events.count == 2)
        }

        @Test func pendingAmbiguitySurvivesClosingAndResolvesBeforeWriting() async throws {
            let context = try EntityPageTestContext()
            defer { context.clean() }
            await context.start()
            let model = QuickEntryWindowModel(store: context.store)
            model.open()
            model.entry.text = "Mert Aksu ile görüşme"
            #expect(await !model.entry.submit(time: nil))
            let mention = try #require(model.entry.pendingAmbiguity)
            model.close()
            model.open()
            #expect(model.entry.pendingAmbiguity != nil)
            let chosen = try #require(mention.candidates.first { $0.qualifier == "iş" })
            model.entry.choose(chosen, for: mention)
            #expect(await model.entry.submit(time: nil))
            let text = context.store.content.day(on: LocalDay.today()).events.first?.text
            #expect(text?.spans.contains { $0.destination == chosen.file } == true)
            #expect(model.entry.text.isEmpty)
        }

        @Test func failedWriteKeepsDraftInTheOpenWindow() async throws {
            let context = try EntityPageTestContext()
            defer { context.clean() }
            await context.start()
            let file = context.root.appendingPathComponent("journal/\(LocalDay.today()).md")
            let original = Data([0xFF, 0xFE])
            try original.write(to: file)
            let model = QuickEntryWindowModel(store: context.store)
            model.open()
            model.entry.text = "Draft"
            #expect(await !model.entry.submit(time: nil))
            #expect(model.entry.text == "Draft")
            #expect(model.isPresented)
            #expect(context.store.entryErrorText != nil)
            #expect(try Data(contentsOf: file) == original)
        }
    }
#endif
