import Cocoa

final class DebugOverlay {
    private var isVisible = true
    private var frameCount = 0
    private var lastFPSTime: Double = 0
    private var currentFPS: Int = 0
    private let overlayView: NSTextField

    init(parentView: NSView) {
        overlayView = NSTextField(frame: NSRect(x: 10, y: 10, width: 400, height: 200))
        overlayView.isEditable = false
        overlayView.isBordered = false
        overlayView.backgroundColor = NSColor.black.withAlphaComponent(0.6)
        overlayView.textColor = .green
        overlayView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        overlayView.isHidden = !isVisible
        parentView.addSubview(overlayView)
    }

    func toggle() {
        isVisible.toggle()
        overlayView.isHidden = !isVisible
    }

    func update(audioState: AudioState, time: Double) {
        guard isVisible else { return }

        frameCount += 1
        if time - lastFPSTime >= 1.0 {
            currentFPS = frameCount
            frameCount = 0
            lastFPSTime = time
        }

        let phase = CorruptionPhase.from(index: audioState.corruptionIndex)
        let barLength = 20

        func bar(_ value: Float) -> String {
            let filled = Int(value * Float(barLength))
            return String(repeating: "█", count: filled) + String(repeating: "░", count: barLength - filled)
        }

        let text = """
        SANCTUM DEBUG
        FPS: \(currentFPS)
        ─────────────────────────
        SUB-BASS [\(bar(audioState.subBass))] \(String(format: "%.2f", audioState.subBass))
        BASS     [\(bar(audioState.bass))] \(String(format: "%.2f", audioState.bass))
        MIDS     [\(bar(audioState.mids))] \(String(format: "%.2f", audioState.mids))
        HIGHS    [\(bar(audioState.highs))] \(String(format: "%.2f", audioState.highs))
        ─────────────────────────
        BPM: \(String(format: "%.0f", audioState.bpm))  BEAT: \(audioState.isBeat ? "●" : "○")
        CORRUPTION: [\(bar(audioState.corruptionIndex))] \(String(format: "%.3f", audioState.corruptionIndex))
        PHASE: \(phase.rawValue.uppercased())
        """

        overlayView.stringValue = text
    }
}
