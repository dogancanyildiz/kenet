import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// A time-of-day picker that draws inside an ink well on macOS (matching TaskDatePicker)
/// and delegates to the platform DatePicker on iOS.
struct InkTimePicker: View {
    let title: LocalizedStringKey
    @Binding var selection: Date

    var body: some View {
        #if os(macOS)
            HStack {
                Text(title)
                    .font(.ink.byline)
                    .foregroundStyle(Color.ink.text)
                Spacer()
                MacTimePicker(selection: $selection)
                    .frame(width: 80, height: 24)
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
            .accessibilityElement(children: .combine)
        #else
            DatePicker(title, selection: $selection, displayedComponents: .hourAndMinute)
        #endif
    }
}

#if os(macOS)
    struct MacTimePicker: NSViewRepresentable {
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
            nsView.dateValue = selection
            nsView.textColor = NSColor(Color.ink.text)
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
