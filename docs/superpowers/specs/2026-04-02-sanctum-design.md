# Sanctum — Design Specification

**Date:** 2026-04-02
**Status:** Approved

## Overview

Sanctum is a macOS application that drives a nightclub video wall with audio-reactive stained glass visuals. It captures audio from a DJ mixer line-in, performs real-time spectral analysis, and renders gothic/medieval stained glass imagery that corrupts and distorts as the music's energy builds over the course of an evening.

**Key constraint:** The visuals must look sharp and professional — hand-crafted, not algorithmically generated.

## Target Environment

- **Hardware:** Mac Studio (Apple Silicon)
- **Displays:** 4x 65" TVs in a 2x2 grid
- **Total canvas:** 3840x2160 (each TV receives a 1920x1080 quadrant)
- **Frame rate:** 60fps
- **Audio input:** Stereo line-in from DJ mixer (44.1kHz or 48kHz)
- **Connectivity:** Always connected (internet available)

## Technology

- **Language:** Swift
- **Graphics:** Metal
- **Audio:** Core Audio + Accelerate framework (vDSP)
- **Platform:** macOS only

## Architecture

Monolithic application with 5 internal modules sharing a single Metal render loop.

```
┌─────────────────────────────────────────────────┐
│                   Sanctum App                    │
│                                                  │
│  ┌──────────┐    ┌──────────────┐               │
│  │ Audio    │───▶│ Analysis     │               │
│  │ Capture  │    │ Engine       │               │
│  │(CoreAudio)│   │(FFT, Beat,  │               │
│  └──────────┘    │ Energy)      │               │
│                  └──────┬───────┘               │
│                         │ AudioState            │
│                         ▼                       │
│  ┌──────────┐    ┌──────────────┐               │
│  │ Asset    │───▶│ Composition  │               │
│  │ Library  │    │ Engine       │               │
│  │(PNG/EXR) │    │(Scene Graph) │               │
│  └──────────┘    └──────┬───────┘               │
│                         │                       │
│                         ▼                       │
│  ┌──────────┐    ┌──────────────┐    ┌────────┐│
│  │Corruption│───▶│ Shader       │───▶│Display ││
│  │ Engine   │    │ Pipeline     │    │Manager ││
│  │(0→1 arc) │    │(Metal)       │    │(2x2)   ││
│  └──────────┘    └──────────────┘    └────────┘│
└─────────────────────────────────────────────────┘
```

### Module Responsibilities

1. **AudioCapture** — Core Audio line-in capture with ring buffer. Feeds raw PCM samples to AnalysisEngine.

2. **AnalysisEngine** — Accelerate framework vDSP for FFT. 4096-sample window, 75% overlap. Outputs an `AudioState` struct every frame containing:
   - 4 frequency band energies (sub-bass 20-80Hz, bass 80-250Hz, mids 250Hz-4kHz, highs 4kHz-20kHz)
   - BPM and beat phase (0-1 sawtooth synced to beat)
   - Beat event flag (kick transient detection)
   - Transient event flag (major energy spikes — drops, breakdowns)
   - Corruption index (0-1, cumulative energy integral over configurable window)
   - Raw FFT spectrum for direct shader use

3. **CompositionEngine** — Scene graph managing stained glass panels and icons. Selects, layers, and transitions assets based on audio state. Divides canvas into zones (center = dramatic, edges = atmospheric).

4. **ShaderPipeline** — Metal render pipeline in 3 passes:
   - **Pass 1 (Compute):** Composite active panels and icons into single texture
   - **Pass 2 (Fragment):** Audio-reactive effects (refraction, lead lines, candlelight, chromatic aberration, crack propagation, icon distortion, color grading, geometry folding)
   - **Pass 3 (Compute):** Post-processing (bloom, film grain, vignette, motion blur)

5. **DisplayManager** — Enumerates connected displays, renders to single offscreen Metal texture at 3840x2160, blits 1920x1080 quadrants to each TV. Grid mapping stored in JSON config. V-sync via CVDisplayLink.

## Audio Analysis Pipeline

**Processing chain per frame (~16ms budget, targeting <2ms):**

1. Ring buffer captures 4096 samples with 75% overlap
2. FFT via Accelerate vDSP produces magnitude spectrum
3. Spectrum decomposed into 4 bands:
   - **Sub-bass (20-80Hz)** → drives large structural movements, glass panel breathing
   - **Bass (80-250Hz)** → kick detection, pulses light through glass
   - **Mids (250Hz-4kHz)** → color shifts, texture changes
   - **Highs (4kHz-20kHz)** → fine detail sparkle, lead line shimmer
4. Beat detector via onset detection + autocorrelation for BPM
5. Transient detector catches sudden energy spikes
6. Cumulative energy tracker maintains the corruption index (0→1 over 4-6 hour window)

```swift
struct AudioState {
    let bands: [Float]        // 4 band energies, 0-1 normalized
    let bpm: Float
    let beatPhase: Float      // 0-1 sawtooth synced to beat
    let isBeat: Bool          // true on kick transient
    let isTransient: Bool     // true on major energy spike
    let corruptionIndex: Float // 0-1, cumulative energy arc
    let rawSpectrum: [Float]  // full FFT for shader use
}
```

## Visual Design

### Hybrid Rendering Approach

- **Pre-rendered assets** provide the professional, hand-crafted look: stained glass panels, religious icons, textures — created using AI art tools with heavy human curation
- **Real-time Metal shaders** handle animation, audio reactivity, and corruption effects
- The base art sells quality; the shaders sell motion and life

