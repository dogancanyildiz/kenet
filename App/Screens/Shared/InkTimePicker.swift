import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// A time-of-day picker that draws inside an ink well on macOS (matching TaskDatePicker)
/// and delegates to the platform DatePicker on iOS.
struct InkTimePicker: View {
    let title: LocalizedStringResource
    @Binding var selection: Date
    @Environment(\.locale) private var locale

    var body: some View {
        #if os(macOS)
            HStack {
                // The field carries the name itself (`MacTimePicker`): VoiceOver lands on an
                // adjustable control, not on a merged text.
                Text(title)
                    .font(.ink.byline)
                    .foregroundStyle(Color.ink.text)
                    .accessibilityHidden(true)
                Spacer()
                MacTimePicker(title: localizedTitle, selection: $selection)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Color.ink.well,
                        in: RoundedRectangle(cornerRadius: InkSize.kanbanCorner, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: InkSize.kanbanCorner, style: .continuous)
                            .strokeBorder(Color.ink.control, lineWidth: InkStroke.control)
                    )
            }
        #else
            DatePicker(selection: $selection, displayedComponents: .hourAndMinute) { Text(title) }
        #endif
    }

    #if os(macOS)
        private var localizedTitle: String {
            var resource = title
            resource.locale = locale
            return String(localized: resource)
        }
    #endif
}

#if os(macOS)
    /// The AppKit hour-and-minute field. It sizes itself to its text: "22:30" and "10:30 PM"
    /// need different widths, so no fixed frame.
    struct MacTimePicker: NSViewRepresentable {
        /// The accessibility label of the field.
        let title: String
        @Binding var selection: Date

        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }

        func makeNSView(context: Context) -> NSDatePicker {
            let picker = NSDatePicker()
            picker.datePickerStyle = .textFieldAndStepper
            picker.datePickerElements = .hourMinute
            picker.isBordered = false
            picker.isBezeled = false
            picker.drawsBackground = false
            picker.calendar = Calendar(identifier: .gregorian)
            picker.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            picker.textColor = NSColor(Color.ink.text)
            picker.target = context.coordinator
            picker.action = #selector(Coordinator.timeChanged(_:))
            return picker
        }

        func updateNSView(_ nsView: NSDatePicker, context: Context) {
            context.coordinator.parent = self
            nsView.locale = context.environment.locale
            nsView.dateValue = selection
            nsView.textColor = NSColor(Color.ink.text)
            nsView.setAccessibilityLabel(title)
        }

        func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSDatePicker, context: Context) -> CGSize? {
            let size = nsView.fittingSize
            return CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
        }

        @MainActor
        final class Coordinator: NSObject {
            var parent: MacTimePicker
            init(_ parent: MacTimePicker) {
                self.parent = parent
            }

            @objc func timeChanged(_ sender: NSDatePicker) {
                parent.selection = sender.dateValue
            }
        }
    }
#endif
