import CoreGraphics
import Foundation
import QuartzCore

/// Turns discrete wheel ticks into a short, eased stream of pixel scroll events.
///
/// Each tick adds distance to a per-axis budget. A 120 Hz timer scrolls a shrinking
/// fraction of what's left each frame (exponential ease-out), so quick spins pile up
/// and feel faster, and a single tick glides to a stop over roughly `duration` seconds.
final class SmoothScroller {
    enum Axis {
        case vertical, horizontal
    }

    private struct Track {
        /// Pixels still to scroll.
        var remaining = 0.0
        /// Fraction of a pixel left over from the previous frame.
        var carry = 0.0
        var duration = 0.25

        mutating func add(_ pixels: Double, duration: Double) {
            guard pixels != 0 else { return }
            // Reversing direction cancels whatever was still gliding the other way.
            if remaining != 0, (remaining > 0) != (pixels > 0) {
                remaining = 0
                carry = 0
            }
            remaining += pixels
            self.duration = duration
        }

        /// Whole pixels to scroll this frame.
        mutating func step(dt: Double) -> Int32 {
            guard remaining != 0 else { return 0 }
            // About 98% of the distance is covered after 4 time constants.
            let tau = max(duration, 0.05) / 4
            var delta = remaining * (1 - exp(-dt / tau))
            if abs(remaining - delta) < 1 { delta = remaining }
            remaining -= delta

            let total = delta + carry
            let whole = remaining == 0 ? total.rounded() : total.rounded(.towardZero)
            carry = remaining == 0 ? 0 : total - whole
            return Int32(whole)
        }
    }

    private var vertical = Track()
    private var horizontal = Track()
    private var timer: Timer?
    private var lastTick: CFTimeInterval = 0
    private let frameInterval = 1.0 / 120

    func add(_ pixels: Double, axis: Axis, duration: Double) {
        switch axis {
        case .vertical: vertical.add(pixels, duration: duration)
        case .horizontal: horizontal.add(pixels, duration: duration)
        }

        guard timer == nil else { return }
        let timer = Timer(timeInterval: frameInterval, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        // Scroll the first frame right away so the wheel feels immediate.
        lastTick = CACurrentMediaTime() - frameInterval
        tick()
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        vertical = Track()
        horizontal = Track()
    }

    private func tick() {
        let now = CACurrentMediaTime()
        // Clamp so a stalled main thread doesn't dump the whole distance in one jump.
        let dt = min(now - lastTick, 0.05)
        lastTick = now

        let dy = vertical.step(dt: dt)
        let dx = horizontal.step(dt: dt)
        if dx != 0 || dy != 0 {
            post(dx: dx, dy: dy)
        }
        if vertical.remaining == 0 && horizontal.remaining == 0 {
            cancel()
        }
    }

    private func post(dx: Int32, dy: Int32) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: dy,
            wheel2: dx,
            wheel3: 0
        ) else { return }
        event.flags = []
        event.setIntegerValueField(.eventSourceUserData, value: Synthetic.marker)
        event.post(tap: .cgSessionEventTap)
    }
}
