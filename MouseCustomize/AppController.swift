import AppKit
import ApplicationServices
import Combine
import ServiceManagement

/// Ties together the Accessibility permission, the event tap and the login item.
final class AppController: ObservableObject {
    static let shared = AppController()

    let settings = SettingsStore.shared
    private lazy var eventTap = EventTap(settings: settings)
    private var trustTimer: Timer?

    @Published private(set) var isTrusted = AXIsProcessTrusted()
    @Published private(set) var isTapRunning = false
    /// Access looks granted but the tap couldn't be created (usually a stale permission entry).
    @Published private(set) var tapFailed = false
    @Published private(set) var isCapturingButton = false
    @Published private(set) var launchAtLogin = false

    private init() {
        refreshLaunchAtLogin()
    }

    /// Called once from `applicationDidFinishLaunching`.
    func launch() {
        refreshTrust()

        if !isTrusted && !settings.didExplainPermission {
            // Let the menu bar item finish appearing before the alert takes focus.
            DispatchQueue.main.async { self.explainPermission() }
        }

        // Start as soon as access is granted, and stop cleanly if it's revoked, with no relaunch.
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.refreshTrust() }
        RunLoop.main.add(timer, forMode: .common)
        trustTimer = timer
    }

    // MARK: - Accessibility permission

    private func refreshTrust() {
        let trusted = AXIsProcessTrusted()
        if isTrusted != trusted { isTrusted = trusted }

        if trusted && !eventTap.isRunning {
            let failed = !eventTap.start()
            if tapFailed != failed { tapFailed = failed }
        } else if !trusted && eventTap.isRunning {
            eventTap.stop()
        }
        if !trusted && tapFailed { tapFailed = false }
        if isTapRunning != eventTap.isRunning { isTapRunning = eventTap.isRunning }
    }

    /// Shown once, ever. After this the panel's banner is the only reminder.
    private func explainPermission() {
        settings.didExplainPermission = true
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Mouse Customize needs Accessibility access"
        alert.informativeText = """
        To remap mouse buttons and change how your scroll wheels behave, Mouse Customize \
        has to read and adjust mouse events as they happen. macOS only allows that for apps \
        you approve under Accessibility.

        It only handles mouse buttons and scrolling. It never reads your keyboard, and \
        nothing leaves your Mac.

        Click Continue, then turn on Mouse Customize in System Settings → Privacy & Security → \
        Accessibility. It starts working as soon as you do; no relaunch needed.
        """
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Not Now")

        if alert.runModal() == .alertFirstButtonReturn {
            // "AXTrustedCheckOptionPrompt" is the value of kAXTrustedCheckOptionPrompt. This shows
            // the system prompt and adds the app to the Accessibility list.
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Adding buttons

    func beginButtonCapture() {
        guard eventTap.isRunning else { return }
        isCapturingButton = true
        eventTap.captureHandler = { [weak self] button in
            guard let self else { return }
            self.isCapturingButton = false
            if self.settings.buttonMappings[button] == nil {
                self.settings.buttonMappings[button] = ButtonMapping()
            }
        }
    }

    func cancelButtonCapture() {
        eventTap.captureHandler = nil
        if isCapturingButton { isCapturingButton = false }
    }

    // MARK: - Launch at login

    /// Uses `SMAppService.mainApp`, which registers this app itself, with no helper tool.
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("MouseCustomize: couldn't change login item: \(error)")
        }
        if SMAppService.mainApp.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
        refreshLaunchAtLogin()
    }

    func refreshLaunchAtLogin() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled || status == .requiresApproval
    }
}
