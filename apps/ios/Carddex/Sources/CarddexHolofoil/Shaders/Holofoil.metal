// Holofoil.metal — Metal Shading Language port of the GLSL shaders defined
// in `apps/web/src/render/shaders.js` (re-exported from `packages/shaders`).
//
// Each pattern below mirrors a "family" from the web renderer. They are
// intentionally hand-ported one-to-one; golden-image parity tests pin the
// MSL output to a Three.js reference render for the same `(card, light, angle)`
// tuples so that visual drift is caught in CI.

#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float2 viewAngle;       // pitch, yaw (radians)
    float3 lightDirection;
    float  depthScale;
    float  foilStrength;
    float  coverage;
    int    pattern;         // 0 = none, 1 = starlight, 2 = cosmos, ...
    float  time;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// A simple full-screen triangle-strip quad for the card face. The actual
// Carddex web renderer displaces vertices by the depth map; we replicate
// that displacement here once we have a vertex buffer for the card mesh.
// For the scaffold we keep a flat quad and let the fragment shader carry
// the holofoil math.
vertex VertexOut holofoil_vertex(uint vid [[vertex_id]],
                                 constant Uniforms &u [[buffer(1)]]) {
    float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    VertexOut out;
    out.position = float4(positions[vid], 0.0, 1.0);
    out.uv = positions[vid] * 0.5 + 0.5;
    return out;
}

// MARK: - Pattern helpers (ported from GLSL)

static inline float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static inline float starlight(float2 uv, float angle, float t) {
    float2 g = floor(uv * 60.0);
    float h = hash21(g);
    float twinkle = 0.5 + 0.5 * sin(t * 4.0 + h * 6.28318);
    float beam = pow(saturate(cos(angle * 6.0 + h * 6.28)), 8.0);
    return saturate(twinkle * beam);
}

static inline float cosmos(float2 uv, float angle) {
    float v = sin(uv.x * 12.0 + angle * 3.0) * cos(uv.y * 18.0 - angle * 2.0);
    return saturate(0.5 + 0.5 * v);
}

static inline float tinsel(float2 uv, float angle) {
    float bands = sin((uv.x + uv.y) * 80.0 + angle * 6.0);
    return saturate(0.5 + 0.5 * bands);
}

static inline float sheen(float2 uv, float angle) {
    return saturate(pow(cos((uv.x - uv.y) * 4.0 + angle * 3.14), 4.0));
}

static inline float crackedIce(float2 uv) {
    float2 q = uv * 7.0;
    float h = hash21(floor(q));
    return saturate(smoothstep(0.4, 0.9, h));
}

static inline float crosshatch(float2 uv, float angle) {
    float a = sin(uv.x * 60.0 + angle * 3.0);
    float b = sin(uv.y * 60.0 - angle * 3.0);
    return saturate(0.5 + 0.5 * a * b);
}

static inline float waterWeb(float2 uv, float t) {
    float v = sin(uv.x * 20.0 + sin(uv.y * 14.0 + t)) * 0.5 + 0.5;
    return saturate(v);
}

static inline float sequin(float2 uv) {
    float2 g = floor(uv * 80.0);
    return step(0.7, hash21(g));
}

static inline float fireworks(float2 uv, float t) {
    float2 g = floor(uv * 12.0);
    float h = hash21(g);
    float pulse = saturate(sin(t * 3.0 + h * 6.28));
    float radial = exp(-12.0 * length(fract(uv * 12.0) - 0.5));
    return saturate(pulse * radial);
}

static inline float plain() { return 0.6; }

// MARK: - Fragment

fragment float4 holofoil_fragment(VertexOut in [[stage_in]],
                                  constant Uniforms &u [[buffer(0)]],
                                  texture2d<float> frontTex   [[texture(0)]],
                                  texture2d<float> depthTex   [[texture(1)]],
                                  texture2d<float> foilMask   [[texture(2)]],
                                  texture2d<float> expandedTex[[texture(3)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);

    float2 uv = in.uv;
    float depth = depthTex.sample(s, uv).r;

    // Parallax UV based on view angle, gated by depth.
    float2 parallax = uv + u.viewAngle * (depth - 0.5) * u.depthScale * 4.0;
    float4 base = frontTex.sample(s, parallax);

    // Sample the foil mask; >0 marks foil-eligible pixels.
    float mask = foilMask.sample(s, uv).a * u.coverage;

    float angle = atan2(u.viewAngle.y, u.viewAngle.x);
    float pattern = 0.0;
    switch (u.pattern) {
        case 1:  pattern = starlight(uv, angle, u.time); break;
        case 2:  pattern = cosmos(uv, angle); break;
        case 3:  pattern = tinsel(uv, angle); break;
        case 4:  pattern = sheen(uv, angle); break;
        case 5:  pattern = crackedIce(uv); break;
        case 6:  pattern = crosshatch(uv, angle); break;
        case 7:  pattern = waterWeb(uv, u.time); break;
        case 8:  pattern = sequin(uv); break;
        case 9:  pattern = fireworks(uv, u.time); break;
        case 10: pattern = plain(); break;
        default: pattern = 0.0; break;
    }

    float3 holo = float3(0.85, 0.95, 1.0) * pattern * u.foilStrength;
    float3 color = base.rgb + holo * mask;
    return float4(color, 1.0);
}
