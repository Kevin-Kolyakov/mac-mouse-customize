import SwiftUI

/// The panel shown when clicking the menu bar icon.
struct MenuView: View {
    @ObservedObject private var controller = AppController.shared
    @ObservedObject private var settings = SettingsStore.shared
    @State private var tab = Tab.buttons

    private enum Tab: String, CaseIterable, Identifiable {
        case buttons = "Buttons"
        case wheel = "Scroll Wheel"
        case thumb = "Thumb Wheel"

        var id: Self { self }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if !controller.isTrusted {
                banner(
                    title: "Accessibility access needed",
                    message: "Turn on Mouse Customize in System Settings → Privacy & Security → Accessibility. It starts working right away."
                )
            } else if controller.tapFailed {
                banner(
                    title: "Couldn't start",
                    message: "macOS reports access as granted, but the mouse hook couldn't start. This usually happens after a rebuild: select Mouse Customize in the Accessibility list, remove it with −, then add it again."
                )
            }

            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                switch tab {
                case .buttons:
                    ButtonsView()
                case .wheel:
                    ScrollSettingsView(title: "Customize scroll wheel", config: $settings.wheel)
                case .thumb:
                    ScrollSettingsView(
                        title: "Customize thumb wheel",
                        config: $settings.thumbWheel,
                        note: "For side wheels that send standard horizontal scrolling, like the Logitech MX Master's. If Logi Options+ manages that wheel, it may handle the events first."
                    )
                }
            }
            .disabled(!settings.isEnabled)

            Divider()

            HStack {
                Toggle("Launch at login", isOn: Binding(
                    get: { controller.launchAtLogin },
                    set: { controller.setLaunchAtLogin($0) }
                ))
                .toggleStyle(.checkbox)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 360)
        .onAppear { controller.refreshLaunchAtLogin() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "computermouse.fill")
                .font(.title2)
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Mouse Customize").font(.headline)
                Text(status).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Toggle("Enabled", isOn: $settings.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    private var status: String {
        if !controller.isTrusted { return "Waiting for Accessibility access" }
        if !controller.isTapRunning { return "Not running" }
        return settings.isEnabled ? "Active" : "Paused"
    }

    private func banner(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Accessibility Settings") { controller.openAccessibilitySettings() }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.15)))
    }
}
