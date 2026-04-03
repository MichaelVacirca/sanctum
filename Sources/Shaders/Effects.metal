#include <metal_stdlib>
#include "ShaderTypes.h"
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// --- Utility functions ---

float2 distort(float2 uv, float amount, float time) {
    float2 offset = float2(
        sin(uv.y * 20.0 + time * 2.0) * amount,
        cos(uv.x * 20.0 + time * 1.5) * amount
    );
    return uv + offset;
}

float crackPattern(float2 uv, float time, float intensity) {
    float2 p = uv * 8.0;
    float2 i_p = floor(p);
    float2 f_p = fract(p);

    float minDist = 1.0;
    float secondDist = 1.0;

    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 neighbor = float2(x, y);
            float2 cellPos = fract(sin(dot(i_p + neighbor, float2(127.1, 311.7))) * 43758.5453);
            cellPos = 0.5 + 0.5 * sin(time * 0.5 + 6.2831 * cellPos);
            float2 diff = neighbor + cellPos - f_p;
            float d = length(diff);
            if (d < minDist) {
                secondDist = minDist;
                minDist = d;
            } else if (d < secondDist) {
                secondDist = d;
            }
        }
    }

    float edge = secondDist - minDist;
    return smoothstep(0.0, 0.05 * intensity, edge);
}

// --- Main effects fragment shader ---

fragment float4 effectsFragment(
    VertexOut in [[stage_in]],
    texture2d<float> compositionTex [[texture(0)]],
    constant AudioUniforms &audio [[buffer(0)]]
) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 uv = in.texCoord;
    float corruption = audio.corruptionIndex;
    float time = audio.time;

    // --- Glass Refraction (driven by sub-bass) ---
    float refractionAmount = audio.bands[0] * corruption * 0.03;
    float2 refractedUV = distort(uv, refractionAmount, time);

    // --- Chromatic Aberration (driven by mids + corruption) ---
    float aberration = audio.bands[2] * corruption * 0.008;
    float4 colorR = compositionTex.sample(s, refractedUV + float2(aberration, 0));
    float4 colorG = compositionTex.sample(s, refractedUV);
    float4 colorB = compositionTex.sample(s, refractedUV - float2(aberration, 0));
    float4 color = float4(colorR.r, colorG.g, colorB.b, 1.0);

    // --- Lead Line Darkening (driven by bass) ---
    float leadIntensity = 1.0 + corruption * 0.5;
    float cracks = crackPattern(uv, time, leadIntensity);
    float leadDarken = mix(1.0, cracks, 0.3 + corruption * 0.4);
    color.rgb *= leadDarken;

    // --- Candlelight / Backlighting (driven by beat phase) ---
    float lightIntensity = mix(
        0.8 + 0.2 * sin(audio.beatPhase * 3.14159 * 2.0),
        0.5 + 0.5 * step(0.5, fract(audio.beatPhase * 2.0)),
        corruption
    );
    float beatFlash = audio.isBeat * (1.0 - corruption * 0.5) * 0.3;
    lightIntensity += beatFlash;
    color.rgb *= lightIntensity;

    // --- Color Grading (driven by corruption + highs) ---
    float3 sacredTint = float3(1.0, 0.9, 0.7);
    float3 profaneTint = float3(0.7, 1.1, 0.9);
    float3 abyssTint = float3(1.2, 0.6, 1.3);
    float3 tint;
    if (corruption < 0.6) {
        tint = mix(sacredTint, profaneTint, corruption / 0.6);
    } else {
        tint = mix(profaneTint, abyssTint, (corruption - 0.6) / 0.4);
    }
    tint += audio.bands[3] * 0.1;
    color.rgb *= tint;

    // --- Icon Distortion (driven by corruption index) ---
    if (corruption > 0.4) {
        float warpStrength = (corruption - 0.4) * 0.05;
        float2 warpedUV = uv;
        warpedUV.x += sin(uv.y * 30.0 + time) * warpStrength;
        warpedUV.y += cos(uv.x * 25.0 + time * 0.8) * warpStrength;
        float4 warpedColor = compositionTex.sample(s, warpedUV);
        color = mix(color, warpedColor, (corruption - 0.4) / 0.6);
    }

    // --- Geometry Folding (full spectrum, high corruption) ---
    if (corruption > 0.7) {
        float foldStrength = (corruption - 0.7) / 0.3;
        float energy = (audio.bands[0] + audio.bands[1] + audio.bands[2] + audio.bands[3]) * 0.25;
        float2 foldedUV = uv;
        if (foldStrength > 0.5) {
            foldedUV = abs(foldedUV * 2.0 - 1.0);
        }
        foldedUV += float2(sin(time * 1.5), cos(time * 1.2)) * foldStrength * energy * 0.1;
        float4 foldedColor = compositionTex.sample(s, foldedUV);
        color = mix(color, foldedColor, foldStrength * 0.5);
    }

    // --- Transient flash (drops/breakdowns) ---
    if (audio.isTransient > 0.5) {
        color.rgb = mix(color.rgb, float3(1.0), 0.4);
    }

    // --- Saturation push with corruption ---
    float3 gray = float3(dot(color.rgb, float3(0.299, 0.587, 0.114)));
    float saturation = 1.0 + corruption * 0.8;
    color.rgb = mix(gray, color.rgb, saturation);

    return color;
}
