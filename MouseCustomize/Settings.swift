import Foundation

/// How one wheel (main wheel or thumb wheel) should behave.
struct ScrollSettings: Codable, Equatable {
    var enabled = true
    var reverse = false
    /// Distance multiplier, 0.25…5.
    var speed = 1.0
    var smooth = true
    /// Seconds a single wheel tick takes to glide to a stop, 0.1…0.6.
    var smoothDuration = 0.25
}

/// What an extra mouse button does when pressed.
enum ActionKind: String, Codable, CaseIterable, Identifiable {
    case passThrough
    case disabled
    case middleClick
    case back
    case forward
    case missionControl
    case appExpose
    case showDesktop
    case spaceLeft
    case spaceRight
    case shortcut

    var id: String { rawValue }

    var title: String {
        switch self {
        case .passThrough: return "Default"
        case .disabled: return "Do Nothing"
        case .middleClick: return "Middle Click"
        case .back: return "Back (⌘[)"
        case .forward: return "Forward (⌘])"
        case .missionControl: return "Mission Control"
        case .appExpose: return "App Exposé"
        case .showDesktop: return "Show Desktop"
        case .spaceLeft: return "Previous Space (⌃←)"
        case .spaceRight: return "Next Space (⌃→)"
        case .shortcut: return "Keyboard Shortcut…"
        }
    }
}

/// A recorded key combination. `modifiers` holds `CGEventFlags` raw bits.
struct KeyShortcut: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt64
    var display: String
}

struct ButtonMapping: Codable, Equatable {
    var action: ActionKind = .passThrough
    var shortcut: KeyShortcut? = nil
}

/// Mouse buttons are identified by their CoreGraphics button number:
/// 0 = left, 1 = right, 2 = middle, 3 = back, 4 = forward, 5+ = extra buttons.
enum MouseButton {
    /// Rows that are always shown in the Buttons tab.
    static let standard = [2, 3, 4]

    static func name(_ button: Int) -> String {
        switch button {
        case 2: return "Middle button"
        case 3: return "Back button"
        case 4: return "Forward button"
        default: return "Button \(button + 1)"
        }
    }
}

/// All user settings, persisted to `UserDefaults` on every change.
/// Read directly by the event tap, which runs on the main run loop.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private enum Key {
        static let isEnabled = "isEnabled"
        static let buttonMappings = "buttonMappings"
        static let wheel = "wheel"
        static let thumbWheel = "thumbWheel"
        static let didExplainPermission = "didExplainPermission"
    }

    private let defaults = UserDefaults.standard

    /// Master switch. When off, every event passes through untouched.
    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Key.isEnabled) }
    }

    /// Keyed by CoreGraphics button number (see `MouseButton`).
    @Published var buttonMappings: [Int: ButtonMapping] {
        didSet { save(buttonMappings, forKey: Key.buttonMappings) }
    }

    @Published var wheel: ScrollSettings {
        didSet { save(wheel, forKey: Key.wheel) }
    }

    @Published var thumbWheel: ScrollSettings {
        didSet { save(thumbWheel, forKey: Key.thumbWheel) }
    }

    /// Set once the permission explanation has been shown, so it never appears again.
    @Published var didExplainPermission: Bool {
        didSet { defaults.set(didExplainPermission, forKey: Key.didExplainPermission) }
    }

    private init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.object(forKey: Key.isEnabled) as? Bool ?? true
        buttonMappings = Self.load([Int: ButtonMapping].self, forKey: Key.buttonMappings, from: defaults) ?? [
            3: ButtonMapping(action: .back),
            4: ButtonMapping(action: .forward),
        ]
        wheel = Self.load(ScrollSettings.self, forKey: Key.wheel, from: defaults) ?? ScrollSettings()
        thumbWheel = Self.load(ScrollSettings.self, forKey: Key.thumbWheel, from: defaults) ?? ScrollSettings()
        didExplainPermission = defaults.bool(forKey: Key.didExplainPermission)
    }

    private func save<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, forKey key: String, from defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
