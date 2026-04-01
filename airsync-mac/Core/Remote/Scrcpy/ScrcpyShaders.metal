//
//  ScrcpyShaders.metal
//  AirSync
//
//  Created by Sameera Wijerathna on 2026-04-01.
//

#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float4 position [[position]];
    float2 texCoord;
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut video_vertex(uint vertexID [[vertex_id]]) {
    const float2 vertices[] = {
        {-1, -1}, {0, 1},
        { 1, -1}, {1, 1},
        {-1,  1}, {0, 0},
        { 1,  1}, {1, 0}
    };
    
    VertexOut out;
    out.position = float4(vertices[vertexID * 2], 0, 1);
    out.texCoord = vertices[vertexID * 2 + 1];
    return out;
}

fragment float4 video_fragment(VertexOut in [[stage_in]],
                              texture2d<float, access::sample> textureY [[texture(0)]],
                              texture2d<float, access::sample> textureUV [[texture(1)]]) {
    
    sampler s(address::clamp_to_edge, filter::linear);
    
    float y = textureY.sample(s, in.texCoord).r;
    float2 uv = textureUV.sample(s, in.texCoord).rg - float2(0.5, 0.5);
    
    // YCbCr to RGB conversion (BT.709)
    float r = y + 1.5748 * uv.y;
    float g = y - 0.1873 * uv.x - 0.4681 * uv.y;
    float b = y + 1.8556 * uv.x;
    
    return float4(r, g, b, 1.0);
}
