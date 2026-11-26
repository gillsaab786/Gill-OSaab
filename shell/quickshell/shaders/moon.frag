#version 440
// Gill(OS) live wallpaper "Moon": tonight's moon, in its real phase (from the date), over a
// slowly turning field of stars. Procedural craters and seas (no photos).
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;   // seconds
    float aspect; // width / height
    float phase;  // 0 new moon .. pi full .. 2 pi
    float dark;   // 0 light mode .. 1 dark mode
};

float hash13(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.zyx + 31.32);
    return fract((p.x + p.y) * p.z);
}
float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}
vec3 hash33(vec3 p) {
    p = fract(p * vec3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return fract((p.xxy + p.yxx) * p.zyx);
}
float noise3(vec3 x) {
    vec3 i = floor(x);
    vec3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x),
                   mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
               mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x),
                   mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float fbm(vec3 p, int octaves) {
    float a = 0.5, s = 0.0;
    for (int i = 0; i < 6; i++) {
        if (i >= octaves) break;
        s += a * noise3(p);
        p = p * 2.03 + vec3(7.1, 3.3, 11.9);
        a *= 0.5;
    }
    return s;
}
// craters: bowls with raised rims, scattered on cells over the sphere
float craters(vec3 p, float scale, float density) {
    vec3 g = p * scale;
    vec3 i = floor(g);
    float h = 0.0;
    for (int z = -1; z <= 1; z++)
    for (int y = -1; y <= 1; y++)
    for (int x = -1; x <= 1; x++) {
        vec3 cell = i + vec3(x, y, z);
        vec3 r = hash33(cell);
        if (r.z > density) continue;
        vec3 c = cell + r;
        float rad = 0.18 + 0.32 * hash13(cell + 5.0);
        float d = length(g - c) / rad;
        float bowl = -smoothstep(1.0, 0.0, d) * 0.9;
        float rim = exp(-pow((d - 1.0) / 0.22, 2.0)) * 0.35;
        h += (bowl + rim) * step(d, 2.0);
    }
    return h;
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 p = (uv - 0.5) * vec2(aspect, 1.0);
    vec3 col = mix(vec3(0.006, 0.008, 0.02), vec3(0.015, 0.02, 0.045), smoothstep(0.6, -0.6, p.y));
    // stars, turning very slowly around a point off screen
    float a = time * 0.0015;
    vec2 sp = mat2(cos(a), -sin(a), sin(a), cos(a)) * (p - vec2(-0.9, -0.8));
    for (int layer = 0; layer < 3; layer++) {
        float scale = 80.0 + float(layer) * 75.0;
        vec2 g = sp * scale;
        vec2 id = floor(g);
        float h = hash12(id + float(layer) * 51.0);
        if (h > 0.962) {
            vec2 cc = vec2(hash12(id + 1.7), hash12(id + 4.2));
            float d = length(fract(g) - cc);
            float tw = 0.6 + 0.4 * sin(time * (0.5 + 2.0 * h) + h * 60.0);
            col += smoothstep(0.1, 0.0, d) * (h - 0.962) * 26.0 * tw * mix(vec3(0.75, 0.82, 1.0), vec3(1.0, 0.92, 0.8), h);
        }
    }
    // the moon, up and to the right of centre
    vec2 c = vec2(0.22 * aspect, -0.12);
    float R = 0.22;
    vec2 d = (p - c) / R;
    float r2 = dot(d, d);
    float rr = sqrt(r2);
    vec3 sun = vec3(sin(phase), 0.08, -cos(phase)); // full moon: the sun is behind us
    sun = normalize(sun);
    if (r2 < 1.0) {
        vec3 n = vec3(d.x, -d.y, sqrt(1.0 - r2));
        float lib = sin(time * 0.01) * 0.05; // a hint of libration
        vec3 w = vec3(n.x * cos(lib) + n.z * sin(lib), n.y, -n.x * sin(lib) + n.z * cos(lib));
        // seas (darker, smooth) and highlands
        float maria = smoothstep(0.47, 0.60, fbm(w * 1.05 + 3.0, 5));
        float hgt = craters(w, 4.0, 0.33) * 0.6 + craters(w, 10.0, 0.26 * (1.0 - maria * 0.7)) * 0.4
                  + craters(w, 24.0, 0.22) * 0.25;
        hgt += (fbm(w * 14.0, 5) - 0.5) * 0.5;
        // bump the normal with the height field
        float e = 0.004;
        vec3 tx = normalize(cross(w, vec3(0.0, 1.0, 0.0)) + 1e-4);
        vec3 ty = cross(w, tx);
        float hx = craters(w + tx * e, 10.0, 0.26) - craters(w - tx * e, 10.0, 0.26);
        float hy = craters(w + ty * e, 10.0, 0.26) - craters(w - ty * e, 10.0, 0.26);
        float ndl0 = dot(n, sun);
        // bumps only show near the line between light and dark, as on the real moon
        float grazing = 1.0 - smoothstep(0.0, 0.6, ndl0);
        vec3 bn = normalize(n - (tx * hx + ty * hy) * (0.4 + 1.6 * grazing));
        float speck = fbm(w * 22.0, 3);
        vec3 albedo = mix(vec3(0.70, 0.69, 0.66), vec3(0.30, 0.31, 0.33), maria);
        albedo *= 0.92 + 0.32 * clamp(hgt, -0.7, 0.7) + 0.16 * (speck - 0.5); // bright rims, darker floors
        float ndl = dot(bn, sun);
        float lit = smoothstep(-0.06, 0.22, ndl) * pow(max(ndl0 + 0.04, 0.0), 0.4);
        vec3 moon = albedo * (lit * 1.2 + 0.006); // earthshine: the dark part just visible
        float edge = smoothstep(1.0, 0.985, rr);
        col = mix(col, moon, edge);
    }
    // soft halo, brighter the fuller the moon
    float full = 0.5 - 0.5 * cos(phase);
    col += vec3(0.55, 0.62, 0.75) * exp(-max(rr - 1.0, 0.0) * 5.5) * 0.10 * full * step(1.0, rr);
    col += (hash12(uv * 1931.0 + fract(time)) - 0.5) / 255.0;
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
