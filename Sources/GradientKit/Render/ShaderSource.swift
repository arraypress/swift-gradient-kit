//
//  ShaderSource.swift
//  GradientKit
//
//  The compute kernel, kept as source and compiled at first use so the
//  package builds with plain `swift build` (no metallib step) and the
//  shader is versioned with the Swift that feeds it. Layouts here mirror
//  `Uniforms.swift` byte for byte.
//

import Foundation

enum ShaderSource {
    static let kernelName = "gradientkit_wallpaper"

    static let source = #"""
    #include <metal_stdlib>
    using namespace metal;

    // ---------------------------------------------------------------- data

    struct Stop {
        float4 lab;        // OKLab L, a, b + straight alpha
        float  position;
        float  pad0, pad1, pad2;
    };

    struct SmearData {
        float4 posVec;   // px, py, vx, vy
        float4 params;   // radius, strength, kind, 0
    };

    struct LayerData {
        float4 p0;   // circle/ring/ellipse/crescent: cx, cy, r (or rx), r2/ry/thickness
        float4 p1;   // line/wave: angle, bend, amplitude, wavelength | ellipse: rotation | crescent: cut cx, cy
        float4 p2;   // phase, distortAmount, distortScale, distortOctaves
        float4 p3;   // spread, opacity, litAngle, litAmount
        float4 p4;   // smoothing, seed, repeatPeriod, hueSweep(rad per t)
        float4 p5;   // chevrons: amplitude, wavelength | tiles: inset, cornerRadius, stagger (xyz)
        float4 p6;   // relief: height, profile, lightAz(rad), lightEl(rad)
        float4 p7;   // relief gloss, shininess, ambient, stepped(0/1)
        float4 p8;   // clip: cx, cy, halfW, halfH
        float4 p9;   // clip: kind, rotation, feather, inverted
        int kind; int blend; int stopOffset; int stopCount;
    };

    struct Globals {
        float2 size; float2 invSize;
        float minSide; float aspect; uint seed; int layerCount;
        int bgKind; int bgStopOffset; int bgStopCount; float bgAngle;
        float4 bgCenterRadius;   // cx, cy (scene units), radius, smoothing
        float4 warp;             // amount, scale, octaves, unused
        float4 grain;            // intensity, size, chroma, shadowBias
        float4 vignette;         // intensity, radius, softness, unused
        float4 tone;             // exposure, contrast, saturation, hueShift(rad)
        float4 misc;             // aberration px, ditherStep, smearCount, 0
        float4 bgMesh;           // columns, rows, stepped, aaWidth(t units)
        float4 orderA;           // effect order, kinds 0…5 (see Uniforms.swift)
        float4 orderB;
    };

    constant int FX_LIQUIFY = 0, FX_WARP = 1, FX_ABERRATION = 2, FX_TONE = 3, FX_VIGNETTE = 4, FX_GRAIN = 5;

    inline int effectAt(constant Globals& g, int i) {
        switch (i) {
            case 0: return int(g.orderA.x);
            case 1: return int(g.orderA.y);
            case 2: return int(g.orderA.z);
            case 3: return int(g.orderA.w);
            case 4: return int(g.orderB.x);
            default: return int(g.orderB.y);
        }
    }

    constant int KIND_CIRCLE = 0, KIND_ELLIPSE = 1, KIND_LINE = 2, KIND_RING = 3, KIND_CRESCENT = 4, KIND_WAVE = 5,
                 KIND_POLYGON = 6, KIND_RECT = 7, KIND_CAPSULE = 8, KIND_STRIPES = 9, KIND_BLOB = 10, KIND_NOISE = 11,
                 KIND_CHEVRONS = 12, KIND_TILES = 13, KIND_GLYPH = 14, KIND_GLYPH_PATTERN = 15, KIND_RAYS = 16;

    // Everything a glyph lookup needs, passed through the distance functions.
    struct GlyphSampling {
        texture2d_array<float, access::sample> color;
        texture2d_array<float, access::sample> sdf;
        sampler samp;
    };

    // Local glyph-box coordinates (±0.5 = the box) → signed distance in scene units.
    inline float glyphDistance(GlyphSampling g, float2 local, float boxSize, uint slice) {
        float2 uv = clamp(local + 0.5, 0.0, 1.0);
        float d = g.sdf.sample(g.samp, uv, slice).r * boxSize;
        // Beyond the box the field is clamped; add the distance to the box.
        float2 outside = max(abs(local) - 0.5, 0.0);
        return d + length(outside) * boxSize;
    }

