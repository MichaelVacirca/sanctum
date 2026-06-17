import Foundation
import simd

/// A complete visual identity for Sanctum.
///
/// The energy arc (`AudioState.corruptionIndex`, 0→1, driven by cumulative
/// audio energy over the night) is theme-agnostic — it is really just a
/// normalized "how hard is the room going" signal. A `Theme` decides what
/// that build *looks and feels* like:
///
/// - **`.cathedral`** — the original gothic arc: pristine stained glass that
///   corrupts from *sacred* to *profane/abyss* as energy climbs. Cracks,
///   melting, Escher folding, toxic neon. Edgy and dark.
/// - **`.beach`** — a feel-good resort night: *sunset → golden hour →
///   tropical dusk → neon night → midnight peak*. The same build adds
///   vibrance, glow, shimmer and color instead of decay. Fun, not horror.
///
/// Everything that defines a look lives here (per-phase palette, panel art,
/// icon set, and how strongly the audio-reactive effects distort vs. glow),
/// so adding a theme for the next themed party is a data-only change.
///
/// Note: this type intentionally imports only Foundation + simd (no Metal),
/// so the arc/palette logic stays unit-testable without a GPU.
struct Theme: Sendable {

    /// One stage of the five-stage energy arc.
    struct Phase: Sendable {
        /// Display label shown in the debug overlay (e.g. "SUNSET").
        let name: String
        /// RGB multiplier applied as a color grade in the effects pass.
        let tint: SIMD3<Float>
    }

    /// How the audio-reactive effects behave for this theme. Cathedral leans
    /// into degradation; beach dials the destructive effects toward zero and
    /// leans into shimmer/glow. Cathedral's values reproduce the original
    /// hand-tuned shader constants exactly (see `Effects.metal`).
    struct EffectProfile: Sendable {
        /// Sub-bass glass refraction / heat-haze warp. 1.0 = original.
        var refraction: Float
        /// Chromatic aberration (RGB split). 1.0 = original.
        var aberration: Float
        /// Dynamic lead-line cracking that darkens with energy. 0 = none.
        var crack: Float
        /// Large-scale UV warp at high energy. 0 = none.
        var warp: Float
        /// Escher-style geometry folding at peak energy. 0 = none.
        var fold: Float
        /// Sun-glint / water-caustic sparkle on highs. 0 = none (cathedral).
        var shimmer: Float
        /// Extra saturation ramp with energy. 1.0 = original.
        var saturation: Float
        /// Final overall brightness multiplier (pops on the video wall).
        var brightness: Float
        /// Per-channel multiplier reached at full energy, lerped from white.
        /// Cathedral drains toward black; beach stays bright and warm.
        var energyTint: SIMD3<Float>
    }

    let id: String
    let displayName: String
    /// Exactly five phases, in ascending energy order.
    let phases: [Phase]
    /// Panel asset names, crossfaded in order as energy builds.
    let panelOrder: [String]
    /// Icon asset names that drift across the canvas.
    let icons: [String]
    let effects: EffectProfile
    /// Canvas clear color (shows only at edges / before art loads).
    let clearColor: SIMD3<Float>

    // MARK: - Arc sampling

    /// Index of the active phase for an energy value in 0...1.
    /// Matches `CorruptionPhase`'s 0.2-wide thresholds for a 5-phase theme.
    func phaseIndex(at index: Float) -> Int {
        guard !phases.isEmpty else { return 0 }
        let clamped = max(0, min(1, index))
        return min(phases.count - 1, Int(clamped * Float(phases.count)))
    }

    /// Display name of the active phase (for the debug overlay).
    func phaseName(at index: Float) -> String {
        guard !phases.isEmpty else { return "" }
        return phases[phaseIndex(at: index)].name
    }

    /// Smoothly interpolated color grade for an energy value in 0...1.
    /// Keypoints are evenly spaced (0, 0.2, 0.4, 0.6, 0.8 for five phases) and
    /// the final phase is held to 1.0 — the same curve the shader used to bake
    /// in for the gothic palette, now driven by theme data.
    func interpolatedTint(at index: Float) -> SIMD3<Float> {
        guard !phases.isEmpty else { return SIMD3(repeating: 1) }
        let n = phases.count
        let clamped = max(0, min(1, index))
        let scaled = clamped * Float(n)
        let i = min(n - 1, Int(scaled))
        let next = min(n - 1, i + 1)
        let f = min(1, scaled - Float(i))
        let a = phases[i].tint
        let b = phases[next].tint
        return a + (b - a) * f
    }

