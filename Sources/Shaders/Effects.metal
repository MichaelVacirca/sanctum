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
        sin(uv.y * 15.0 + time * 3.0) * amount,
        cos(uv.x * 15.0 + time * 2.0) * amount
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
    float bass = audio.bands[0];
    float mids = audio.bands[2];
    float highs = audio.bands[3];

    // --- Glass Refraction (driven by sub-bass) — CRANKED UP ---
    float refractionAmount = bass * 0.015 + bass * corruption * 0.04;
    float2 refractedUV = distort(uv, refractionAmount, time);

    // --- Chromatic Aberration (always present, stronger with corruption) ---
    float aberration = 0.002 + mids * 0.006 + corruption * 0.012;
    float4 colorR = compositionTex.sample(s, refractedUV + float2(aberration, aberration * 0.5));
    float4 colorG = compositionTex.sample(s, refractedUV);
    float4 colorB = compositionTex.sample(s, refractedUV - float2(aberration, -aberration * 0.3));
    float4 color = float4(colorR.r, colorG.g, colorB.b, 1.0);

    // --- Lead Line Darkening (driven by bass) ---
    float leadIntensity = 1.0 + corruption * 0.8;
    float cracks = crackPattern(uv, time, leadIntensity);
    float leadDarken = mix(1.0, cracks, 0.2 + corruption * 0.5);
    color.rgb *= leadDarken;

    // --- Candlelight / Backlighting (driven by beat phase) — MORE DRAMATIC ---
    float pulse = sin(audio.beatPhase * 3.14159 * 2.0);
    float lightIntensity = mix(
        0.7 + 0.3 * pulse,
        0.3 + 0.7 * step(0.5, fract(audio.beatPhase * 2.0)),
        corruption
    );
    // Strong beat flash
    float beatFlash = audio.isBeat * (1.0 - corruption * 0.3) * 0.6;
    lightIntensity += beatFlash;
    // Bass throb — the whole image breathes with the bass
    lightIntensity += bass * 0.25;
    color.rgb *= lightIntensity;

    // --- Color Grading (more vivid phase shifts) ---
    float3 sacredTint = float3(0.9, 0.85, 1.1);    // cool sacred blue push
    float3 awakeningTint = float3(1.1, 0.95, 0.7);  // warm golden
    float3 fractureTint = float3(1.2, 0.6, 0.5);    // aggressive red
    float3 profaneTint = float3(0.5, 1.1, 0.8);     // sickly green
    float3 abyssTint = float3(1.3, 0.4, 1.4);       // toxic purple

    float3 tint;
    if (corruption < 0.2) {
        tint = mix(sacredTint, awakeningTint, corruption / 0.2);
    } else if (corruption < 0.4) {
        tint = mix(awakeningTint, fractureTint, (corruption - 0.2) / 0.2);
    } else if (corruption < 0.6) {
        tint = mix(fractureTint, profaneTint, (corruption - 0.4) / 0.2);
    } else if (corruption < 0.8) {
        tint = mix(profaneTint, abyssTint, (corruption - 0.6) / 0.2);
    } else {
        tint = abyssTint;
    }
    tint += highs * 0.15;
    color.rgb *= tint;

    // --- Warp distortion (grows with corruption) ---
    if (corruption > 0.3) {
        float warpStrength = (corruption - 0.3) * 0.08;
        float2 warpedUV = uv;
        warpedUV.x += sin(uv.y * 20.0 + time * 2.0) * warpStrength * bass;
        warpedUV.y += cos(uv.x * 18.0 + time * 1.5) * warpStrength * bass;
        float4 warpedColor = compositionTex.sample(s, warpedUV);
        color = mix(color, warpedColor, (corruption - 0.3) * 0.7);
    }

    // --- Geometry Folding (full spectrum, high corruption) ---
    if (corruption > 0.65) {
        float foldStrength = (corruption - 0.65) / 0.35;
        float energy = (bass + audio.bands[1] + mids + highs) * 0.25;
        float2 foldedUV = uv;
        if (foldStrength > 0.4) {
            foldedUV = abs(foldedUV * 2.0 - 1.0);
        }
        foldedUV += float2(sin(time * 2.0), cos(time * 1.5)) * foldStrength * energy * 0.15;
        float4 foldedColor = compositionTex.sample(s, foldedUV);
        color = mix(color, foldedColor, foldStrength * 0.6);
    }

    // --- Transient flash (drops/breakdowns) — BIGGER ---
    if (audio.isTransient > 0.5) {
        color.rgb = mix(color.rgb, float3(1.2, 1.1, 1.3), 0.6);
    }

    // --- Saturation push with corruption ---
    float3 gray = float3(dot(color.rgb, float3(0.299, 0.587, 0.114)));
    float saturation = 1.2 + corruption * 1.0;
    color.rgb = mix(gray, color.rgb, saturation);

    // --- Overall brightness boost so it pops on video walls ---
    color.rgb *= 1.15;

    return color;
}
