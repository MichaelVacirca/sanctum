# Sanctum

Audio-reactive stained glass visuals for nightclub video walls.

## Tech Stack
- **Language:** Swift
- **Graphics:** Metal (Apple GPU framework)
- **Audio:** Core Audio + Accelerate (vDSP for FFT)
- **Platform:** macOS (Mac Studio target)
- **IDE:** Xcode

## Architecture
Monolithic Swift/Metal app with 5 internal modules:
1. **AudioCapture** — Core Audio line-in, ring buffer
2. **AnalysisEngine** — FFT, beat detection, band decomposition, corruption index
3. **CompositionEngine** — Scene graph, asset management, panel/icon layering
4. **ShaderPipeline** — Metal render pipeline (composition, effects, post-processing)
5. **DisplayManager** — 2x2 display grid (4x 65" TVs), 3840x2160 total canvas

## Project Structure
```
Sanctum/                    # Xcode project
├── App/                    # App entry, config, setup UI
├── Audio/                  # AudioCapture, AnalysisEngine
├── Composition/            # Scene graph, asset management
├── Shaders/                # .metal shader files
├── Corruption/             # Corruption engine, phase logic
├── Display/                # Display manager, grid config
└── Resources/Assets/       # Pre-rendered stained glass art
```

## Conventions
- Swift code follows standard Swift API Design Guidelines
- Metal shaders use `.metal` extension, one file per effect where practical
- Shader parameters are always smoothly interpolated (lerp) — no hard pops
- Audio analysis targets <2ms per frame
- Total render budget: 16ms (60fps)
- All audio-reactive values normalized to 0-1 range

## Key Design Decisions
- Pre-rendered art assets + real-time shaders (hybrid approach) for professional look
- Corruption arc driven by cumulative audio energy, not timers
- Single offscreen render target, blit quadrants to each display
- Debug overlay available in development (FPS, audio bands, corruption index)

## Testing
- Unit tests for audio analysis with known signals
- Unit tests for corruption phase transitions
- Snapshot tests for shader output
- Test with audio file input for deterministic results
