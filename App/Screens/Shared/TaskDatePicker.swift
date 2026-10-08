import SwiftUI
import VaultFormat

struct TaskDatePicker: View {
    @State private var selected: Date
    let current: CalendarDate?
    /// A sheet already draws on paper under a manşet that names the field; a popover needs its
    /// own surface and label.
    let isOnPage: Bool
    let commit: (CalendarDate?) -> Void

    init(current: CalendarDate?, isOnPage: Bool = false, commit: @escaping (CalendarDate?) -> Void) {
        self.current = current
        self.isOnPage = isOnPage
        self.commit = commit
        _selected = State(initialValue: LocalDay.instant(for: current ?? LocalDay.today()))
    }

    var body: some View {
        if isOnPage {
            // The sheet scaffold already supplies the page margin.
            content
        } else {
            content
                .padding()
                .frame(minWidth: 280)
                .inkSurface()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            #if os(macOS)
                picker
            #else
                if isOnPage {
                    picker.labelsHidden()
                } else {
                    picker
                }
            #endif
            HStack {
                Button("Tarihi kaldır") { commit(nil) }
                    .disabled(current == nil)
                    .buttonStyle(InkTextButtonStyle())
                Spacer()
                if isOnPage {
                    Button("Tarihi seç") { commit(LocalDay.today(at: selected)) }
                        .buttonStyle(InkTextButtonStyle())
                        .fontWeight(.semibold)
                } else {
                    Button("Tarihi seç") { commit(LocalDay.today(at: selected)) }
                        .buttonStyle(InkPrimaryButtonStyle())
                }
            }
        }
    }

    @ViewBuilder
    private var picker: some View {
        #if os(macOS)
            let macPicker = TaskDateMacPicker(selected: $selected)
                .frame(width: 140, height: 24)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Color.ink.well,
                    in: RoundedRectangle(cornerRadius: InkSize.kanbanCorner, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: InkSize.kanbanCorner, style: .continuous)
                        .strokeBorder(Color.ink.control, lineWidth: InkStroke.control)
                )
            if isOnPage {
                macPicker
            } else {
                HStack {
                    Text("Görev tarihi")
                        .font(.ink.byline)
                        .foregroundStyle(Color.ink.text)
                    Spacer()
                    macPicker
                }
            }
        #else
            DatePicker("Görev tarihi", selection: $selected, displayedComponents: .date)
                .environment(\.calendar, Calendar(identifier: .gregorian))
        #endif
    }
}

#if os(macOS)
    import AppKit

    struct TaskDateMacPicker: NSViewRepresentable {
        @Binding var selected: Date

        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }

        func makeNSView(context: Context) -> NSDatePicker {
            let picker = NSDatePicker()
            picker.datePickerStyle = .textFieldAndStepper
            picker.datePickerElements = .yearMonthDay
            picker.isBordered = false
            picker.isBezeled = false
            picker.drawsBackground = false
            picker.calendar = Calendar(identifier: .gregorian)
            picker.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            picker.textColor = NSColor(Color.ink.text)
            picker.target = context.coordinator
            picker.action = #selector(Coordinator.dateChanged(_:))
            picker.setAccessibilityLabel(String(localized: "Görev tarihi"))
            return picker
        }

        func updateNSView(_ nsView: NSDatePicker, context: Context) {
            context.coordinator.parent = self
            nsView.dateValue = selected
            nsView.textColor = NSColor(Color.ink.text)
        }

        @MainActor
        final class Coordinator: NSObject {
            var parent: TaskDateMacPicker
            init(_ parent: TaskDateMacPicker) {
                self.parent = parent
            }

            @objc func dateChanged(_ sender: NSDatePicker) {
                parent.selected = sender.dateValue
            }
        }
    }
#endif
