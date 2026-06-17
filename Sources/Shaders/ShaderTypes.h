#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

struct Vertex {
    simd_float2 position;
    simd_float2 texCoord;
};

struct AudioUniforms {
    float bands[4];       // sub-bass, bass, mids, highs (0-1)
    float bpm;
    float beatPhase;      // 0-1 sawtooth
    float corruptionIndex; // 0-1 energy arc (theme-agnostic build signal)
    float time;
    float isBeat;         // 1.0 on beat frame, else 0.0
    float isTransient;    // 1.0 on transient frame, else 0.0

    // --- Theme-driven look (filled from the active Theme each frame) ---
    float phaseTint[3];   // interpolated per-phase color grade
    float refraction;     // effect profile: sub-bass refraction strength
    float aberration;     // effect profile: chromatic aberration strength
    float crack;          // effect profile: dynamic lead-line cracking (0=off)
    float warp;           // effect profile: large-scale UV warp (0=off)
    float fold;           // effect profile: geometry folding at peak (0=off)
    float shimmer;        // effect profile: sun-glint / caustic sparkle (0=off)
    float saturation;     // effect profile: saturation ramp with energy
    float brightness;     // effect profile: final brightness multiplier
    float padding[3];     // align to 16 bytes (96 total)
};

struct CompositionUniforms {
    simd_float2 canvasSize;
    uint32_t panelCount;
    uint32_t iconCount;
};

#endif