### Asset Library

- **Panels (~20-30):** Rose windows, geometric tracery, cathedral arches, lancet windows. 4K resolution each.
- **Icons (~40-50):** Saints, angels, crosses, chalices, doves, halos, praying hands. Transparent PNGs for compositing.
- **Textures:** Glass grain, lead came, surface imperfections, dust, patina. Tiling.
- **Format:** PNG for color, EXR for HDR. Pre-loaded into Metal textures at startup.

### The Corruption Arc

The corruption index (0→1) is driven by cumulative audio energy. As the night's music builds in intensity, the visuals degrade from sacred to profane.

| Corruption | Phase | Visual Character |
|---|---|---|
| 0.0 – 0.2 | **Sacred** | Pristine cathedral glass. Warm candlelight. Saints gaze serenely. Gentle breathing to sub-bass. Colors: deep blues, ruby reds, gold leaf. |
| 0.2 – 0.4 | **Awakening** | Glass pulses more aggressively. Colors saturate. Lead lines thicken. Icons' eyes shift. Faint chromatic aberration. |
| 0.4 – 0.6 | **Fracture** | Cracks propagate on beat hits. Glass fragments float. Icons distort — faces stretch, halos tilt. Colors push toward unnatural greens, magentas. |
| 0.6 – 0.8 | **Profane** | Panels shatter and reassemble wrong. Icons invert — upside down crosses, melting faces, skeletal hands. Heavy chromatic aberration. Deep purples, sickly yellows, blood reds. |
| 0.8 – 1.0 | **Abyss** | Full visual chaos. Geometry folds on itself. Icons are abstract corrupted forms. Extreme distortion on all bands. Moments of sudden clarity on breakdowns before plunging back. Black and neon. |

### Composition Rules

- Canvas divided into zones — center panels get most dramatic effects, edges get atmospheric fill
- Panels crossfade on detected musical transitions (energy shifts, not random timers)
- Icons drift across grid, corruption state matching global index
- Each beat pulse sends light ripple outward from center

## Shader Effects Detail

### Pass 2 Effects (Fragment Shaders)

| Effect | Audio Driver | Corruption Behavior |
|---|---|---|
| Glass refraction | Sub-bass | Subtle distortion → extreme warping |
| Lead line rendering | Static + bass | Clean lines → thicken, crack, bleed |
| Candlelight / Backlighting | Beat phase | Warm flicker → strobe, unnatural hues |
| Chromatic aberration | Mids + corruption | None → RGB split → prismatic separation |
| Crack propagation | Beat transients | None → hairlines → full shatter on hits |
| Icon distortion | Corruption index | None → stretch → melt → invert → abstract |
| Color grading | Corruption + highs | Warm cathedral → oversaturated → toxic/neon |
| Geometry folding | Full spectrum | None → subtle warp → Escher-like recursion |

### Pass 3 Post-Processing

- **Bloom:** Light bleeding through glass, intensity scales with bass
- **Film grain:** Subtle, prevents "too clean" digital look
- **Vignette:** Darkens edges, focuses center
- **Motion blur:** Light, smooths corruption state transitions

### Performance Budget

| Pass | Target |
|---|---|
| Composition (compute) | ~3ms |
| Effects (fragment) | ~8ms |
| Post-processing (compute) | ~3ms |
| Overhead + blit | ~2ms |
| **Total** | **~16ms (60fps)** |

All shader parameters smoothly interpolated (lerp toward targets). Beat events trigger immediate spikes decaying over ~200ms.

## Display Management

- 4 displays, 2x2 grid, each 1920x1080
- Total canvas: 3840x2160
- Single offscreen Metal texture → blit quadrants to each display
- Display enumeration via `CGGetActiveDisplayList`
- One-time setup screen for grid mapping, saved to JSON config
- Each display gets fullscreen `NSWindow` with `CAMetalLayer`
- V-sync via `CVDisplayLink`

**Fallback modes:**
- Single display for development (full canvas scaled to fit)
- Grid config is JSON — no recompile to change layout

## Development Workflow

- Single-display mode by default during development
- Audio file input (WAV/AIFF) for deterministic testing
- Debug overlay: FPS, audio band visualizer, corruption index, beat indicator
- Metal shader hot-reload during development

## Testing Strategy

- **Unit tests:** Audio analysis with known signals (verify band outputs, beat detection)
- **Unit tests:** Corruption engine phase transitions at expected thresholds
- **Snapshot tests:** Shader output for known scene + audio state vs reference images
- **Manual QA:** Test tracks spanning genres and energy levels

## Deployment

- Standard macOS app bundle
- Config file for display grid, audio input device, corruption timing
- Launch on boot via macOS login items

## Project Structure

```
sanctum/
├── Sanctum/                    # Xcode project
│   ├── App/                    # Entry point, config, setup UI
│   ├── Audio/                  # AudioCapture, AnalysisEngine
│   ├── Composition/            # Scene graph, asset management
│   ├── Shaders/                # .metal files
│   ├── Corruption/             # Corruption engine, phase logic
│   ├── Display/                # Display manager, grid config
│   └── Resources/Assets/       # Pre-rendered stained glass art
├── Assets/                     # Source art (high-res, not bundled)
├── docs/                       # Design docs, specs
├── .claude/                    # Claude Code config
│   └── CLAUDE.md
└── README.md
```
