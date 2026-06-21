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
    float pFlash      = audio.flash;
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
    // The hard strobe (step) only ramps in with the theme's flash amount, so
    // calm themes (beach) keep the smooth pulse instead of flickering.
    float pulse = sin(audio.beatPhase * 3.14159 * 2.0);
    float lightIntensity = mix(
        0.7 + 0.3 * pulse,
        0.3 + 0.7 * step(0.5, fract(audio.beatPhase * 2.0)),
        corruption * pFlash
    );
    // Beat flash (scaled by theme flash amount)
    float beatFlash = audio.isBeat * (1.0 - corruption * 0.3) * 0.6 * pFlash;
    lightIntensity += beatFlash;
    // Bass throb — the whole image breathes with the bass
    lightIntensity += bass * 0.25;
    color.rgb *= lightIntensity;

    // --- Color Grading (theme phase tint + highs sparkle) ---
    float3 tint = phaseTint + highs * 0.15;
    color.rgb *= tint;

    // --- Beach reactivity: a beating sun + rolling ocean waves ---
    // Gated by the theme's shimmer knob, so cathedral (shimmer == 0) is
    // untouched. The reactions are centred on the two beach motifs the music
    // drives: the sun pulses/blooms on the kick, the waves roll and surge.
    if (pShimmer > 0.001) {
        const float aspect = 16.0 / 9.0;        // keep the sun round on a 16:9 wall
        float beatHit = audio.isBeat;
        float throb = 0.5 + 0.5 * sin(audio.beatPhase * 6.28318); // per-beat swell

        // Warm by day, cycling neon at the peak (the midnight rave).
        float3 sunWarm = float3(1.0, 0.82, 0.45);
        float3 neon = mix(float3(0.40, 1.0, 1.0), float3(1.0, 0.45, 1.0),
                          0.5 + 0.5 * sin(time * 1.6));
        float3 sunCol = mix(sunWarm, neon, smoothstep(0.55, 0.9, corruption));

        // ---- The beating sun ----
        float2 d = uv - float2(audio.sunPos[0], audio.sunPos[1]);
        d.x *= aspect;
        float dist = length(d);
        // Tight glow halo that swells on the bass and flares on the kick.
        float halo = exp(-dist * (10.0 - bass * 2.0 - beatHit * 1.0));
        // Thin rays radiating from the sun, slowly turning, pulsing on the beat.
        float ang = atan2(d.y, d.x);
        float rays = pow(0.5 + 0.5 * sin(ang * 18.0 + time * 0.45), 3.0);
        float rayGlow = rays * exp(-dist * 4.5) * (0.10 + bass * 0.32 + beatHit * 0.28);
        color.rgb += (halo * (0.35 + throb * 0.40) + rayGlow) * sunCol * pShimmer;

        // ---- Rolling ocean waves ----
        // Spare the bright window frame: fade the water FX out on bright pixels.
        float luma = dot(color.rgb, float3(0.299, 0.587, 0.114));
        float viewMask = 1.0 - smoothstep(0.72, 0.96, luma);
        float sea = smoothstep(0.52, 0.63, uv.y) * viewMask;
        // The beat advances the surf, so waves roll in time with the music.
        float roll = time * 1.2 + audio.beatPhase * 1.4;
        float waves = sin(uv.y * 34.0 - roll * 3.0 + sin(uv.x * 5.0 + time * 0.3) * 1.2);
        // Water rises and falls...
        color.rgb *= 1.0 + waves * 0.10 * sea * (0.5 + bass);
        // ...and foam crests catch the light, swelling on the kick.
        float crest = smoothstep(0.5, 1.0, waves);
        float swell = 0.25 + bass * 0.7 + beatHit * 0.45;
        float3 foamCol = mix(float3(0.75, 0.92, 1.0), neon, smoothstep(0.6, 0.9, corruption));
        color.rgb += crest * swell * sea * pShimmer * foamCol * 0.55;
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

    // --- Transient flash (drops/breakdowns) — smooth decaying pulse, scaled
    // by the theme flash amount (isTransient is a 0→1 decaying envelope) ---
    color.rgb = mix(color.rgb, float3(1.2, 1.1, 1.3), audio.isTransient * 0.6 * pFlash);

    // --- Saturation push with energy (ramp scaled by profile) ---
    float3 gray = float3(dot(color.rgb, float3(0.299, 0.587, 0.114)));
    float saturation = 1.2 + corruption * pSaturation;
    color.rgb = mix(gray, color.rgb, saturation);

    // --- Overall brightness boost so it pops on video walls ---
    color.rgb *= pBrightness;

    return color;
}
