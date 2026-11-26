#version 440
// Gill(OS) live wallpaper "Shore": looking straight down on a beach. Turquoise water rolls in in
// slow waves with white foam, sand on the other side; the light follows the real sun where you
// are, from bright noon to golden evening and a moonlit night.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float aspect;
    float dark;
    float sunElev;
    float sunX;
};

float hash12(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
float noise2(vec2 x) { vec2 i = floor(x), f = fract(x); f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y); }
float fbm(vec2 p) { float a = 0.5, s = 0.0; for (int i = 0; i < 5; i++) { s += a * noise2(p); p = p * 2.03 + 3.1; a *= 0.5; } return s; }

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 p = (uv - 0.5) * vec2(aspect, 1.0);
    float t = time;
    // the waterline: a wavy diagonal; water to the right, sand to the left
    float coast = p.x * 0.85 + p.y * 0.35 + (fbm(vec2(p.y * 2.0, 1.0)) - 0.5) * 0.25;
    float wave = sin(t * 0.35) * 0.025 + sin(t * 0.21 + 1.7) * 0.015;   // the swash moves in and out
    float s = coast - 0.05 - wave;                                          // < 0 sand, > 0 water
    // water colour: clear turquoise near the shore, deep blue further out
    vec3 shallow = vec3(0.30, 0.82, 0.80), deep = vec3(0.02, 0.24, 0.45);
    vec3 water = mix(shallow, deep, smoothstep(0.0, 0.45, s));
    // caustics and swell
    float swell = sin((coast * 22.0) - t * 0.9 + fbm(p * 3.0) * 3.0);
    water *= 0.92 + 0.08 * swell;
    water += vec3(0.9, 1.0, 1.0) * pow(fbm(p * 9.0 + vec2(t * 0.05, -t * 0.03)), 4.0) * 0.18 * smoothstep(0.3, 0.0, s);
    // foam: bands of breaking waves marching to the shore, and the lacy edge on the sand
    float band = sin(coast * 34.0 - t * 1.1);
    float foam = smoothstep(0.8, 1.0, band) * smoothstep(0.25, 0.02, s) * smoothstep(0.35, 0.65, fbm(p * 14.0 + vec2(t * 0.1, 0.0)));
    foam += smoothstep(0.03, 0.0, abs(s)) * smoothstep(0.4, 0.6, fbm(p * 22.0 + t * 0.05));
    vec3 sand = mix(vec3(0.86, 0.76, 0.60), vec3(0.95, 0.88, 0.74), fbm(p * 30.0));
    float wet = smoothstep(-0.08, 0.0, s);                                  // darker wet sand by the water
    sand = mix(sand, sand * 0.72, wet);
    vec3 col = s < 0.0 ? sand : mix(water, vec3(1.0), clamp(foam, 0.0, 1.0) * 0.9);
    col = mix(col, sand * 0.72, smoothstep(0.012, 0.0, s) * step(0.0, s) * 0.5);
    // light from the real sun: bright day, golden evening, moonlit night
    float e = sunElev;
    float day = smoothstep(-0.12, 0.3, e);
    float golden = exp(-pow((e - 0.04) / 0.13, 2.0));
    vec3 tint = mix(vec3(0.10, 0.14, 0.26), vec3(1.0), day);
    tint = mix(tint, vec3(1.08, 0.82, 0.62), golden * 0.7);
    col *= tint;
    col += (hash12(uv * 1931.0 + fract(time)) - 0.5) / 255.0;
    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0) * qt_Opacity;
}
