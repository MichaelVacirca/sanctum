import XCTest
@testable import Sanctum

final class BeatDetectorTests: XCTestCase {

    func testSilenceProducesNoBeats() {
        let detector = BeatDetector(sampleRate: 48000)
        let result = detector.process(bassEnergy: 0, overallEnergy: 0, deltaTime: 1.0 / 60.0)
        XCTAssertFalse(result.isBeat)
        XCTAssertFalse(result.isTransient)
    }

    func testSuddenEnergySpikeTriggersBeat() {
        let detector = BeatDetector(sampleRate: 48000)
        for _ in 0..<30 {
            _ = detector.process(bassEnergy: 0.05, overallEnergy: 0.1, deltaTime: 1.0 / 60.0)
        }
        let result = detector.process(bassEnergy: 0.9, overallEnergy: 0.8, deltaTime: 1.0 / 60.0)
        XCTAssertTrue(result.isBeat, "A large sudden bass spike should trigger a beat")
    }

    func testBeatPhaseRamps() {
        let detector = BeatDetector(sampleRate: 48000)
        detector.currentBPM = 120
        let r1 = detector.process(bassEnergy: 0.05, overallEnergy: 0.1, deltaTime: 0.25)
        XCTAssertEqual(r1.beatPhase, 0.5, accuracy: 0.1)
    }

    func testTransientDetectsLargeOverallSpike() {
        let detector = BeatDetector(sampleRate: 48000)
        for _ in 0..<60 {
            _ = detector.process(bassEnergy: 0.3, overallEnergy: 0.3, deltaTime: 1.0 / 60.0)
        }
        let result = detector.process(bassEnergy: 0.95, overallEnergy: 0.95, deltaTime: 1.0 / 60.0)
        XCTAssertTrue(result.isTransient)
    }
}