    // Rotate + place: returns local box coords and the slice for a pattern cell.
    inline float2 rotate2(float2 p, float a) { float c = cos(a), s = sin(a); return float2(p.x * c + p.y * s, -p.x * s + p.y * c); }

    constant int BG_SOLID = 0, BG_LINEAR = 1, BG_RADIAL = 2, BG_MESH = 3;

    inline float floorMod(float x, float y) { return x - y * floor(x / y); }

    // ---------------------------------------------------------------- hash & noise

    inline uint pcg(uint v) {
        uint state = v * 747796405u + 2891336453u;
        uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
        return (word >> 22u) ^ word;
    }

    inline float hash1(int2 p, uint seed) {
        uint h = pcg(uint(p.x) ^ pcg(uint(p.y) ^ pcg(seed)));
        return float(h) * (1.0 / 4294967296.0);
    }

    // Smooth value noise on an integer lattice with cell size `cell` px.
    inline float valueNoise(float2 p, float cell, uint seed) {
        float2 g = p / cell;
        float2 i = floor(g);
        float2 f = g - i;
        f = f * f * (3.0 - 2.0 * f);
        int2 ii = int2(i);
        float a = hash1(ii, seed), b = hash1(ii + int2(1, 0), seed);
        float c = hash1(ii + int2(0, 1), seed), d = hash1(ii + int2(1, 1), seed);
        return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
    }