    /// Composite-pass tint: lerps from white (low energy) toward the profile's
    /// `energyTint` (full energy).
    func energyTint(at index: Float) -> SIMD3<Float> {
        let white = SIMD3<Float>(repeating: 1)
        let clamped = max(0, min(1, index))
        return white + (effects.energyTint - white) * clamped
    }

    // MARK: - Lookup

    static let all: [Theme] = [.cathedral, .beach]

    /// Resolve a theme by id, falling back to `.cathedral` for unknown ids.
    static func named(_ id: String) -> Theme {
        all.first { $0.id.caseInsensitiveCompare(id) == .orderedSame } ?? .cathedral
    }
}

// MARK: - Built-in themes

extension Theme {
    /// The original gothic stained-glass corruption arc. These values
    /// reproduce the previously hard-coded look exactly.
    static let cathedral = Theme(
        id: "cathedral",
        displayName: "Cathedral",
        phases: [
            Phase(name: "SACRED",    tint: SIMD3(0.9, 0.85, 1.1)),
            Phase(name: "AWAKENING", tint: SIMD3(1.1, 0.95, 0.7)),
            Phase(name: "FRACTURE",  tint: SIMD3(1.2, 0.6, 0.5)),
            Phase(name: "PROFANE",   tint: SIMD3(0.5, 1.1, 0.8)),
            Phase(name: "ABYSS",     tint: SIMD3(1.3, 0.4, 1.4)),
        ],
        panelOrder: [
            "panel-sacred-blue",
            "panel-golden-amber",
            "panel-ruby-red",
            "panel-emerald-purple",
            "panel-corrupted",
            "panel-fire",
        ],
        icons: [
            "icon-cross", "icon-rose", "icon-chalice",
            "icon-skull", "icon-dove", "icon-halo",
        ],
        effects: EffectProfile(
            refraction: 1.0,
            aberration: 1.0,
            crack: 1.0,
            warp: 1.0,
            fold: 1.0,
            shimmer: 0.0,
            saturation: 1.0,
            brightness: 1.15,
            energyTint: SIMD3(0.8, 0.7, 0.95)
        ),
        clearColor: SIMD3(0, 0, 0)
    )

    /// Beach / resort night: a feel-good build from a warm sunset to an
    /// electric midnight peak. Destructive effects are off; shimmer and glow
    /// are on. Stays bright and vivid all night — pure good-time energy.
    static let beach = Theme(
        id: "beach",
        displayName: "Beach Resort",
        phases: [
            Phase(name: "SUNSET",        tint: SIMD3(1.30, 1.00, 0.70)),
            Phase(name: "GOLDEN HOUR",   tint: SIMD3(1.25, 1.02, 0.85)),
            Phase(name: "TROPICAL DUSK", tint: SIMD3(1.05, 1.05, 1.20)),
            Phase(name: "NEON NIGHT",    tint: SIMD3(1.20, 0.85, 1.30)),
            Phase(name: "MIDNIGHT",      tint: SIMD3(1.10, 0.95, 1.45)),
        ],
        panelOrder: [
            "panel-beach-sunset",
            "panel-beach-goldenhour",
            "panel-beach-dusk",
            "panel-beach-neonnight",
            "panel-beach-midnight",
        ],
        icons: [
            "icon-beach-sun", "icon-beach-palm", "icon-beach-wave",
            "icon-beach-cocktail", "icon-beach-flamingo", "icon-beach-shell",
            "icon-beach-starfish", "icon-beach-pineapple",
        ],
        effects: EffectProfile(
            refraction: 0.5,   // gentle heat-haze / water shimmer, not warping
            aberration: 0.35,  // subtle, not prismatic
            crack: 0.0,        // no cracking — the glass stays whole
            warp: 0.3,         // soft "looking through water" wobble
            fold: 0.0,         // no Escher horror
            shimmer: 1.0,      // sun-glint + water caustics — the beachy magic
            saturation: 0.7,   // vivid but not toxic
            brightness: 1.25,  // bright, poppy, resort
            energyTint: SIMD3(1.05, 1.00, 0.95) // stays bright + warm, never dark
        ),
        clearColor: SIMD3(0.02, 0.04, 0.10) // deep tropical night blue
    )
}
