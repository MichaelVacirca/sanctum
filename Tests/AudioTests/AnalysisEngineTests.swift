import XCTest
@testable import Sanctum

final class AnalysisEngineTests: XCTestCase {

    func testSilenceProducesZeroBands() {
        let engine = AnalysisEngine(sampleRate: 48000)
        let silence = [Float](repeating: 0, count: 4096)
        let state = engine.analyze(samples: silence)

        XCTAssertEqual(state.subBass, 0, accuracy: 0.01)
        XCTAssertEqual(state.bass, 0, accuracy: 0.01)
        XCTAssertEqual(state.mids, 0, accuracy: 0.01)
        XCTAssertEqual(state.highs, 0, accuracy: 0.01)
    }

    func testSubBassDetection() {
        let engine = AnalysisEngine(sampleRate: 48000)
        let samples = generateSineWave(frequency: 50, sampleRate: 48000, count: 4096)
        // Call multiple times to let smoothing converge
        _ = engine.analyze(samples: samples)
        _ = engine.analyze(samples: samples)
        _ = engine.analyze(samples: samples)
        _ = engine.analyze(samples: samples)
        let state = engine.analyze(samples: samples)

        XCTAssertGreaterThan(state.subBass, 0.3, "Sub-bass should be dominant")
        XCTAssertGreaterThan(state.subBass, state.mids, "Sub-bass should exceed mids")
        XCTAssertGreaterThan(state.subBass, state.highs, "Sub-bass should exceed highs")
    }

    func testBassDetection() {
        let engine = AnalysisEngine(sampleRate: 48000)
        let samples = generateSineWave(frequency: 150, sampleRate: 48000, count: 4096)
        _ = engine.analyze(samples: samples)
        _ = engine.analyze(samples: samples)
        _ = engine.analyze(samples: samples)
        _ = engine.analyze(samples: samples)
        let state = engine.analyze(samples: samples)

        XCTAssertGreaterThan(state.bass, 0.3, "Bass should be dominant")
        XCTAssertGreaterThan(state.bass, state.subBass, "Bass should exceed sub-bass")
    }

    func testMidsDetection() {
        let engine = AnalysisEngine(sampleRate: 48000)
        let samples = generateSineWave(frequency: 1000, sampleRate: 48000, count: 4096)
        _ = engine.analyze(samples: samples)
        _ = engine.analyze(samples: samples)
        _ = engine.analyze(samples: samples)
        _ = engine.analyze(samples: samples)
        let state = engine.analyze(samples: samples)

        XCTAssertGreaterThan(state.mids, 0.3, "Mids should be dominant")
        XCTAssertGreaterThan(state.mids, state.subBass, "Mids should exceed sub-bass")
    }

    func testHighsDetection() {
        let engine = AnalysisEngine(sampleRate: 48000)
        let samples = generateSineWave(frequency: 8000, sampleRate: 48000, count: 4096)
        // More iterations needed - highs energy spreads across many bins
        for _ in 0..<10 {
            _ = engine.analyze(samples: samples)
        }
        let state = engine.analyze(samples: samples)

        XCTAssertGreaterThan(state.highs, 0.2, "Highs should be dominant")
        XCTAssertGreaterThan(state.highs, state.subBass, "Highs should exceed sub-bass")
    }

    func testSpectrumLength() {
        let engine = AnalysisEngine(sampleRate: 48000)
        let samples = [Float](repeating: 0, count: 4096)
        let state = engine.analyze(samples: samples)
        XCTAssertEqual(state.rawSpectrum.count, 2048)
    }

    private func generateSineWave(frequency: Float, sampleRate: Float, count: Int) -> [Float] {
        (0..<count).map { i in
            sinf(2.0 * .pi * frequency * Float(i) / sampleRate)
        }
    }
}
