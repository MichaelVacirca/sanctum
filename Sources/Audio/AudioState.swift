import Foundation

struct AudioState {
    var bands: (Float, Float, Float, Float) = (0, 0, 0, 0) // sub-bass, bass, mids, highs
    var bpm: Float = 120
    var beatPhase: Float = 0    // 0-1 sawtooth synced to beat
    var isBeat: Bool = false
    var isTransient: Bool = false
    var corruptionIndex: Float = 0 // 0-1 cumulative energy arc
    var rawSpectrum: [Float] = []

    static let silent = AudioState()

    var subBass: Float { bands.0 }
    var bass: Float { bands.1 }
    var mids: Float { bands.2 }
    var highs: Float { bands.3 }
    var overallEnergy: Float { (bands.0 + bands.1 + bands.2 + bands.3) / 4.0 }
}