    // 2D simplex noise (Gustavson / McEwan), range about -1...1.
    inline float3 mod289(float3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
    inline float2 mod289(float2 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
    inline float3 permute(float3 x) { return mod289(((x * 34.0) + 1.0) * x); }

    float snoise(float2 v) {
        const float4 C = float4(0.211324865405187, 0.366025403784439, -0.577350269189626, 0.024390243902439);
        float2 i  = floor(v + dot(v, C.yy));
        float2 x0 = v - i + dot(i, C.xx);
        float2 i1 = (x0.x > x0.y) ? float2(1.0, 0.0) : float2(0.0, 1.0);
        float4 x12 = x0.xyxy + C.xxzz;
        x12.xy -= i1;
        i = mod289(i);
        float3 p = permute(permute(i.y + float3(0.0, i1.y, 1.0)) + i.x + float3(0.0, i1.x, 1.0));
        float3 m = max(0.5 - float3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), 0.0);
        m = m * m; m = m * m;
        float3 x = 2.0 * fract(p * C.www) - 1.0;
        float3 h = abs(x) - 0.5;
        float3 ox = floor(x + 0.5);
        float3 a0 = x - ox;
        m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
        float3 g;
        g.x = a0.x * x0.x + h.x * x0.y;
        g.yz = a0.yz * x12.xz + h.yz * x12.yw;
        return 130.0 * dot(m, g);
    }

    float fbm(float2 p, int octaves) {
        float amp = 0.5, sum = 0.0, norm = 0.0;
        for (int i = 0; i < octaves; i++) {
            sum += amp * snoise(p);
            norm += amp;
            p = p * 2.03 + float2(17.1, 31.7);
            amp *= 0.5;
        }
        return sum / max(norm, 1e-6);
    }

    // ---------------------------------------------------------------- colour

    inline float3 oklabToLinear(float3 lab) {
        float l_ = lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z;
        float m_ = lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z;
        float s_ = lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z;
        float l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_;
        return float3( 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                      -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                      -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s);
    }

    inline float3 linearToOklab(float3 c) {
        c = max(c, 0.0);
        float l = 0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b;
        float m = 0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b;
        float s = 0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b;
        float l_ = pow(l, 1.0 / 3.0), m_ = pow(m, 1.0 / 3.0), s_ = pow(s, 1.0 / 3.0);
        return float3(0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
                      1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
                      0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_);
    }

    inline float3 encodeSRGB(float3 c) {
        c = clamp(c, 0.0, 1.0);
        float3 lo = c * 12.92;
        float3 hi = 1.055 * pow(c, 1.0 / 2.4) - 0.055;
        return select(hi, lo, c <= 0.0031308);
    }

    inline float3 decodeSRGB(float3 v) {
        float3 lo = v / 12.92;
        float3 hi = pow((v + 0.055) / 1.055, 2.4);
        return select(hi, lo, v <= 0.04045);
    }

    // Ramp lookup in OKLab; returns (L, a, b, alpha). `stepped` holds each
    // stop's colour until the next (hard bands, anti-aliased over `aa`).
    float4 evalRamp(constant Stop* stops, int offset, int count, float t, float smoothing, bool stepped, float aa) {
        if (count <= 0) return float4(0.0);
        Stop first = stops[offset];
        if (count == 1 || t <= first.position) return first.lab;
        Stop last = stops[offset + count - 1];
        if (t >= last.position) return last.lab;
        for (int i = 1; i < count; i++) {
            Stop b = stops[offset + i];
            if (t <= b.position) {
                Stop a = stops[offset + i - 1];
                if (stepped) {
                    float u = smoothstep(b.position - max(aa, 1e-6), b.position, t);
                    return mix(a.lab, b.lab, u);
                }
                float u = (t - a.position) / max(b.position - a.position, 1e-6);
                u = mix(u, u * u * (3.0 - 2.0 * u), smoothing);
                return mix(a.lab, b.lab, u);
            }
        }
        return last.lab;
    }

    inline float3 blendMode(int mode, float3 dst, float3 src) {
        switch (mode) {
            case 1: return dst + src;                                  // add
            case 2: return 1.0 - (1.0 - dst) * (1.0 - src);            // screen
            case 3: return dst * src;                                  // multiply
            case 4: {                                                  // soft light (W3C)
                float3 d = select(sqrt(dst), ((16.0 * dst - 12.0) * dst + 4.0) * dst, dst <= 0.25);
                return select(dst + (2.0 * src - 1.0) * (d - dst),
                              dst - (1.0 - 2.0 * src) * dst * (1.0 - dst),
                              src <= 0.5);
            }
            case 5: return select(1.0 - 2.0 * (1.0 - dst) * (1.0 - src), 2.0 * dst * src, dst <= 0.5); // overlay
            default: return src;
        }
    }

    // ---------------------------------------------------------------- shapes

    // Resolve a glyph layer at q: local box coords, box size, slice.
    inline void glyphLocate(constant LayerData& L, float2 q, thread float2& local, thread float& box, thread uint& slice) {
        float2 rel = q - L.p0.xy;
        if (L.kind == KIND_GLYPH) {
            box = max(L.p1.y, 1e-4);
            local = rotate2(rel, L.p1.x) / box;
            slice = uint(L.p5.z);
            return;
        }
        float2 cell = max(L.p0.zw, 1e-4);
        float2 p = rotate2(rel, L.p1.x);
        float row = floor(p.y / cell.y + 0.5);
        p.x += L.p1.z * cell.x * row;                              // stagger
        float2 cellIndex = floor(p / cell + 0.5);
        float2 center = cellIndex * cell;
        int2 ci = int2(cellIndex);
        uint seed = uint(L.p4.y) * 7u + 13u;
        float h1 = hash1(ci, seed), h2 = hash1(ci, seed + 1u), h3 = hash1(ci, seed + 2u), h4 = hash1(ci, seed + 3u), h5 = hash1(ci, seed + 4u);
        center += (float2(h1, h2) - 0.5) * L.p1.w * cell;          // position jitter
        float rot = (h3 - 0.5) * 2.0 * L.p5.x;                     // rotation jitter (rad)
        float scale = 1.0 + (h4 - 0.5) * 2.0 * L.p5.y;             // scale jitter
        box = max(L.p1.y * scale, 1e-4);
        local = rotate2(p - center, rot) / box;
        uint count = max(uint(L.p5.w), 1u);
        slice = uint(L.p5.z) + uint(floor(h5 * float(count))) % count;
    }

    float layerDistance(constant LayerData& L, float2 q, GlyphSampling gs) {
        float2 c = L.p0.xy;
        float2 rel = q - c;
        switch (L.kind) {
            case KIND_GLYPH:
            case KIND_GLYPH_PATTERN: {
                float2 local; float box; uint slice;
                glyphLocate(L, q, local, box, slice);
                return glyphDistance(gs, local, box, slice);
            }
            case KIND_CIRCLE:
                return length(rel) - L.p0.z;
            case KIND_ELLIPSE: {
                float rot = L.p1.x;
                float cs = cos(rot), sn = sin(rot);
                float2 r = float2(rel.x * cs + rel.y * sn, -rel.x * sn + rel.y * cs);
                float2 ab = max(L.p0.zw, 1e-4);
                float2 rn = r / ab;
                float f = length(rn) - 1.0;                    // implicit
                float2 grad = rn / ab / max(length(rn), 1e-4); // ∇f
                return f / max(length(grad), 1e-4);            // first-order distance
            }
            case KIND_RING:
                return abs(length(rel) - L.p0.z) - L.p0.w * 0.5;
            case KIND_CRESCENT: {
                float d1 = length(rel) - L.p0.z;
                float d2 = length(q - L.p1.xy) - L.p0.w;
                return max(d1, -d2);
            }
            case KIND_LINE:
            case KIND_WAVE:
            case KIND_STRIPES: {
                float a = L.p1.x;
                float2 n = float2(cos(a), sin(a));
                float2 tdir = float2(-n.y, n.x);
                float along = dot(rel, tdir);
                float d = dot(rel, n);
                if (L.kind == KIND_LINE) {
                    d += L.p1.y * along * along;
                } else if (L.kind == KIND_WAVE) {
                    float wl = max(L.p1.w, 1e-3);
                    d += L.p1.z * sin(along * 6.28318530718 / wl + L.p2.x);
                } else {
                    d += L.p1.y * along * along;
                    float period = max(L.p1.z, 1e-3);
                    float m = d - period * floor(d / period + 0.5);   // distance to nearest stripe centre
                    d = abs(m) - L.p1.w * 0.5;
                }
                return d;
            }
            case KIND_POLYGON: {
                // Regular n-gon (Quilez), inset by the rounding then re-expanded.
                float rot = L.p1.x;
                float cs = cos(rot), sn = sin(rot);
                float2 p = float2(rel.x * cs + rel.y * sn, -rel.x * sn + rel.y * cs);
                float n = max(L.p1.y, 3.0);
                float rounding = min(L.p0.w, L.p0.z * 0.9);
                float r = max(L.p0.z - rounding, 1e-4);
                float an = 3.14159265 / n;
                float2 acs = float2(cos(an), sin(an));
                float bn = floorMod(atan2(p.x, p.y) + an, 2.0 * an) - an;
                float2 q2 = length(p) * float2(cos(bn), abs(sin(bn)));
                q2 -= r * acs;
                q2.y += clamp(-q2.y, 0.0, r * acs.y);
                return length(q2) * sign(q2.x) - rounding;
            }
            case KIND_RECT: {
                float rot = L.p1.x;
                float cs = cos(rot), sn = sin(rot);
                float2 p = float2(rel.x * cs + rel.y * sn, -rel.x * sn + rel.y * cs);
                float2 halfSize = max(L.p0.zw * 0.5, 1e-4);
                float cr = min(L.p1.y, min(halfSize.x, halfSize.y));
                float2 d2 = abs(p) - (halfSize - cr);
                return length(max(d2, 0.0)) + min(max(d2.x, d2.y), 0.0) - cr;
            }
            case KIND_CAPSULE: {
                float2 a = L.p0.xy, b = L.p0.zw;
                float2 pa = q - a, ba = b - a;
                float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
                return length(pa - ba * h) - L.p1.x;
            }
            case KIND_BLOB: {
                float theta = atan2(rel.y, rel.x);
                float rr = L.p0.z * (1.0 + L.p0.w * sin(L.p1.y * theta + L.p1.x));
                return length(rel) - rr;
            }
            case KIND_NOISE: {
                float2 np = (q - c) * L.p1.x + float2(L.p4.y * 0.13, -L.p4.y * 0.07);
                return fbm(np, int(L.p1.y));
            }
            case KIND_CHEVRONS: {
                float a = L.p1.x;
                float2 n = float2(cos(a), sin(a));
                float2 tdir = float2(-n.y, n.x);
                float along = dot(rel, tdir);
                float wl = max(L.p5.y, 1e-3);
                float tri = abs(2.0 * (along / wl - floor(along / wl + 0.5)));   // 0…1 triangle wave
                float d = dot(rel, n) + L.p5.x * (tri - 0.5) * 2.0;
                float period = max(L.p1.z, 1e-3);
                float m = d - period * floor(d / period + 0.5);
                return abs(m) - L.p1.w * 0.5;
            }
            case KIND_RAYS: {
                float count = max(L.p1.y, 1.0);
                float period = 6.28318530718 / count;
                float theta = atan2(rel.y, rel.x) - L.p1.x;
                float m = theta - period * floor(theta / period + 0.5);        // ±period/2
                float halfWidth = L.p1.z * period * 0.5;
                return (abs(m) - halfWidth) * max(length(rel), 1e-4);          // arc distance
            }
            case KIND_TILES: {
                float rot = L.p1.x;
                float cs = cos(rot), sn = sin(rot);
                float2 p = float2(rel.x * cs + rel.y * sn, -rel.x * sn + rel.y * cs);
                float2 cell = max(L.p0.zw, 1e-3);
                float row = floor(p.y / cell.y + 0.5);
                p.x += L.p5.z * cell.x * row;                       // stagger alternate rows
                float2 local = p - cell * floor(p / cell + 0.5);     // centred in its cell
                float2 halfSize = cell * 0.5 - L.p5.x;
                float cr = min(L.p5.y, min(halfSize.x, halfSize.y));
                float2 d2 = abs(local) - (halfSize - cr);
                return length(max(d2, 0.0)) + min(max(d2.x, d2.y), 0.0) - cr;
            }
        }
        return 1e9;
    }

    // Distance including the layer's own noise distortion.
    float layerField(constant LayerData& L, float2 q, GlyphSampling gs) {
        float d = layerDistance(L, q, gs);
        if (L.p2.y != 0.0) {
            float2 np = q * L.p2.z + float2(L.p4.y * 0.61, L.p4.y * 0.29);
            d += fbm(np, int(L.p2.w)) * L.p2.y;
        }
        return d;
    }

    // Height above the surface for a relief layer, from signed distance.
    inline float reliefHeight(constant LayerData& L, float d) {
        float x = clamp(-d / max(L.p3.x, 1e-5), 0.0, 1.0);
        int profile = int(L.p6.y);
        float h;
        if (profile == 0)      h = sqrt(max(0.0, 1.0 - (1.0 - x) * (1.0 - x)));   // dome
        else if (profile == 1) h = x * x * (3.0 - 2.0 * x);                        // bevel
        else                   h = x;                                              // slope
        return h * L.p6.x;
    }

    // ---------------------------------------------------------------- scene

    // Liquify: walk strokes newest-first, each displacing the sampling point.
    float2 applySmears(float2 q, int n, constant SmearData* smears) {
        for (int i = 0; i < n; i++) {
            constant SmearData& S = smears[i];
            float2 rel = q - S.posVec.xy;
            float r = max(S.params.x, 1e-4);
            if (abs(rel.x) >= r || abs(rel.y) >= r) continue;
            float d = length(rel) / r;
            if (d >= 1.0) continue;
            float w = pow(1.0 - d * d, max(S.params.w, 0.5)) * S.params.y;   // feathered bump, zero at the rim
            int kind = int(S.params.z);
            if (kind == 0) {                              // push: sample from behind the drag
                q -= S.posVec.zw * w;
            } else if (kind == 1) {                       // swirl
                float ang = (S.posVec.z + S.posVec.w) * 6.28318 * w;
                float cs = cos(ang), sn = sin(ang);
                q = S.posVec.xy + float2(rel.x * cs - rel.y * sn, rel.x * sn + rel.y * cs);
            } else if (kind == 2) {                       // pinch: pull outward samples in
                q = S.posVec.xy + rel * (1.0 + length(S.posVec.zw) * w);
            } else {                                      // bloat
                q = S.posVec.xy + rel * (1.0 - min(length(S.posVec.zw) * w, 0.9));
            }
        }
        return q;
    }

    // The smear map covers normalised canvas coords −0.25…1.25 and stores a
    // scene-unit displacement, so it is independent of output resolution.
    constant float MAP_LO = -0.25, MAP_SPAN = 1.5;

    inline float2 mapUV(float2 norm) { return (norm - MAP_LO) / MAP_SPAN; }

    float3 shade(float2 pix, constant Globals& g, constant LayerData* layers, constant Stop* stops,
                 texture2d<float, access::sample> smearMap, sampler samp, GlyphSampling gs) {
        float2 q = (pix - g.size * 0.5) / g.minSide;

        // Coordinate effects, in the stack's order. Each one displaces the
        // point the next samples at, so order changes the picture.
        for (int i = 0; i < 6; i++) {
            int fx = effectAt(g, i);
            if (fx == FX_LIQUIFY && g.misc.z > 0.0) {
                float2 norm = q * g.minSide * g.invSize + 0.5;
                q += smearMap.sample(samp, mapUV(norm)).xy;
            } else if (fx == FX_WARP && g.warp.x > 0.0) {
                int oct = int(g.warp.z);
                float2 base = q * g.warp.y + float2(float(g.seed % 977u) * 0.37, float(g.seed % 613u) * 0.53);
                float2 w = float2(fbm(base, oct), fbm(base + float2(41.3, -17.9), oct));
                q += w * g.warp.x;
            }
        }

        // Background
        float3 col;
        {
            float t = 0.0;
            if (g.bgKind == BG_LINEAR) {
                float2 n = float2(cos(g.bgAngle), sin(g.bgAngle));
                float2 halfExt = float2(g.size.x, g.size.y) * 0.5 / g.minSide;
                float ext = abs(n.x) * halfExt.x + abs(n.y) * halfExt.y;   // half-extent along n
                t = dot(q, n) / max(ext, 1e-4) * 0.5 + 0.5;
            } else if (g.bgKind == BG_RADIAL) {
                t = length(q - g.bgCenterRadius.xy) / max(g.bgCenterRadius.z, 1e-4);
            }
            if (g.bgKind == BG_MESH) {
                // Bilinear (eased) blend of a colour grid across the warped canvas.
                int cols = max(int(g.bgMesh.x), 1), rows = max(int(g.bgMesh.y), 1);
                float2 uv = clamp(q * g.minSide * g.invSize + 0.5, 0.0, 1.0);
                float fx = uv.x * float(cols - 1), fy = uv.y * float(rows - 1);
                int x0 = int(floor(fx)), y0 = int(floor(fy));
                int x1 = min(x0 + 1, cols - 1), y1 = min(y0 + 1, rows - 1);
                x0 = min(x0, cols - 1); y0 = min(y0, rows - 1);
                float ux = fx - floor(fx), uy = fy - floor(fy);
                ux = mix(ux, ux * ux * (3.0 - 2.0 * ux), g.bgCenterRadius.w);
                uy = mix(uy, uy * uy * (3.0 - 2.0 * uy), g.bgCenterRadius.w);
                int n = g.bgStopCount;
                float4 c00 = stops[g.bgStopOffset + min(y0 * cols + x0, n - 1)].lab;
                float4 c10 = stops[g.bgStopOffset + min(y0 * cols + x1, n - 1)].lab;
                float4 c01 = stops[g.bgStopOffset + min(y1 * cols + x0, n - 1)].lab;
                float4 c11 = stops[g.bgStopOffset + min(y1 * cols + x1, n - 1)].lab;
                float4 lab = mix(mix(c00, c10, ux), mix(c01, c11, ux), uy);
                col = oklabToLinear(lab.xyz);
            } else {
                float4 lab = evalRamp(stops, g.bgStopOffset, g.bgStopCount, t, g.bgCenterRadius.w, g.bgMesh.z > 0.5, g.bgMesh.w);
                col = oklabToLinear(lab.xyz);
            }
        }

        // Layers
        for (int i = 0; i < g.layerCount; i++) {
            constant LayerData& L = layers[i];
            float d = layerField(L, q, gs);
            float t = d / max(L.p3.x, 1e-5);
            if (L.p4.z > 0.0) {
                float period = L.p4.z;
                t = t - period * floor(t / period + 0.5);   // fold into ±period/2
            }
            float aa = 1.5 / (g.minSide * max(L.p3.x, 1e-5));
            float4 lab = evalRamp(stops, L.stopOffset, L.stopCount, t, L.p4.x, L.p7.w > 0.5, aa);
            if (L.p4.w != 0.0) {
                float ang = L.p4.w * t;
                float cs = cos(ang), sn = sin(ang);
                lab.yz = float2(lab.y * cs - lab.z * sn, lab.y * sn + lab.z * cs);
            }
            float alpha = lab.w * L.p3.y;
            if (L.p9.x > 0.5) {
                // Clip: a soft mask from a circle/ellipse or rectangle.
                float2 cr = rotate2(q - L.p8.xy, L.p9.y);
                float cd;
                if (L.p9.x < 1.5) {
                    float2 rn = cr / L.p8.zw;
                    float f = length(rn) - 1.0;
                    float2 grad = rn / L.p8.zw / max(length(rn), 1e-4);
                    cd = f / max(length(grad), 1e-4);
                } else {
                    float2 d2 = abs(cr) - L.p8.zw;
                    cd = length(max(d2, 0.0)) + min(max(d2.x, d2.y), 0.0);
                }
                float inside = 1.0 - smoothstep(-L.p9.z, L.p9.z, cd);
                alpha *= (L.p9.w > 0.5) ? (1.0 - inside) : inside;
            }
            if (L.p3.w != 0.0 && L.kind != KIND_LINE && L.kind != KIND_WAVE && L.kind != KIND_STRIPES && L.kind != KIND_NOISE && L.kind != KIND_RAYS) {
                // One-sided light: a linear gradient across the shape's own
                // radius (no singularity at the centre), eased at both ends.
                float2 dir = float2(cos(L.p3.z), sin(L.p3.z));
                float R = max((L.kind == KIND_ELLIPSE || L.kind == KIND_RECT) ? max(L.p0.z, L.p0.w)
                              : (L.kind == KIND_CAPSULE ? L.p1.x : ((L.kind == KIND_GLYPH || L.kind == KIND_GLYPH_PATTERN) ? L.p1.y * 0.5 : L.p0.z)), 1e-3);
                float facing = clamp(dot(q - L.p0.xy, dir) / R * 0.5 + 0.5, 0.0, 1.0);
                facing = smoothstep(0.15, 0.9, facing);
                alpha *= mix(1.0, facing, L.p3.w);
            }
            float3 src = oklabToLinear(lab.xyz);
            if ((L.kind == KIND_GLYPH || L.kind == KIND_GLYPH_PATTERN) && L.p2.x > 0.0) {
                // The emoji's own colours inside its outline, blended by glyphColor.
                float2 local; float box; uint slice;
                glyphLocate(L, q, local, box, slice);
                float2 uv = clamp(local + 0.5, 0.0, 1.0);
                bool inBox = all(abs(local) <= 0.5);
                float4 pm = inBox ? gs.color.sample(gs.samp, uv, slice) : float4(0.0);
                float ga = pm.a;
                float3 emoji = ga > 1e-4 ? pow(pm.rgb / ga, 2.2) : src;     // un-premultiply, to linear
                float k = L.p2.x * ga;
                src = mix(src, emoji, k);
                // Outside the emoji's own ink, only the ramp's alpha applies; inside, its coverage.
                alpha = mix(alpha, ga * L.p3.y, L.p2.x * (d < 0.0 ? 1.0 : 0.0));
            }
            if (alpha <= 0.0) continue;
            if (L.p6.x > 0.0) {
                // Relief: slope of the height field → normal → directional light + specular.
                float eps = 1.5 / g.minSide;
                float h0 = reliefHeight(L, d);
                float hx = reliefHeight(L, layerField(L, q + float2(eps, 0.0), gs));
                float hy = reliefHeight(L, layerField(L, q + float2(0.0, eps), gs));
                float3 nrm = normalize(float3(-(hx - h0) / eps, -(hy - h0) / eps, 1.0));
                float az = L.p6.z, el = L.p6.w;
                float3 Ld = float3(cos(az) * cos(el), sin(az) * cos(el), sin(el));
                float diffuse = mix(L.p7.z, 1.0, max(dot(nrm, Ld), 0.0));
                float3 H = normalize(Ld + float3(0.0, 0.0, 1.0));
                float spec = L.p7.x * pow(max(dot(nrm, H), 0.0), max(L.p7.y, 1.0));
                src = src * diffuse + spec;
            }
            float3 blended = blendMode(L.blend, col, src);
            col = mix(col, blended, clamp(alpha, 0.0, 1.0));
        }
        return col;
    }

    kernel void gradientkit_wallpaper(texture2d<float, access::write> out [[texture(0)]],
                                      constant Globals& g [[buffer(0)]],
                                      constant LayerData* layers [[buffer(1)]],
                                      constant Stop* stops [[buffer(2)]],
                                      constant SmearData* smears [[buffer(3)]],
                                      texture2d_array<float, access::sample> glyphColor [[texture(1)]],
                                      texture2d_array<float, access::sample> glyphSDF [[texture(2)]],
                                      texture2d<float, access::sample> smearMap [[texture(3)]],
                                      sampler glyphSampler [[sampler(0)]],
                                      uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= out.get_width() || gid.y >= out.get_height()) return;
        float2 pix = float2(gid) + 0.5;
        GlyphSampling gs = { glyphColor, glyphSDF, glyphSampler };

        float3 col;
        if (g.misc.x > 0.0) {
            float2 fromCenter = pix - g.size * 0.5;
            float2 halfSize = g.size * 0.5;
            float r = length(fromCenter / halfSize) / 1.41421356;   // 0 centre … 1 corner
            float2 dir = fromCenter / max(length(fromCenter), 1e-3);
            float2 off = dir * g.misc.x * r * r;
            col.r = shade(pix + off, g, layers, stops, smearMap, glyphSampler, gs).r;
            col.g = shade(pix, g, layers, stops, smearMap, glyphSampler, gs).g;
            col.b = shade(pix - off, g, layers, stops, smearMap, glyphSampler, gs).b;
        } else {
            col = shade(pix, g, layers, stops, smearMap, glyphSampler, gs);
        }

        // Colour effects, in the stack's order. `col` stays linear; grain
        // works in gamma space and converts back, so it can sit anywhere.
        for (int i = 0; i < 6; i++) {
            int fx = effectAt(g, i);
            if (fx == FX_TONE) {
                col *= exp2(g.tone.x);
                if (g.tone.z != 1.0) {
                    float lum = dot(col, float3(0.2126, 0.7152, 0.0722));
                    col = mix(float3(lum), col, g.tone.z);
                }
                if (g.tone.w != 0.0) {
                    float3 lab = linearToOklab(col);
                    float cs = cos(g.tone.w), sn = sin(g.tone.w);
                    lab.yz = float2(lab.y * cs - lab.z * sn, lab.y * sn + lab.z * cs);
                    col = oklabToLinear(lab);
                }
                if (g.tone.y != 1.0) {
                    float3 e = encodeSRGB(col);
                    e = (e - 0.5) * g.tone.y + 0.5;
                    col = decodeSRGB(clamp(e, 0.0, 1.0));
                }
            } else if (fx == FX_VIGNETTE && g.vignette.x > 0.0) {
                float2 uv = (pix * g.invSize - 0.5) * 2.0;
                float rr = length(uv) / 1.41421356;
                float v = smoothstep(g.vignette.y, g.vignette.y + max(g.vignette.z, 1e-3), rr);
                col *= 1.0 - g.vignette.x * v;
            } else if (fx == FX_GRAIN && g.grain.x > 0.0) {
                float gi = g.grain.x;
                float3 srgb = encodeSRGB(col);
                float cell = max(g.grain.y, 1.0);
                uint s = g.seed;
                float3 n;
                if (cell <= 1.0) {
                    n = float3(hash1(int2(gid), s), hash1(int2(gid), s + 1u), hash1(int2(gid), s + 2u));
                } else {
                    // Soft clumps at the cell size plus a touch of per-pixel sparkle.
                    float fine = 0.35;
                    float3 coarse = float3(valueNoise(pix, cell, s), valueNoise(pix, cell, s + 1u), valueNoise(pix, cell, s + 2u));
                    float3 fineN = float3(hash1(int2(gid), s + 3u), hash1(int2(gid), s + 4u), hash1(int2(gid), s + 5u));
                    n = mix(coarse, fineN, fine);
                }
                n = n - 0.5;
                float mono = n.x;
                float3 grain = mix(float3(mono), n, g.grain.z) * 2.0 * gi;
                float lum = dot(srgb, float3(0.299, 0.587, 0.114));
                float bias = g.grain.w;
                float weight = 1.0 + bias * (0.5 - lum) * 2.0;   // shadowBias>0 → more in darks
                srgb += grain * max(weight, 0.0);
                col = decodeSRGB(clamp(srgb, 0.0, 1.0));
            }
        }

        // Encode
        float3 srgb = encodeSRGB(col);

        // Triangular dither (±1 LSB)
        float step = g.misc.y;
        if (step > 0.0) {
            float d1 = hash1(int2(gid), g.seed + 101u);
            float d2 = hash1(int2(gid), g.seed + 202u);
            srgb += (d1 - d2) * step;
        }

        out.write(float4(clamp(srgb, 0.0, 1.0), 1.0), gid);
    }

