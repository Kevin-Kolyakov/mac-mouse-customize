import SwiftUI

/// Settings for one wheel. Used for both the main scroll wheel and the thumb wheel.
struct ScrollSettingsView: View {
    let title: String
    @Binding var config: ScrollSettings
    var note: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(title, isOn: $config.enabled)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Toggle("Reverse direction", isOn: $config.reverse)
                    Text("Flips this wheel relative to the system Natural Scrolling setting. Trackpads aren't affected.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                sliderRow("Speed", value: $config.speed, in: 0.25...5, step: 0.25,
                          label: String(format: "%.2f×", config.speed))

                Toggle("Smooth scrolling", isOn: $config.smooth)

                sliderRow("Glide", value: $config.smoothDuration, in: 0.1...0.6, step: 0.05,
                          label: String(format: "%.2f s", config.smoothDuration))
                    .disabled(!config.smooth)
            }
            .disabled(!config.enabled)

            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func sliderRow(_ name: String, value: Binding<Double>, in range: ClosedRange<Double>,
                           step: Double, label: String) -> some View {
        HStack {
            Text(name).frame(width: 50, alignment: .leading)
            Slider(value: value, in: range, step: step)
            Text(label)
                .monospacedDigit()
                .frame(width: 52, alignment: .trailing)
        }
    }
}
