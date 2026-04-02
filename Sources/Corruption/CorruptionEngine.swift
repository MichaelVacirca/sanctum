import Foundation

final class CorruptionEngine {
    private let windowDuration: Double
    private var cumulativeEnergy: Double = 0
    private(set) var corruptionIndex: Float = 0

    var currentPhase: CorruptionPhase {
        CorruptionPhase.from(index: corruptionIndex)
    }

    var localProgress: Float {
        CorruptionPhase.localProgress(at: corruptionIndex)
    }

    init(windowDuration: Double = 18000) {
        self.windowDuration = windowDuration
    }

    func update(energy: Float, deltaTime: Float) {
        cumulativeEnergy += Double(energy) * Double(deltaTime)
        corruptionIndex = min(1.0, Float(cumulativeEnergy / windowDuration))
    }

    func reset() {
        cumulativeEnergy = 0
        corruptionIndex = 0
    }
}
