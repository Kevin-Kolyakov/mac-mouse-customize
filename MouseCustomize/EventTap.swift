import AppKit

/// Owns the app's one and only `CGEventTap`.
///
/// The tap only listens for extra-button and scroll-wheel events. It never sees keyboard
/// events, so it needs Accessibility permission and nothing else (no Input Monitoring).
/// Left and right clicks are never intercepted, so a bug here can't take away your mouse.
final class EventTap {
    private let settings: SettingsStore
    private let scroller = SmoothScroller()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Buttons whose mouse-down was swallowed; their drag and up events are swallowed too.
    private var swallowedButtons = Set<Int64>()

    /// When set, the next extra-button press is reported here (for "Add Button…") instead of handled.
    var captureHandler: ((Int) -> Void)?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    var isRunning: Bool { tap != nil }

    /// Creates the tap on the main run loop. Fails if Accessibility access hasn't been granted.
    func start() -> Bool {
        guard tap == nil else { return true }

        let types: [CGEventType] = [.otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let eventTap = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()
                return eventTap.handle(type, event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }
        // Common modes keep the tap working while menus or sliders are being tracked.
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        runLoopSource = source
        return true
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CFMachPortInvalidate(tap)
        self.tap = nil
        runLoopSource = nil
        swallowedButtons.removeAll()
        scroller.cancel()
    }

    // MARK: - Routing

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS turns the tap off if a callback is too slow; turn it straight back on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        case .otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel:
            break
        default:
            return pass
        }

        if event.getIntegerValueField(.eventSourceUserData) == Synthetic.marker {
            return pass
        }

        let keep: Bool
        if type == .scrollWheel {
            keep = !settings.isEnabled || handleScroll(event)
        } else {
            keep = handleButton(type, event)
        }
        return keep ? pass : nil
    }

    // MARK: - Buttons

    /// Returns `false` to swallow the event.
    private func handleButton(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let button = event.getIntegerValueField(.mouseEventButtonNumber)

        if type != .otherMouseDown {
            if swallowedButtons.contains(button) {
                if type == .otherMouseUp { swallowedButtons.remove(button) }
                return false
            }
            if settings.isEnabled, settings.buttonMappings[Int(button)]?.action == .middleClick {
                event.setIntegerValueField(.mouseEventButtonNumber, value: 2)
            }
            return true
        }

        if let capture = captureHandler {
            captureHandler = nil
            swallowedButtons.insert(button)
            DispatchQueue.main.async { capture(Int(button)) }
            return false
        }

        guard settings.isEnabled, let mapping = settings.buttonMappings[Int(button)] else { return true }

        switch mapping.action {
        case .passThrough:
            return true
        case .shortcut where mapping.shortcut == nil:
            return true // Shortcut chosen but not recorded yet.
        case .middleClick:
            event.setIntegerValueField(.mouseEventButtonNumber, value: 2)
            return true
        case .disabled:
            swallowedButtons.insert(button)
            return false
        default:
            swallowedButtons.insert(button)
            // Run the action after the callback returns so the tap is never slowed down.
            DispatchQueue.main.async { ActionPerformer.perform(mapping) }
            return false
        }
    }

    // MARK: - Scrolling

    /// Returns `false` to swallow the event (the smooth scroller re-posts it).
    private func handleScroll(_ event: CGEvent) -> Bool {
        // Trackpads and the Magic Mouse send continuous, phased events. Leave them alone.
        if event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
            || event.getIntegerValueField(.scrollWheelEventScrollPhase) != 0
            || event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0 {
            return true
        }

        let dy = pixelDelta(event, point: .scrollWheelEventPointDeltaAxis1, line: .scrollWheelEventDeltaAxis1)
        let dx = pixelDelta(event, point: .scrollWheelEventPointDeltaAxis2, line: .scrollWheelEventDeltaAxis2)
        guard dx != 0 || dy != 0 else { return true }

        let flags = event.flags
        let shift = flags.contains(.maskShift)
        let vertical = abs(dy) >= abs(dx)

        // The thumb wheel sends plain horizontal events. Shift + main wheel also scrolls
        // horizontally, but it belongs to the main wheel's settings.
        let config = (vertical || shift) ? settings.wheel : settings.thumbWheel
        guard config.enabled else { return true }

        let factor = config.speed * (config.reverse ? -1 : 1)
        let zoomModifiers = !flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty

        if !config.smooth || zoomModifiers {
            scale(event, by: factor)
            return true
        }

        if vertical && !shift {
            scroller.add(dy * factor, axis: .vertical, duration: config.smoothDuration)
        } else {
            // With Shift held, macOS may or may not have moved the delta to the horizontal axis
            // already, so take whichever axis has it and scroll horizontally.
            scroller.add((vertical ? dy : dx) * factor, axis: .horizontal, duration: config.smoothDuration)
        }
        return false
    }

    /// Pixel distance for one axis, falling back to line delta for events that only carry lines.
    private func pixelDelta(_ event: CGEvent, point: CGEventField, line: CGEventField) -> Double {
        let pixels = event.getIntegerValueField(point)
        return Double(pixels != 0 ? pixels : event.getIntegerValueField(line) * 10)
    }

    private static let axisFields: [(line: CGEventField, fixed: CGEventField, point: CGEventField)] = [
        (.scrollWheelEventDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventPointDeltaAxis1),
        (.scrollWheelEventDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventPointDeltaAxis2),
    ]

    /// Applies speed and direction to an event in place. Apps read different delta fields,
    /// so all three (lines, fixed-point lines, pixels) are scaled.
    private func scale(_ event: CGEvent, by factor: Double) {
        for fields in Self.axisFields {
            // Read everything before writing: setting one field can make CoreGraphics recompute the others.
            let lines = event.getIntegerValueField(fields.line)
            let fixed = event.getDoubleValueField(fields.fixed)
            let points = event.getIntegerValueField(fields.point)
            guard lines != 0 || fixed != 0 || points != 0 else { continue }

            // Round lines away from zero so a slow speed never turns a tick into nothing.
            event.setIntegerValueField(fields.line, value: Int64((Double(lines) * factor).rounded(.awayFromZero)))
            event.setDoubleValueField(fields.fixed, value: fixed * factor)
            event.setIntegerValueField(fields.point, value: Int64((Double(points) * factor).rounded()))
        }
    }
}
