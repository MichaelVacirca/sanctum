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

// Cheap hash for sparkle placement.
float seaHash(float2 p) {
    float h = dot(p, float2(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

// --- Main effects fragment shader ---

fragment float4 effectsFragment(
    VertexOut in [[stage_in]],
    texture2d<float> compositionTex [[texture(0)]],
    constant AudioUniforms &audio [[buffer(0)]]
) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 uv = in.texCoord;
    float corruption = audio.corruptionIndex; // theme-agnostic energy build
    float time = audio.time;
    float bass = audio.bands[0];
    float mids = audio.bands[2];
    float highs = audio.bands[3];

    // Theme effect profile (see Theme.EffectProfile). Cathedral passes 1.0 for
    // the cranked effects and 0.0 for shimmer, reproducing the original look;
    // beach dials cracking/folding to 0 and shimmer up.
    float pRefraction = audio.refraction;
    float pAberration = audio.aberration;
    float pCrack      = audio.crack;
    float pWarp       = audio.warp;
    float pFold       = audio.fold;
    float pShimmer    = audio.shimmer;
    float pSaturation = audio.saturation;
    float pBrightness = audio.brightness;
    float3 phaseTint  = float3(audio.phaseTint[0], audio.phaseTint[1], audio.phaseTint[2]);

    // --- Glass Refraction (driven by sub-bass) ---
    float refractionAmount = (bass * 0.015 + bass * corruption * 0.04) * pRefraction;
    float2 refractedUV = distort(uv, refractionAmount, time);

    // --- Chromatic Aberration (always present, stronger with energy) ---
    float aberration = (0.002 + mids * 0.006 + corruption * 0.012) * pAberration;
    float4 colorR = compositionTex.sample(s, refractedUV + float2(aberration, aberration * 0.5));
    float4 colorG = compositionTex.sample(s, refractedUV);
    float4 colorB = compositionTex.sample(s, refractedUV - float2(aberration, -aberration * 0.3));
    float4 color = float4(colorR.r, colorG.g, colorB.b, 1.0);

    // --- Lead Line / Crack Darkening (gated by profile.crack) ---
    float leadIntensity = 1.0 + corruption * 0.8;
    float cracks = crackPattern(uv, time, leadIntensity);
    float leadDarken = mix(1.0, cracks, (0.2 + corruption * 0.5) * pCrack);
    color.rgb *= leadDarken;

    // --- Candlelight / Backlighting (driven by beat phase) ---
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

    // --- Color Grading (theme phase tint + highs sparkle) ---
    float3 tint = phaseTint + highs * 0.15;
    color.rgb *= tint;

    // --- Beach water, caustics, sparkle & god rays (gated; cathedral=0) ---
    // Everything here is additive light scaled by the theme's shimmer knob, so
    // the cathedral theme (shimmer == 0) skips it entirely and is unchanged.
    if (pShimmer > 0.001) {
        float energy = corruption;
        // Sea fills the lower frame, sky the upper — soft masks, no hard line.
        float sea = smoothstep(0.46, 0.64, uv.y);
        float sky = smoothstep(0.62, 0.12, uv.y);

        // Calm = warm gold; peak = cycling cyan/magenta neon (the midnight rave).
        float3 warmGlow = float3(1.0, 0.92, 0.70);
        float3 neon = mix(float3(0.35, 1.0, 1.0), float3(1.0, 0.35, 0.95),
                          0.5 + 0.5 * sin(time * 1.6));
        float3 glow = mix(warmGlow, neon, smoothstep(0.5, 0.85, energy));

        // Undulating coordinates so the light network rolls like gentle surf,
        // breathing harder with the bass.
        float2 wuv = uv;
        wuv.x += sin(uv.y * 22.0 - time * 1.6) * (0.01 + bass * 0.02);
        wuv.y += sin(uv.x * 16.0 - time * 2.2) * 0.008;

        // Caustics: two crossing wave fields make bright veins of light.
        float c1 = sin(wuv.x * 38.0 + time * 1.5 + sin(wuv.y * 28.0 - time));
        float c2 = cos(wuv.y * 34.0 - time * 1.2 + cos(wuv.x * 20.0 + time));
        float caustic = pow(max(0.0, c1 * c2), 2.0);
        float causticAmt = caustic * (0.12 + highs * 0.45 + bass * 0.30) * sea;

        // Sparkle: pinpoint glints on the water that pop on the kick.
        float2 cell = floor(uv * float2(130.0, 80.0));
        float twinkle = seaHash(cell + floor(time * 7.0));
        float sparkle = step(0.978 - audio.isBeat * 0.03, twinkle)
                      * (0.6 + highs) * sea;

        color.rgb += (causticAmt + sparkle) * pShimmer * glow;

        // God rays / light shafts fanning from just above the horizon, in the
        // sky, pulsing with the bass and flaring on the beat.
        float2 toLight = uv - float2(0.5, -0.08);
        float ang = atan2(toLight.y, toLight.x);
        float rays = pow(0.5 + 0.5 * sin(ang * 24.0 + time * 0.5), 3.0);
        float rayAmt = rays * sky * (0.05 + bass * 0.12 + audio.isBeat * 0.10) * pShimmer;
        color.rgb += rayAmt * warmGlow;
    }

    // --- Warp distortion (grows with energy, gated by profile.warp) ---
    if (corruption > 0.3 && pWarp > 0.001) {
        float warpStrength = (corruption - 0.3) * 0.08;
        float2 warpedUV = uv;
        warpedUV.x += sin(uv.y * 20.0 + time * 2.0) * warpStrength * bass;
        warpedUV.y += cos(uv.x * 18.0 + time * 1.5) * warpStrength * bass;
        float4 warpedColor = compositionTex.sample(s, warpedUV);
        color = mix(color, warpedColor, (corruption - 0.3) * 0.7 * pWarp);
    }

    // --- Geometry Folding (peak energy, gated by profile.fold) ---
    if (corruption > 0.65 && pFold > 0.001) {
        float foldStrength = (corruption - 0.65) / 0.35;
        float energy = (bass + audio.bands[1] + mids + highs) * 0.25;
        float2 foldedUV = uv;
        if (foldStrength > 0.4) {
            foldedUV = abs(foldedUV * 2.0 - 1.0);
        }
        foldedUV += float2(sin(time * 2.0), cos(time * 1.5)) * foldStrength * energy * 0.15;
        float4 foldedColor = compositionTex.sample(s, foldedUV);
        color = mix(color, foldedColor, foldStrength * 0.6 * pFold);
    }

    // --- Transient flash (drops/breakdowns) ---
    if (audio.isTransient > 0.5) {
        color.rgb = mix(color.rgb, float3(1.2, 1.1, 1.3), 0.6);
    }

    // --- Saturation push with energy (ramp scaled by profile) ---
    float3 gray = float3(dot(color.rgb, float3(0.299, 0.587, 0.114)));
    float saturation = 1.2 + corruption * pSaturation;
    color.rgb = mix(gray, color.rgb, saturation);

    // --- Overall brightness boost so it pops on video walls ---
    color.rgb *= pBrightness;

    return color;
}
