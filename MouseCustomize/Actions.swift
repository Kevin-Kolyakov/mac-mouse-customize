import AppKit
import Carbon.HIToolbox

enum Synthetic {
    /// Stored in `.eventSourceUserData` on every event this app posts,
    /// so the event tap can recognize and ignore its own output.
    static let marker: Int64 = 0x4D4F_5553 // "MOUS"
}

/// Runs the non-click button actions. Called on the main thread, outside the tap callback.
enum ActionPerformer {
    static func perform(_ mapping: ButtonMapping) {
        switch mapping.action {
        case .passThrough, .disabled, .middleClick:
            break // Handled directly in the event tap.
        case .back:
            postKey(CGKeyCode(kVK_ANSI_LeftBracket), flags: .maskCommand)
        case .forward:
            postKey(CGKeyCode(kVK_ANSI_RightBracket), flags: .maskCommand)
        case .missionControl:
            launchMissionControl()
        case .appExpose:
            launchMissionControl("2")
        case .showDesktop:
            launchMissionControl("1")
        case .spaceLeft:
            postKey(CGKeyCode(kVK_LeftArrow), flags: .maskControl)
        case .spaceRight:
            postKey(CGKeyCode(kVK_RightArrow), flags: .maskControl)
        case .shortcut:
            guard let shortcut = mapping.shortcut else { return }
            postKey(CGKeyCode(shortcut.keyCode), flags: CGEventFlags(rawValue: shortcut.modifiers))
        }
    }

    /// Posts a key down + key up. Posting events is covered by the Accessibility permission.
    static func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags) {
        var flags = flags
        // Real keyboards flag arrows, navigation and F-keys as "function" keys (and arrows as keypad);
        // some system shortcuts, like switching Spaces, only match when those flags are present.
        if KeyNames.functionKeys.contains(Int(keyCode)) { flags.insert(.maskSecondaryFn) }
        if KeyNames.arrowKeys.contains(Int(keyCode)) { flags.insert(.maskNumericPad) }

        let source = CGEventSource(stateID: .hidSystemState)
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: Synthetic.marker)
            event.post(tap: .cghidEventTap)
        }
    }

    /// The Mission Control app takes an optional argument: "1" shows the desktop, "2" shows the
    /// current app's windows. This avoids private Dock APIs.
    private static func launchMissionControl(_ argument: String? = nil) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/System/Applications/Mission Control.app/Contents/MacOS/Mission Control")
        process.arguments = argument.map { [$0] } ?? []
        do {
            try process.run()
        } catch {
            NSLog("MouseCustomize: couldn't launch Mission Control: \(error)")
        }
    }
}

enum KeyNames {
    static let arrowKeys: Set<Int> = [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow]

    static let functionKeys: Set<Int> = arrowKeys.union([
        kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown, kVK_ForwardDelete, kVK_Help,
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ])

    private static let special: [Int: String] = [
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_Return: "↩", kVK_ANSI_KeypadEnter: "⌤", kVK_Tab: "⇥", kVK_Space: "Space",
        kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Escape: "⎋",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]

    static func name(keyCode: UInt16, characters: String?) -> String {
        if let name = special[Int(keyCode)] { return name }
        if let characters, !characters.isEmpty { return characters.uppercased() }
        return "Key \(keyCode)"
    }
}

extension KeyShortcut {
    /// Builds a shortcut from a key press captured in the app's own window.
    init(event: NSEvent) {
        let modifiers = event.modifierFlags
        var flags = CGEventFlags()
        var symbols = ""
        if modifiers.contains(.control) { flags.insert(.maskControl); symbols += "⌃" }
        if modifiers.contains(.option) { flags.insert(.maskAlternate); symbols += "⌥" }
        if modifiers.contains(.shift) { flags.insert(.maskShift); symbols += "⇧" }
        if modifiers.contains(.command) { flags.insert(.maskCommand); symbols += "⌘" }

        let key = KeyNames.name(keyCode: event.keyCode, characters: event.characters(byApplyingModifiers: []))
        self.init(keyCode: event.keyCode, modifiers: flags.rawValue, display: symbols + key)
    }
}
