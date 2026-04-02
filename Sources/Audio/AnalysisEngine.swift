import Foundation
import Accelerate

final class AnalysisEngine: @unchecked Sendable {
    private let sampleRate: Float
    private let fftSize: Int
    private let fftSetup: FFTSetup
    private let log2n: vDSP_Length
    private let windowBuffer: [Float]

    private let subBassRange: ClosedRange<Float> = 20...80
    private let bassRange: ClosedRange<Float> = 80...250
    private let midsRange: ClosedRange<Float> = 250...4000
    private let highsRange: ClosedRange<Float> = 4000...20000

    private var smoothedBands: (Float, Float, Float, Float) = (0, 0, 0, 0)
    private let smoothingFactor: Float = 0.3
    private let beatDetector: BeatDetector

    init(sampleRate: Float = 48000, fftSize: Int = 4096) {
        self.sampleRate = sampleRate
        self.fftSize = fftSize

        let log2n = vDSP_Length(log2(Float(fftSize)))
        self.log2n = log2n
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            fatalError("Failed to create FFT setup")
        }
        self.fftSetup = setup

        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_DENORM))
        self.windowBuffer = window
        self.beatDetector = BeatDetector(sampleRate: sampleRate)
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    func analyze(samples: [Float]) -> AudioState {
        guard samples.count >= fftSize else {
            return .silent
        }

        var windowed = [Float](repeating: 0, count: fftSize)
        var input = Array(samples.prefix(fftSize))
        vDSP_vmul(&input, 1, windowBuffer, 1, &windowed, 1, vDSP_Length(fftSize))

        let magnitudes = performFFT(windowed)

        let subBass = bandEnergy(magnitudes: magnitudes, range: subBassRange)
        let bass = bandEnergy(magnitudes: magnitudes, range: bassRange)
        let mids = bandEnergy(magnitudes: magnitudes, range: midsRange)
        let highs = bandEnergy(magnitudes: magnitudes, range: highsRange)

        let beatResult = beatDetector.process(
            bassEnergy: subBass,
            overallEnergy: (subBass + bass + mids + highs) / 4.0,
            deltaTime: Float(fftSize) / sampleRate
        )

        smoothedBands.0 = lerp(smoothedBands.0, subBass, t: smoothingFactor)
        smoothedBands.1 = lerp(smoothedBands.1, bass, t: smoothingFactor)
        smoothedBands.2 = lerp(smoothedBands.2, mids, t: smoothingFactor)
        smoothedBands.3 = lerp(smoothedBands.3, highs, t: smoothingFactor)

        var state = AudioState()
        state.bands = smoothedBands
        state.rawSpectrum = magnitudes
        state.isBeat = beatResult.isBeat
        state.isTransient = beatResult.isTransient
        state.beatPhase = beatResult.beatPhase
        state.bpm = beatResult.bpm
        return state
    }

    private func performFFT(_ samples: [Float]) -> [Float] {
        let halfN = fftSize / 2
        var realPart = [Float](repeating: 0, count: halfN)
        var imagPart = [Float](repeating: 0, count: halfN)

        samples.withUnsafeBufferPointer { samplesPtr in
            realPart.withUnsafeMutableBufferPointer { realPtr in
                imagPart.withUnsafeMutableBufferPointer { imagPtr in
                    var splitComplex = DSPSplitComplex(
                        realp: realPtr.baseAddress!,
                        imagp: imagPtr.baseAddress!
                    )
                    samplesPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(halfN))
                    }
                    vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))
                }
            }
        }

        var magnitudes = [Float](repeating: 0, count: halfN)
        realPart.withUnsafeBufferPointer { realPtr in
            imagPart.withUnsafeBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(
                    realp: UnsafeMutablePointer(mutating: realPtr.baseAddress!),
                    imagp: UnsafeMutablePointer(mutating: imagPtr.baseAddress!)
                )
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfN))
            }
        }

        var sqrtMagnitudes = [Float](repeating: 0, count: halfN)
        var count = Int32(halfN)
        vvsqrtf(&sqrtMagnitudes, &magnitudes, &count)

        let scale = 2.0 / Float(fftSize)
        var scaled = [Float](repeating: 0, count: halfN)
        vDSP_vsmul(&sqrtMagnitudes, 1, [scale], &scaled, 1, vDSP_Length(halfN))

        return scaled
    }

    private func bandEnergy(magnitudes: [Float], range: ClosedRange<Float>) -> Float {
        let binResolution = sampleRate / Float(fftSize)
        let startBin = max(0, Int(range.lowerBound / binResolution))
        let endBin = min(magnitudes.count - 1, Int(range.upperBound / binResolution))

        guard startBin < endBin else { return 0 }

        let slice = Array(magnitudes[startBin...endBin])
        var sumOfSquares: Float = 0
        vDSP_svesq(slice, 1, &sumOfSquares, vDSP_Length(slice.count))
        let rms = sqrt(sumOfSquares / Float(slice.count))

        return min(rms * 10.0, 1.0)
    }

    private func lerp(_ a: Float, _ b: Float, t: Float) -> Float {
        a + (b - a) * t
    }
}
