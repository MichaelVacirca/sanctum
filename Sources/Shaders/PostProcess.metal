#include <metal_stdlib>
#include "ShaderTypes.h"
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

float hash(float2 p) {
    float h = dot(p, float2(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fragment float4 postProcessFragment(
    VertexOut in [[stage_in]],
    texture2d<float> effectsTex [[texture(0)]],
    texture2d<float> prevFrameTex [[texture(1)]],
    constant AudioUniforms &audio [[buffer(0)]]
) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 uv = in.texCoord;
    float4 color = effectsTex.sample(s, uv);
    float corruption = audio.corruptionIndex;
    float bass = audio.bands[0];

    // --- Bloom (larger kernel, bass-driven, more intense) ---
    float bloomIntensity = 0.4 + bass * 0.6 + corruption * 0.3;
    float4 bloom = float4(0);
    float bloomRadius = 0.004 + corruption * 0.006 + bass * 0.003;
    for (int x = -3; x <= 3; x++) {
        for (int y = -3; y <= 3; y++) {
            if (x == 0 && y == 0) continue;
            float2 offset = float2(x, y) * bloomRadius;
            bloom += effectsTex.sample(s, uv + offset);
        }
    }
    bloom /= 48.0;
    float brightness = dot(bloom.rgb, float3(0.299, 0.587, 0.114));
    bloom *= smoothstep(0.3, 0.7, brightness);
    color.rgb += bloom.rgb * bloomIntensity;

    // --- Film Grain (subtle) ---
    float grain = hash(uv * float2(effectsTex.get_width(), effectsTex.get_height()) + audio.time * 100.0);
    grain = (grain - 0.5) * 0.04;
    color.rgb += grain;

    // --- Vignette (stronger, dramatic) ---
    float2 vignetteUV = uv * (1.0 - uv);
    float vignette = vignetteUV.x * vignetteUV.y * 15.0;
    vignette = pow(vignette, 0.25 + corruption * 0.25);
    color.rgb *= vignette;

    // --- Motion Blur (blend with previous frame) ---
    float motionBlurAmount = 0.08 + corruption * 0.2;
    float4 prevColor = prevFrameTex.sample(s, uv);
    color = mix(color, prevColor, motionBlurAmount);

    color = clamp(color, 0.0, 1.0);
    color.a = 1.0;

    return color;
}
