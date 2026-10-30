import Carbon.HIToolbox
import SwiftUI

struct ButtonsView: View {
    @ObservedObject private var controller = AppController.shared
    @ObservedObject private var settings = SettingsStore.shared

    private var buttons: [Int] {
        Set(MouseButton.standard).union(settings.buttonMappings.keys).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(buttons, id: \.self) { button in
                ButtonRow(
                    button: button,
                    mapping: mapping(for: button),
                    removable: !MouseButton.standard.contains(button),
                    onRemove: { settings.buttonMappings[button] = nil }
                )
            }

            if controller.isCapturingButton {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Press a mouse button…")
                    Spacer()
                    Button("Cancel") { controller.cancelButtonCapture() }
                }
            } else {
                Button {
                    controller.beginButtonCapture()
                } label: {
                    Label("Add Button…", systemImage: "plus")
                }
                .disabled(!controller.isTapRunning)
            }

            Text("Left and right click are never changed.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .onDisappear { controller.cancelButtonCapture() }
    }

    private func mapping(for button: Int) -> Binding<ButtonMapping> {
        Binding(
            get: { settings.buttonMappings[button] ?? ButtonMapping() },
            set: { settings.buttonMappings[button] = $0 }
        )
    }
}

private struct ButtonRow: View {
    let button: Int
    @Binding var mapping: ButtonMapping
    let removable: Bool
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                Text(MouseButton.name(button))
                Spacer(minLength: 8)
                Picker("", selection: $mapping.action) {
                    ForEach(ActionKind.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(width: 180)

                Button(action: onRemove) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove this button")
                .opacity(removable ? 1 : 0)
                .disabled(!removable)
            }

            if mapping.action == .shortcut {
                HStack(spacing: 6) {
                    Text("Shortcut").font(.caption).foregroundColor(.secondary)
                    ShortcutRecorder(shortcut: $mapping.shortcut)
                }
                // Line up under the picker, past the remove button's slot.
                .padding(.trailing, 22)
            }
        }
    }
}

/// Records a key combination by listening for key presses in this app's own panel.
/// A local monitor only sees events sent to this app, so it needs no extra permission.
private struct ShortcutRecorder: View {
    @Binding var shortcut: KeyShortcut?
    // Not `private`: that would make the memberwise init private and unusable from ButtonRow.
    @State var isRecording = false
    @State var monitor: Any?

    var body: some View {
        Button(isRecording ? "Type shortcut… (esc to cancel)" : (shortcut?.display ?? "Record Shortcut")) {
            if isRecording { stop() } else { start() }
        }
        .onDisappear { stop() }
    }

    private func start() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode != UInt16(kVK_Escape) {
                shortcut = KeyShortcut(event: event)
            }
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }
}
