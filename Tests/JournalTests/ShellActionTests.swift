import Testing

@testable import Journal

/// The shell's commands are values made once (``ShellAction``): equal to themselves only, so a
/// view that hands the same one on every body changes nothing for the views reading it.
@MainActor
struct ShellActionTests {
    @Test func anActionEqualsItsCopiesAndNotAnotherWithTheSameBody() {
        let counter = Counter()
        let action = ShellAction { counter.count += 1 }
        let copy = action
        let twin = ShellAction { counter.count += 1 }

        #expect(copy == action)
        #expect(twin != action, "same body, made again: a new value")
        copy()
        action()
        #expect(counter.count == 2, "a copy runs the same body")
    }

    /// The window's search action: read as often as the window updates, made once.
    @Test func searchPresentationRaisesTheSheetWithOneAction() {
        let search = SearchPresentation()
        let open = search.open

        #expect(!search.isPresented)
        open()
        #expect(search.isPresented)
        #expect(search.open == open, "every read hands the same action")
    }

    /// ⌘F and a page's magnifier inside the open sheet: back to the results, the field focused,
    /// also when the results already show.
    @Test func searchInsideTheSheetReturnsToTheFieldEachTime() throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let model = SearchModel(store: context.store, defaults: context.defaults.defaults)
        model.path = [.note("notes/Okuma Listesi.md")]
        let asked = model.fieldFocusRequests

        model.returnToField()
        #expect(model.path.isEmpty, "the page closes onto the results")
        #expect(model.fieldFocusRequests == asked + 1)
        model.returnToField()
        #expect(model.fieldFocusRequests == asked + 2, "the results already show: the field is asked again")
    }

    @MainActor private final class Counter { var count = 0 }
}
