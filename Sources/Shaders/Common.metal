#include <metal_stdlib>
#include "ShaderTypes.h"
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut fullscreenQuadVertex(uint vertexID [[vertex_id]]) {
    float2 positions[4] = {
        float2(-1, -1),
        float2( 1, -1),
        float2(-1,  1),
        float2( 1,  1)
    };
    float2 texCoords[4] = {
        float2(0, 1),
        float2(1, 1),
        float2(0, 0),
        float2(1, 0)
    };

    VertexOut out;
    out.position = float4(positions[vertexID], 0, 1);
    out.texCoord = texCoords[vertexID];
    return out;
}

fragment float4 passthroughFragment(VertexOut in [[stage_in]],
                                     texture2d<float> tex [[texture(0)]]) {
    constexpr sampler s(filter::linear);
    return tex.sample(s, in.texCoord);
}

fragment float4 solidColorFragment(VertexOut in [[stage_in]],
                                    constant float4 &color [[buffer(0)]]) {
    return color;
}
