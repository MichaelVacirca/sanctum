import XCTest
@testable import Sanctum

final class AudioCaptureTests: XCTestCase {

    func testRingBufferWriteAndRead() {
        let capture = AudioCapture(bufferSize: 1024)
        let samples = capture.getRecentSamples(count: 512)
        XCTAssertEqual(samples.count, 512)
        XCTAssertTrue(samples.allSatisfy { $0 == 0 })
    }

    func testAudioStateDefaults() {
        let state = AudioState.silent
        XCTAssertEqual(state.subBass, 0)
        XCTAssertEqual(state.bass, 0)
        XCTAssertEqual(state.mids, 0)
        XCTAssertEqual(state.highs, 0)
        XCTAssertEqual(state.corruptionIndex, 0)
        XCTAssertEqual(state.bpm, 120)
        XCTAssertFalse(state.isBeat)
    }

    func testOverallEnergy() {
        var state = AudioState()
        state.bands = (0.5, 0.5, 0.5, 0.5)
        XCTAssertEqual(state.overallEnergy, 0.5)

        state.bands = (1.0, 0.0, 0.5, 0.5)
        XCTAssertEqual(state.overallEnergy, 0.5)
    }
}
