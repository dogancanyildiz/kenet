#if os(macOS)
    import SwiftUI
    import Testing

    @testable import Journal

    @MainActor @Suite(.timeLimit(.minutes(1)))
    struct MentionNoticeLifetimeTests {
        private let watchdog = HostedTestWatchdog()

        @Test(arguments: [true, false])
        func noticeLifetimeControlsAutomaticDismissal(automaticallyDismisses: Bool) async throws {
            let context = try DayEditingTestContext()
            defer { context.clean() }
            await context.start()
            let composer = MentionComposer(store: context.store)
            let notice = MentionComposer.CreationNotice(name: "Deniz Arıkan", kind: .person)
            composer.creationNotice = notice
            var appeared = false
            let mount = HostedLayout.Mount(
                MentionAssistStrip(composer: composer, store: context.store)
                    .environment(\.mentionNoticeLifetime, automaticallyDismisses ? .milliseconds(50) : nil)
                    .onAppear { appeared = true },
                size: CGSize(width: 400, height: 200))
            defer { mount.close() }

            let clock = ContinuousClock()
            let appearanceDeadline = clock.now.advanced(by: .seconds(2))
            while !appeared && clock.now < appearanceDeadline {
                await mount.settle(rounds: 1)
            }
            try #require(appeared, "The strip must be mounted before measuring its timer")

            if automaticallyDismisses {
                let deadline = clock.now.advanced(by: .seconds(1))
                while composer.creationNotice != nil && clock.now < deadline {
                    await mount.settle(rounds: 1)
                }
                #expect(composer.creationNotice == nil)
            } else {
                // Five times the short lifetime, with the same hosted view still mounted.
                try await Task.sleep(for: .milliseconds(250))
                #expect(composer.creationNotice == notice)
            }
        }
    }
#endif
