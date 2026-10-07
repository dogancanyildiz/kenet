import Testing

@testable import Journal

struct DestructiveConfirmationTests {
    @Test func idleRequestConfirmDeletesOnceAndCancelDoesNot() {
        var confirmation = DestructiveConfirmation<String>()
        #expect(!confirmation.isPending)
        #expect(confirmation.confirm() == nil)

        confirmation.request("event-a")
        #expect(confirmation.isPending)
        #expect(confirmation.pending == "event-a")

        confirmation.cancel()
        #expect(!confirmation.isPending)
        #expect(confirmation.confirm() == nil)

        confirmation.request("event-b")
        #expect(confirmation.confirm() == "event-b")
        #expect(!confirmation.isPending)
        #expect(confirmation.confirm() == nil)
    }

    @Test func tokenConfirmationSupportsSingleControlScreens() {
        var confirmation = DestructiveConfirmation<DestructiveConfirmationToken>()
        confirmation.request(.pending)
        #expect(confirmation.isPending)
        #expect(confirmation.confirm() == .pending)
        #expect(!confirmation.isPending)
    }

    @Test func replacingPendingKeepsLatestTarget() {
        var confirmation = DestructiveConfirmation<Int>()
        confirmation.request(1)
        confirmation.request(2)
        #expect(confirmation.pending == 2)
        #expect(confirmation.confirm() == 2)
    }
}
