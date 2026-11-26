#version 440
// Gill(OS) live wallpaper "Flow": slow ribbons of light, like silk in water or the aurora,
// drifting and folding. Deep and glowing in Dark Mode, soft and pastel in Light Mode.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;   // seconds
    float aspect; // width / height
    float dark;   // 0 light mode .. 1 dark mode
    float hue;    // accent hue shift 0..1
};

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}
float noise3(vec3 x) {
    vec3 i = floor(x);
    vec3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    float a = mix(mix(hash12(i.xy + i.z * 37.0), hash12(i.xy + vec2(1, 0) + i.z * 37.0), f.x),
                  mix(hash12(i.xy + vec2(0, 1) + i.z * 37.0), hash12(i.xy + vec2(1, 1) + i.z * 37.0), f.x), f.y);
    float b = mix(mix(hash12(i.xy + (i.z + 1.0) * 37.0), hash12(i.xy + vec2(1, 0) + (i.z + 1.0) * 37.0), f.x),
                  mix(hash12(i.xy + vec2(0, 1) + (i.z + 1.0) * 37.0), hash12(i.xy + vec2(1, 1) + (i.z + 1.0) * 37.0), f.x), f.y);
    return mix(a, b, f.z);
}
float fbm(vec3 p) {
    float a = 0.5, s = 0.0;
    for (int i = 0; i < 4; i++) {
        s += a * noise3(p);
        p = p * 2.01 + vec3(3.1, 7.7, 1.3);
        a *= 0.5;
    }
    return s;
}
// no array constructors: older GPUs (GLSL ES 1.0) can't take them
vec3 ribbonTint(int i) {
    if (i == 0) return vec3(0.20, 0.85, 0.95);
    if (i == 1) return vec3(0.50, 0.35, 1.00);
    if (i == 2) return vec3(1.00, 0.40, 0.65);
    if (i == 3) return vec3(0.25, 0.55, 1.00);
    return vec3(0.65, 0.95, 0.85);
}

vec3 hueShift(vec3 c, float h) {
    // rotate the colour around the grey axis (accent colour shift)
    const vec3 k = vec3(0.57735);
    float a = h * 6.28318;
    return c * cos(a) + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - cos(a));
}

void main() {
    vec2 uv = qt_TexCoord0;
    float x = (uv.x - 0.5) * aspect, y = uv.y;
    float t = time * 0.05;
    // background: deep night blue, a little lighter at the top
    vec3 bg = mix(vec3(0.05, 0.06, 0.16), vec3(0.01, 0.012, 0.035), smoothstep(0.0, 1.0, y));
    vec3 add = vec3(0.0);
    // ribbons of light, each folding slowly at its own pace
    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float f = 0.9 + fi * 0.35;
        float base = 0.30 + fi * 0.085;
        float yc = base + 0.10 * sin(x * f + t * (0.6 + fi * 0.13) + fi * 1.7)
                        + 0.045 * sin(x * f * 2.3 - t * (0.9 + fi * 0.07) + fi * 4.1)
                        + 0.02 * (noise3(vec3(x * 1.5, fi * 3.0, t * 0.5)) - 0.5);
        float th = 0.035 + 0.025 * (0.5 + 0.5 * sin(x * 1.3 + t * 0.7 + fi));
        float d = (y - yc) / th;
        float glow = exp(-d * d * 0.5);
        float core = exp(-d * d * 6.0);
        // aurora curtains: faint vertical streaks rising from each ribbon
        float curtain = exp(-max(yc - y, 0.0) * 9.0) * step(y, yc) * (0.5 + 0.5 * noise3(vec3(x * 18.0, fi, t * 0.8)));
        vec3 tint = hueShift(ribbonTint(i), hue);
        add += tint * (glow * 0.35 + core * 0.35 + curtain * 0.10) * (0.75 + 0.25 * sin(x * 2.0 - t + fi));
    }
    vec3 col = 1.0 - exp(-(bg + add) * 1.4); // gentle tone curve: bright but never blown out
    col *= 1.0 - 0.25 * length(uv - vec2(0.5, 0.4));
    // light mode: the same ribbons as soft colour on a pale sky
    vec3 sky = mix(vec3(0.97, 0.975, 1.0), vec3(0.88, 0.91, 0.98), y);
    float ink = clamp(1.0 - exp(-dot(add, vec3(0.45)) * 1.6), 0.0, 1.0);
    vec3 hueOnly = add / (max(max(add.r, add.g), add.b) + 1e-3);
    vec3 lightCol = mix(sky, mix(hueOnly * 0.9, vec3(1.0), 0.25), ink * 0.75);
    col = mix(lightCol, col, dark);
    col += (hash12(uv * 1931.0 + fract(time)) - 0.5) / 255.0;
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
