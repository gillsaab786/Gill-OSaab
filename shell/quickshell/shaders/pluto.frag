#version 440
// Gill(OS) live wallpaper "Pluto": a far, cold dwarf planet with its pale heart, lit by a tiny
// distant sun and slowly turning (it spins once every 6.4 days; here a little faster).
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float aspect;
    float dark;
};

float hash13(vec3 p) { p = fract(p * 0.1031); p += dot(p, p.zyx + 31.32); return fract((p.x + p.y) * p.z); }
float hash12(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
float noise3(vec3 x) {
    vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
               mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float fbm(vec3 p) { float a = 0.5, s = 0.0; for (int i = 0; i < 6; i++) { s += a * noise3(p); p = p * 2.03 + 7.7; a *= 0.5; } return s; }

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 p = (uv - 0.5) * vec2(aspect, 1.0);
    vec3 col = mix(vec3(0.004, 0.005, 0.012), vec3(0.012, 0.012, 0.03), smoothstep(0.7, -0.5, p.y));
    for (int layer = 0; layer < 3; layer++) {
        float scale = 90.0 + float(layer) * 80.0;
        vec2 g = p * scale; vec2 id = floor(g); float h = hash12(id + float(layer) * 41.0);
        if (h > 0.968) {
            float d = length(fract(g) - vec2(hash12(id + 2.1), hash12(id + 5.3)));
            col += smoothstep(0.1, 0.0, d) * (h - 0.968) * 24.0 * (0.7 + 0.3 * sin(time * (0.4 + h) + h * 50.0));
        }
    }
    // Charon, small and far behind
    vec2 cc = vec2(-0.32 * aspect, -0.22);
    float cr = length(p - cc) / 0.035;
    if (cr < 1.0) {
        vec3 n = vec3((p - cc) / 0.035 * vec2(1, -1), sqrt(1.0 - cr * cr));
        col = vec3(0.42, 0.41, 0.40) * (0.15 + 0.85 * max(dot(n, normalize(vec3(0.8, 0.3, 0.4))), 0.0)) * (0.8 + 0.4 * fbm(n * 6.0));
    }
    // Pluto
    vec2 c = vec2(0.18 * aspect, 0.08);
    float R = 0.36;
    vec2 d = (p - c) / R;
    float r2 = dot(d, d);
    vec3 sun = normalize(vec3(0.75, 0.35, 0.55));
    if (r2 < 1.0) {
        vec3 n = vec3(d.x, -d.y, sqrt(1.0 - r2));
        float a = time * 0.02;
        mat3 rot = mat3(cos(a), 0, -sin(a), 0, 1, 0, sin(a), 0, cos(a)) * mat3(1, 0, 0, 0, cos(0.35), sin(0.35), 0, -sin(0.35), cos(0.35));
        vec3 w = rot * n;
        // tholin browns and reds, nitrogen-ice plains, and the heart
        float t = fbm(w * 2.2);
        vec3 surf = mix(vec3(0.36, 0.20, 0.12), vec3(0.72, 0.58, 0.46), smoothstep(0.35, 0.7, t));
        surf = mix(surf, vec3(0.20, 0.09, 0.06), smoothstep(0.55, 0.8, fbm(w * 4.5 + 3.0)) * smoothstep(0.1, -0.5, w.y));
        vec3 hp = w - normalize(vec3(0.15, 0.05, 1.0));
        float heart = smoothstep(0.62, 0.48, length(hp * vec3(1.0, 1.25, 1.0)) + (fbm(w * 5.0) - 0.5) * 0.25);
        surf = mix(surf, vec3(0.93, 0.90, 0.86), heart * 0.95);
        surf *= 0.85 + 0.3 * fbm(w * 18.0);
        float ndl = dot(n, sun);
        float lit = smoothstep(-0.04, 0.3, ndl) * (0.3 + 0.7 * max(ndl, 0.0));
        vec3 planet = surf * lit * 1.1 + surf * 0.01;
        // a thin blue haze at the rim (Pluto's hazy air)
        planet += vec3(0.25, 0.45, 0.9) * pow(1.0 - n.z, 4.0) * smoothstep(-0.3, 0.3, ndl) * 0.5;
        col = mix(col, planet, smoothstep(1.0, 0.99, sqrt(r2)));
    }
    float rr = sqrt(r2);
    vec2 dir = d / max(rr, 1e-4);
    col += vec3(0.3, 0.5, 1.0) * exp(-max(rr - 1.0, 0.0) * 70.0) * step(1.0, rr) * smoothstep(-0.2, 0.6, dot(vec3(dir.x, -dir.y, 0.0), sun)) * 0.35;
    col += (hash12(uv * 1931.0 + fract(time)) - 0.5) / 255.0;
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
