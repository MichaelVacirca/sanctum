import Foundation

enum CorruptionPhase: String, CaseIterable {
    case sacred
    case awakening
    case fracture
    case profane
    case abyss

    static func from(index: Float) -> CorruptionPhase {
        switch index {
        case ..<0.2: return .sacred
        case ..<0.4: return .awakening
        case ..<0.6: return .fracture
        case ..<0.8: return .profane
        default: return .abyss
        }
    }

    static func localProgress(at index: Float) -> Float {
        let clamped = max(0, min(1, index))
        let phaseStart = (clamped / 0.2).rounded(.down) * 0.2
        return (clamped - phaseStart) / 0.2
    }

    var range: ClosedRange<Float> {
        switch self {
        case .sacred: return 0...0.2
        case .awakening: return 0.2...0.4
        case .fracture: return 0.4...0.6
        case .profane: return 0.6...0.8
        case .abyss: return 0.8...1.0
        }
    }
}
