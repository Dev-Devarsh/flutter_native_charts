#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float4 color;
};

struct ChartUniforms {
    float4x4 projection;
};

// Vertex shader reads per-vertex {x, y, r, g, b, a} as 6 consecutive floats
// from buffer 0. The renderer (Swift) uploads the interleaved buffer directly.
vertex VertexOut chart_vertex_main(uint vid [[vertex_id]],
                                   const device float* vertices [[buffer(0)]],
                                   constant ChartUniforms& uniforms [[buffer(1)]]) {
    uint base = vid * 6u;
    float2 pos = float2(vertices[base], vertices[base + 1u]);
    float4 col = float4(vertices[base + 2u],
                        vertices[base + 3u],
                        vertices[base + 4u],
                        vertices[base + 5u]);
    VertexOut out;
    out.position = uniforms.projection * float4(pos, 0.0, 1.0);
    out.color = col;
    return out;
}

fragment float4 chart_fragment_main(VertexOut in [[stage_in]]) {
    return in.color;
}
