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
    float corruptionIndex; // 0-1
    float time;
    float isBeat;         // 1.0 on beat frame, else 0.0
    float isTransient;    // 1.0 on transient frame, else 0.0
    float padding[2];     // align to 16 bytes
};

struct CompositionUniforms {
    simd_float2 canvasSize;
    uint32_t panelCount;
    uint32_t iconCount;
};

#endif
