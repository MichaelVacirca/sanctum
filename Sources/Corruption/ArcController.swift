import Foundation

/// Drives the 0→1 arc index that everything visual keys off. Three ways to
/// move it:
///
/// - **energy** — the original behavior: cumulative audio energy over a window.
/// - **schedule** — wall-clock time between two hours (e.g. 9 PM → 2 AM), so a
///   themed night advances itself from start to peak automatically.
/// - **manual override** — the operator scrubs it with the keyboard; this
///   freezes the automatic driver until `resumeAuto()` is called.
final class ArcController {
    enum Mode: String {
        case energy
        case schedule
    }

    var mode: Mode
    /// Schedule window as fractional hours on a 24h clock (21.0 = 9 PM).
    var startHour: Double
    var endHour: Double

    private let energyEngine: CorruptionEngine
    private var manualOverride: Float?
    private(set) var index: Float = 0

    /// True while the operator has taken manual control.
    var isManual: Bool { manualOverride != nil }

    init(mode: Mode, startHour: Double, endHour: Double, energyWindow: Double) {
        self.mode = mode
        self.startHour = startHour
        self.endHour = endHour
        self.energyEngine = CorruptionEngine(windowDuration: energyWindow)
    }

    func update(energy: Float, deltaTime: Float, now: Date = Date()) {
        // Keep integrating energy so switching back to .energy is seamless.
        energyEngine.update(energy: energy, deltaTime: deltaTime)

        if let override = manualOverride {
            index = override
            return
        }
        switch mode {
        case .energy:
            index = energyEngine.corruptionIndex
        case .schedule:
            index = Self.scheduleProgress(now: now, startHour: startHour, endHour: endHour)
        }
    }

    /// Nudge the arc by `delta` (positive = advance, negative = roll back).
    /// Takes manual control until `resumeAuto()`.
    func advance(by delta: Float) {
        manualOverride = min(1, max(0, (manualOverride ?? index) + delta))
    }

    /// Hand control back to the automatic driver (schedule / energy).
    func resumeAuto() {
        manualOverride = nil
    }

    /// Roll all the way back to the start of the night (sunset) and hold there.
    func reset() {
        manualOverride = 0
        energyEngine.reset()
    }

    /// Fraction (0...1) through a clock window. Handles windows that wrap past
    /// midnight (e.g. 21:00 → 02:00). Before the window it's 0; after, 1.
    static func scheduleProgress(now: Date, startHour: Double, endHour: Double,
                                 calendar: Calendar = .current) -> Float {
        let c = calendar.dateComponents([.hour, .minute, .second], from: now)
        let h = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600
        if endHour > startHour {
            return Float(min(1, max(0, (h - startHour) / (endHour - startHour))))
        }
        // Wraps midnight: only the post-midnight tail (≤ endHour) maps forward.
        var hh = h
        if hh <= endHour { hh += 24 }
        return Float(min(1, max(0, (hh - startHour) / ((endHour + 24) - startHour))))
    }

    /// Parse "HH:mm" (or "HH") into fractional hours. Defaults to `fallback`.
    static func parseHour(_ string: String, fallback: Double) -> Double {
        let parts = string.split(separator: ":")
        guard let h = parts.first.flatMap({ Double($0) }) else { return fallback }
        let m = parts.count > 1 ? (Double(parts[1]) ?? 0) : 0
        return h + m / 60
    }
}
