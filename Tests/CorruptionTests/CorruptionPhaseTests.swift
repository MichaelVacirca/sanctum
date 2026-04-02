import XCTest
@testable import Sanctum

final class CorruptionPhaseTests: XCTestCase {
    func testPhaseFromCorruptionIndex() {
        XCTAssertEqual(CorruptionPhase.from(index: 0.0), .sacred)
        XCTAssertEqual(CorruptionPhase.from(index: 0.1), .sacred)
        XCTAssertEqual(CorruptionPhase.from(index: 0.2), .awakening)
        XCTAssertEqual(CorruptionPhase.from(index: 0.3), .awakening)
        XCTAssertEqual(CorruptionPhase.from(index: 0.5), .fracture)
        XCTAssertEqual(CorruptionPhase.from(index: 0.7), .profane)
        XCTAssertEqual(CorruptionPhase.from(index: 0.9), .abyss)
        XCTAssertEqual(CorruptionPhase.from(index: 1.0), .abyss)
    }

    func testPhaseLocalProgress() {
        let progress = CorruptionPhase.localProgress(at: 0.3)
        XCTAssertEqual(progress, 0.5, accuracy: 0.01)
    }
}
