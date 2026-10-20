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
            // A second strip whose notice always dismisses after the short lifetime: the clock for
            // the strip that must keep its notice.
            let control = MentionComposer(store: context.store)
            control.creationNotice = MentionComposer.CreationNotice(name: "Ece Yalın", kind: .person)
            var appeared = false
            let mount = HostedLayout.Mount(
                VStack {
                    MentionAssistStrip(composer: composer, store: context.store)
                        .environment(\.mentionNoticeLifetime, automaticallyDismisses ? .milliseconds(50) : nil)
                    MentionAssistStrip(composer: control, store: context.store)
                        .environment(\.mentionNoticeLifetime, .milliseconds(50))
                }
                .onAppear { appeared = true },
                size: CGSize(width: 400, height: 300))
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
                // Five of the control's lifetimes, each one awaited, with the same hosted view still
                // mounted: on a slow machine the control slows down with the strip under test.
                for round in 0..<5 {
                    if round > 0 {
                        control.creationNotice = MentionComposer.CreationNotice(
                            name: "Ece Yalın \(round)", kind: .person)
                    }
                    let deadline = clock.now.advanced(by: .seconds(2))
                    while control.creationNotice != nil && clock.now < deadline {
                        await mount.settle(rounds: 1)
                    }
                    try #require(control.creationNotice == nil, "The control notice must dismiss itself")
                }
                #expect(composer.creationNotice == notice)
            }
        }
    }
#endif
