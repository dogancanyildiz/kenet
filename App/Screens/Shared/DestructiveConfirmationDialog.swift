import SwiftUI

extension View {
    /// Presents a destructive confirmation dialog driven by ``DestructiveConfirmation``.
    func destructiveConfirmationDialog<Target: Equatable>(
        _ title: LocalizedStringKey,
        confirmation: Binding<DestructiveConfirmation<Target>>,
        confirmTitle: LocalizedStringKey = "Sil",
        message: LocalizedStringKey = "Bu işlem geri alınamaz.",
        onConfirm: @escaping (Target) -> Void
    ) -> some View {
        confirmationDialog(
            title,
            isPresented: Binding(
                get: { confirmation.wrappedValue.isPending },
                set: { presented in
                    guard !presented else { return }
                    var value = confirmation.wrappedValue
                    value.cancel()
                    confirmation.wrappedValue = value
                }
            )
        ) {
            Button(confirmTitle, role: .destructive) {
                var value = confirmation.wrappedValue
                if let target = value.confirm() {
                    confirmation.wrappedValue = value
                    onConfirm(target)
                }
            }
        } message: {
            Text(message)
        }
    }
}
