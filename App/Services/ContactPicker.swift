#if os(iOS)
    import ContactsUI
    import SwiftUI

    /// The system's out-of-process contact picker, multi-selection. The app never touches
    /// `CNContactStore`, so no contacts permission is requested (no `NSContactsUsageDescription`).
    /// Only ``ContactName`` values leave this file; a `CNContact` never reaches a model.
    struct ContactPicker: UIViewControllerRepresentable {
        let onSelect: ([ContactName]) -> Void
        let onCancel: () -> Void

        func makeUIViewController(context: Context) -> CNContactPickerViewController {
            let picker = CNContactPickerViewController()
            picker.delegate = context.coordinator
            return picker
        }

        func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

        func makeCoordinator() -> Coordinator {
            Coordinator(onSelect: onSelect, onCancel: onCancel)
        }

        final class Coordinator: NSObject, CNContactPickerDelegate {
            private let onSelect: ([ContactName]) -> Void
            private let onCancel: () -> Void

            init(onSelect: @escaping ([ContactName]) -> Void, onCancel: @escaping () -> Void) {
                self.onSelect = onSelect
                self.onCancel = onCancel
            }

            // Implementing the plural variant is what switches the picker to multi-selection.
            func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
                onSelect(contacts.map(ContactNameReader.name(from:)))
            }

            func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
                onCancel()
            }
        }
    }

    /// Reads the two things the import is allowed to take from a contact: the name of a person
    /// and the nickname. Phone numbers, addresses, dates, the organization, the note, the image
    /// and the contact identifier are never read.
    enum ContactNameReader {
        /// An empty name is returned (not dropped) so the summary can list the contact as invalid.
        static func name(from contact: CNContact) -> ContactName {
            let nickname =
                contact.isKeyAvailable(CNContactNicknameKey) ? trimmed(contact.nickname) : ""
            var name = ""
            if hasPersonName(contact),
                contact.areKeysAvailable([CNContactFormatter.descriptorForRequiredKeys(for: .fullName)])
            {
                name = trimmed(CNContactFormatter.string(from: contact, style: .fullName) ?? "")
            }
            // A contact saved under its nickname alone is still a person the user can name.
            if name.isEmpty { return ContactName(name: nickname) }
            return ContactName(name: name, nickname: nickname.isEmpty ? nil : nickname)
        }

        /// The system formatter falls back to the organization for a company card; a company is
        /// not a person and its name is not among the imported fields.
        private static func hasPersonName(_ contact: CNContact) -> Bool {
            let keys = [CNContactTypeKey, CNContactGivenNameKey, CNContactMiddleNameKey, CNContactFamilyNameKey]
            guard contact.areKeysAvailable(keys as [any CNKeyDescriptor]), contact.contactType == .person
            else { return false }
            return [contact.givenName, contact.middleName, contact.familyName].contains { !trimmed($0).isEmpty }
        }

        private static func trimmed(_ text: String) -> String {
            text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
#endif
