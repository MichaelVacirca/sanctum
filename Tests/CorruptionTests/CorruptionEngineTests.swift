import XCTest
@testable import Sanctum

final class CorruptionEngineTests: XCTestCase {
    func testStartsAtZero() {
        let engine = CorruptionEngine(windowDuration: 3600)
        XCTAssertEqual(engine.corruptionIndex, 0, accuracy: 0.001)
    }

    func testAccumulatesEnergy() {
        let engine = CorruptionEngine(windowDuration: 100)
        for _ in 0..<60 {
            engine.update(energy: 1.0, deltaTime: 1.0)
        }
        XCTAssertGreaterThan(engine.corruptionIndex, 0)
        XCTAssertLessThanOrEqual(engine.corruptionIndex, 1.0)
    }

    func testSilenceDoesNotIncrease() {
        let engine = CorruptionEngine(windowDuration: 3600)
        engine.update(energy: 0, deltaTime: 1.0)
        engine.update(energy: 0, deltaTime: 1.0)
        XCTAssertEqual(engine.corruptionIndex, 0, accuracy: 0.001)
    }

    func testClampsAtOne() {
        let engine = CorruptionEngine(windowDuration: 10)
        for _ in 0..<1000 {
            engine.update(energy: 1.0, deltaTime: 1.0)
        }
        XCTAssertEqual(engine.corruptionIndex, 1.0, accuracy: 0.001)
    }

    func testReset() {
        let engine = CorruptionEngine(windowDuration: 100)
        for _ in 0..<50 {
            engine.update(energy: 1.0, deltaTime: 1.0)
        }
        XCTAssertGreaterThan(engine.corruptionIndex, 0)
        engine.reset()
        XCTAssertEqual(engine.corruptionIndex, 0, accuracy: 0.001)
    }
}
