#if os(iOS)
    import SwiftUI
    import UIKit

    /// Keeps the edge swipe back on a subpage whose system bar is hidden (iPhone tab shell,
    /// ``InkPageHeader`` and ``InkNavigationRow`` draw the back item). UIKit stops the swipe
    /// once the bar hides; this hands the stack's pop gesture a delegate that allows it whenever
    /// there is a page to return to.
    struct InkInteractivePopEnabler: UIViewRepresentable {
        func makeUIView(context: Context) -> ProbeView { ProbeView() }

        func updateUIView(_ uiView: ProbeView, context: Context) {
            uiView.enablePop()
        }

        final class ProbeView: UIView {
            override init(frame: CGRect) {
                super.init(frame: frame)
                isUserInteractionEnabled = false
                isAccessibilityElement = false
            }

            required init?(coder: NSCoder) { nil }

            override func didMoveToWindow() {
                super.didMoveToWindow()
                enablePop()
            }

            func enablePop() {
                guard let navigation = owningNavigationController,
                    let pop = navigation.interactivePopGestureRecognizer,
                    !(pop.delegate is InkPopGestureDelegate)
                else { return }
                let delegate = InkPopGestureDelegate(navigation: navigation)
                // The recognizer holds its delegate weakly; the registry keeps it alive.
                InkPopGestureDelegate.registry[ObjectIdentifier(navigation)] = delegate
                pop.delegate = delegate
            }

            private var owningNavigationController: UINavigationController? {
                var responder: UIResponder? = self
                while let current = responder {
                    if let controller = current as? UIViewController {
                        return controller.navigationController ?? (controller as? UINavigationController)
                    }
                    responder = current.next
                }
                return nil
            }
        }
    }

    /// Allows the pop gesture when the stack has a page under the top one and no transition runs.
    @MainActor final class InkPopGestureDelegate: NSObject, UIGestureRecognizerDelegate {
        static var registry: [ObjectIdentifier: InkPopGestureDelegate] = [:]
        private weak var navigation: UINavigationController?

        init(navigation: UINavigationController) {
            self.navigation = navigation
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let navigation else { return false }
            return navigation.viewControllers.count > 1 && navigation.transitionCoordinator == nil
        }
    }
#endif