    // ------------------------------------------------------------- smear map

    // Rebuild the whole displacement map from the stroke list (newest first).
    kernel void gradientkit_smear_rebuild(texture2d<float, access::write> map [[texture(0)]],
                                          constant Globals& g [[buffer(0)]],
                                          constant SmearData* smears [[buffer(3)]],
                                          uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= map.get_width() || gid.y >= map.get_height()) return;
        float2 uv = (float2(gid) + 0.5) / float2(map.get_width(), map.get_height());
        float2 norm = uv * MAP_SPAN + MAP_LO;
        float2 q = (norm - 0.5) * g.size / g.minSide;
        float2 q2 = applySmears(q, int(g.misc.z), smears);
        map.write(float4(q2 - q, 0.0, 0.0), gid);
    }

    // Compose one new stroke sample onto an existing map: D'(p) = s(p) + D(s(p)) − p.
    kernel void gradientkit_smear_append(texture2d<float, access::sample> oldMap [[texture(0)]],
                                         texture2d<float, access::write> newMap [[texture(1)]],
                                         constant Globals& g [[buffer(0)]],
                                         constant SmearData* smear [[buffer(3)]],
                                         sampler samp [[sampler(0)]],
                                         uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= newMap.get_width() || gid.y >= newMap.get_height()) return;
        float2 uv = (float2(gid) + 0.5) / float2(newMap.get_width(), newMap.get_height());
        float2 norm = uv * MAP_SPAN + MAP_LO;
        float2 q = (norm - 0.5) * g.size / g.minSide;
        float2 q2 = applySmears(q, 1, smear);
        float2 norm2 = q2 * g.minSide / g.size + 0.5;
        float2 old = oldMap.sample(samp, mapUV(norm2)).xy;
        newMap.write(float4(q2 + old - q, 0.0, 0.0), gid);
    }
    """#
}
