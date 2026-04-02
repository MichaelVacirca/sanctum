import Foundation

struct BeatResult {
    let isBeat: Bool
    let isTransient: Bool
    let beatPhase: Float
    let bpm: Float
}

final class BeatDetector {
    private let sampleRate: Float
    var currentBPM: Float = 120
    private var beatPhaseAccumulator: Float = 0
    private var bassHistory: [Float] = []
    private var energyHistory: [Float] = []
    private let historySize = 120
    private var lastBeatTime: Double = 0
    private var beatIntervals: [Double] = []
    private let maxIntervals = 16
    private let beatThresholdMultiplier: Float = 1.8
    private let transientThresholdMultiplier: Float = 2.5
    private let minBeatInterval: Double = 0.2
    private var elapsedTime: Double = 0

    init(sampleRate: Float = 48000) {
        self.sampleRate = sampleRate
    }

    func process(bassEnergy: Float, overallEnergy: Float, deltaTime: Float) -> BeatResult {
        elapsedTime += Double(deltaTime)

        bassHistory.append(bassEnergy)
        energyHistory.append(overallEnergy)
        if bassHistory.count > historySize { bassHistory.removeFirst() }
        if energyHistory.count > historySize { energyHistory.removeFirst() }

        let bassAvg = bassHistory.reduce(0, +) / Float(bassHistory.count)
        let isBeat = bassEnergy > bassAvg * beatThresholdMultiplier
                     && bassEnergy > 0.15
                     && (elapsedTime - lastBeatTime) > minBeatInterval

        if isBeat {
            let interval = elapsedTime - lastBeatTime
            if interval > minBeatInterval && interval < 2.0 {
                beatIntervals.append(interval)
                if beatIntervals.count > maxIntervals { beatIntervals.removeFirst() }
                if beatIntervals.count >= 4 {
                    let avgInterval = beatIntervals.reduce(0, +) / Double(beatIntervals.count)
                    currentBPM = Float(60.0 / avgInterval)
                }
            }
            lastBeatTime = elapsedTime
            beatPhaseAccumulator = 0
        }

        let energyAvg = energyHistory.reduce(0, +) / Float(energyHistory.count)
        let isTransient = overallEnergy > energyAvg * transientThresholdMultiplier
                          && overallEnergy > 0.5

        let beatsPerSecond = currentBPM / 60.0
        beatPhaseAccumulator += deltaTime * beatsPerSecond
        let phase = beatPhaseAccumulator.truncatingRemainder(dividingBy: 1.0)

        return BeatResult(isBeat: isBeat, isTransient: isTransient, beatPhase: phase, bpm: currentBPM)
    }

    func reset() {
        bassHistory.removeAll()
        energyHistory.removeAll()
        beatIntervals.removeAll()
        beatPhaseAccumulator = 0
        lastBeatTime = 0
        elapsedTime = 0
        currentBPM = 120
    }
}
