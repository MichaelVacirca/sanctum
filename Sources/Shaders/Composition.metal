#include <metal_stdlib>
#include "ShaderTypes.h"
using namespace metal;

// Composite a single full-screen panel with crossfade to next panel
kernel void compositePanels(
    texture2d<float, access::write> canvas [[texture(0)]],
    texture2d<float> currentPanel [[texture(1)]],
    texture2d<float> nextPanel [[texture(2)]],
    constant float4 &tintColor [[buffer(0)]],
    constant float &crossfade [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint canvasW = canvas.get_width();
    uint canvasH = canvas.get_height();
    constexpr sampler s(filter::linear);

    float2 uv = float2(float(gid.x) / float(canvasW),
                        float(gid.y) / float(canvasH));

    float4 colorA = currentPanel.sample(s, uv);
    float4 colorB = nextPanel.sample(s, uv);
    float4 color = mix(colorA, colorB, crossfade);
    color.rgb *= tintColor.rgb;
    canvas.write(color, gid);
}

struct IconInstance {
    float2 position;
    float2 size;
    float opacity;
    float rotation;
    float scale;
    float padding;
};

kernel void compositeIcons(
    texture2d<float, access::read_write> canvas [[texture(0)]],
    texture2d<float> iconAtlas [[texture(1)]],
    const device IconInstance *icons [[buffer(0)]],
    constant uint &iconCount [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    float2 pixelPos = float2(gid);
    float4 color = canvas.read(gid);
    constexpr sampler s(filter::linear, address::clamp_to_edge);

    for (uint i = 0; i < iconCount && i < 32; i++) {
        IconInstance icon = icons[i];
        float2 scaledSize = icon.size * icon.scale;
        float2 localPos = pixelPos - icon.position;

        float cosR = cos(icon.rotation);
        float sinR = sin(icon.rotation);
        float2 rotated = float2(
            localPos.x * cosR + localPos.y * sinR,
            -localPos.x * sinR + localPos.y * cosR
        );

        float2 halfSize = scaledSize * 0.5;
        if (abs(rotated.x) < halfSize.x && abs(rotated.y) < halfSize.y) {
            float2 uv = (rotated + halfSize) / scaledSize;
            float4 texColor = iconAtlas.sample(s, uv);
            texColor.a *= icon.opacity;
            color.rgb = mix(color.rgb, texColor.rgb, texColor.a);
        }
    }

    canvas.write(color, gid);
}
