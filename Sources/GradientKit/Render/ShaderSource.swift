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

    struct LayerData {
        float4 p0;   // circle/ring/ellipse/crescent: cx, cy, r (or rx), r2/ry/thickness
        float4 p1;   // line/wave: angle, bend, amplitude, wavelength | ellipse: rotation | crescent: cut cx, cy
        float4 p2;   // phase, distortAmount, distortScale, distortOctaves
        float4 p3;   // spread, opacity, litAngle, litAmount
        float4 p4;   // smoothing, seed, 0, 0
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
        float4 misc;             // aberration px, ditherStep, 0, 0
    };

    constant int KIND_CIRCLE = 0, KIND_ELLIPSE = 1, KIND_LINE = 2, KIND_RING = 3, KIND_CRESCENT = 4, KIND_WAVE = 5;
    constant int BG_SOLID = 0, BG_LINEAR = 1, BG_RADIAL = 2;

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

    // Ramp lookup in OKLab; returns (L, a, b, alpha).
    float4 evalRamp(constant Stop* stops, int offset, int count, float t, float smoothing) {
        if (count <= 0) return float4(0.0);
        Stop first = stops[offset];
        if (count == 1 || t <= first.position) return first.lab;
        Stop last = stops[offset + count - 1];
        if (t >= last.position) return last.lab;
        for (int i = 1; i < count; i++) {
            Stop b = stops[offset + i];
            if (t <= b.position) {
                Stop a = stops[offset + i - 1];
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

    float layerDistance(constant LayerData& L, float2 q) {
        float2 c = L.p0.xy;
        float2 rel = q - c;
        switch (L.kind) {
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
            case KIND_WAVE: {
                float a = L.p1.x;
                float2 n = float2(cos(a), sin(a));
                float2 tdir = float2(-n.y, n.x);
                float along = dot(rel, tdir);
                float d = dot(rel, n);
                if (L.kind == KIND_LINE) {
                    d += L.p1.y * along * along;
                } else {
                    float wl = max(L.p1.w, 1e-3);
                    d += L.p1.z * sin(along * 6.28318530718 / wl + L.p2.x);
                }
                return d;
            }
        }
        return 1e9;
    }

    // ---------------------------------------------------------------- scene

    float3 shade(float2 pix, constant Globals& g, constant LayerData* layers, constant Stop* stops) {
        float2 q = (pix - g.size * 0.5) / g.minSide;

        if (g.warp.x > 0.0) {
            int oct = int(g.warp.z);
            float2 base = q * g.warp.y + float2(float(g.seed % 977u) * 0.37, float(g.seed % 613u) * 0.53);
            float2 w = float2(fbm(base, oct), fbm(base + float2(41.3, -17.9), oct));
            q += w * g.warp.x;
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
            float4 lab = evalRamp(stops, g.bgStopOffset, g.bgStopCount, t, g.bgCenterRadius.w);
            col = oklabToLinear(lab.xyz);
        }

        // Layers
        for (int i = 0; i < g.layerCount; i++) {
            constant LayerData& L = layers[i];
            float d = layerDistance(L, q);
            if (L.p2.y != 0.0) {
                float2 np = q * L.p2.z + float2(L.p4.y * 0.61, L.p4.y * 0.29);
                d += fbm(np, int(L.p2.w)) * L.p2.y;
            }
            float t = d / max(L.p3.x, 1e-5);
            float4 lab = evalRamp(stops, L.stopOffset, L.stopCount, t, L.p4.x);
            float alpha = lab.w * L.p3.y;
            if (L.p3.w != 0.0 && L.kind != KIND_LINE && L.kind != KIND_WAVE) {
                // One-sided light: a linear gradient across the shape's own
                // radius (no singularity at the centre), eased at both ends.
                float2 dir = float2(cos(L.p3.z), sin(L.p3.z));
                float R = max(L.kind == KIND_ELLIPSE ? max(L.p0.z, L.p0.w) : L.p0.z, 1e-3);
                float facing = clamp(dot(q - L.p0.xy, dir) / R * 0.5 + 0.5, 0.0, 1.0);
                facing = smoothstep(0.15, 0.9, facing);
                alpha *= mix(1.0, facing, L.p3.w);
            }
            if (alpha <= 0.0) continue;
            float3 src = oklabToLinear(lab.xyz);
            float3 blended = blendMode(L.blend, col, src);
            col = mix(col, blended, clamp(alpha, 0.0, 1.0));
        }
        return col;
    }

    kernel void gradientkit_wallpaper(texture2d<float, access::write> out [[texture(0)]],
                                      constant Globals& g [[buffer(0)]],
                                      constant LayerData* layers [[buffer(1)]],
                                      constant Stop* stops [[buffer(2)]],
                                      uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= out.get_width() || gid.y >= out.get_height()) return;
        float2 pix = float2(gid) + 0.5;

        float3 col;
        if (g.misc.x > 0.0) {
            float2 fromCenter = pix - g.size * 0.5;
            float2 halfSize = g.size * 0.5;
            float r = length(fromCenter / halfSize) / 1.41421356;   // 0 centre … 1 corner
            float2 dir = fromCenter / max(length(fromCenter), 1e-3);
            float2 off = dir * g.misc.x * r * r;
            col.r = shade(pix + off, g, layers, stops).r;
            col.g = shade(pix, g, layers, stops).g;
            col.b = shade(pix - off, g, layers, stops).b;
        } else {
            col = shade(pix, g, layers, stops);
        }

        // Tone (linear light)
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

        // Vignette
        if (g.vignette.x > 0.0) {
            float2 uv = (pix * g.invSize - 0.5) * 2.0;
            float rr = length(uv) / 1.41421356;
            float v = smoothstep(g.vignette.y, g.vignette.y + max(g.vignette.z, 1e-3), rr);
            col *= 1.0 - g.vignette.x * v;
        }

        // Encode
        float3 srgb = encodeSRGB(col);
        if (g.tone.y != 1.0) srgb = (srgb - 0.5) * g.tone.y + 0.5;

        // Grain (gamma space)
        float gi = g.grain.x;
        if (gi > 0.0) {
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
        }

        // Triangular dither (±1 LSB)
        float step = g.misc.y;
        if (step > 0.0) {
            float d1 = hash1(int2(gid), g.seed + 101u);
            float d2 = hash1(int2(gid), g.seed + 202u);
            srgb += (d1 - d2) * step;
        }

        out.write(float4(clamp(srgb, 0.0, 1.0), 1.0), gid);
    }
    """#
}
