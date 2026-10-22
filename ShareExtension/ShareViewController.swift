import SwiftUI
import UIKit

/// The share extension's entry point (`NSExtensionPrincipalClass`). Apple starts a share
/// extension with a view controller; this one only hosts the SwiftUI form (`ShareFormView`) and
/// ends the request. It is the extension's only UIKit type: AGENTS.md keeps new UIKit views out,
/// and this entry point has no SwiftUI replacement.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let writer = ShareEntryWriter(
            group: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppIdentifiers.appGroup),
            cloudContainer: { await Self.cloudContainer() }, coordination: SystemFileCoordination())
        let model = ShareFormModel(
            writer: writer,
            finish: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) },
            cancel: { [weak self] in self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled)) })
        let host = UIHostingController(rootView: ShareRootView(model: model))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        let items = extensionContext?.inputItems ?? []
        Task { await model.load(items) }
    }

    /// The real iCloud container, looked up off the main thread; nil without an iCloud account.
    private static func cloudContainer() async -> URL? {
        await Task.detached {
            guard FileManager.default.ubiquityIdentityToken != nil else { return nil }
            return FileManager.default.url(forUbiquityContainerIdentifier: AppIdentifiers.iCloudContainer)
        }.value
    }
}

private struct ShareRootView: View {
    @Bindable var model: ShareFormModel

    var body: some View {
        ShareFormView(
            text: $model.text, isSaving: model.isSaving, failed: model.failed, onCancel: model.cancel,
            onConfirm: model.confirm)
    }
}
