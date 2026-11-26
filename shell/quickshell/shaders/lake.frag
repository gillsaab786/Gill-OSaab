#version 440
// Gill(OS) live wallpaper "Lake": snowy peaks over a still alpine lake, under the real sky where
// you are (sun from your location and the clock). The water ripples and mirrors the sky; at
// night the stars come out over the mountains.
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

float hash11(float p) { p = fract(p * 0.1031); p *= p + 33.33; p *= p + p; return fract(p); }
float hash12(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
float noise1(float x) { float i = floor(x), f = fract(x); return mix(hash11(i), hash11(i + 1.0), f * f * (3.0 - 2.0 * f)); }
float noise2(vec2 x) { vec2 i = floor(x), f = fract(x); f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y); }
float ridged(float x, float seed) {
    float h = 0.0, a = 0.5, f = 1.0;
    for (int i = 0; i < 5; i++) { h += a * (1.0 - abs(noise1(x * f + seed) * 2.0 - 1.0)); a *= 0.5; f *= 2.05; }
    return h;
}

vec3 sky(float x, float y, float e, out vec3 hor) {
    float day = smoothstep(-0.10, 0.25, e);
    float golden = exp(-pow((e - 0.03) / 0.12, 2.0));
    vec3 zen = mix(vec3(0.01, 0.015, 0.05), vec3(0.16, 0.38, 0.75), day);
    hor = mix(vec3(0.05, 0.07, 0.15), vec3(0.72, 0.84, 0.95), day);
    hor = mix(hor, vec3(1.0, 0.6, 0.38), golden * 0.8);
    zen = mix(zen, vec3(0.24, 0.22, 0.45), golden * 0.45);
    return mix(zen, hor, pow(smoothstep(0.0, 0.56, y), 1.4));
}

// the scene above the waterline (y < 0.56)
vec3 land(float x, float y, float e, vec3 hor) {
    float day = smoothstep(-0.10, 0.25, e);
    float night = 1.0 - smoothstep(-0.2, 0.0, e);
    float golden = exp(-pow((e - 0.03) / 0.12, 2.0));
    vec3 c = sky(x, y, e, hor);
    vec2 g = vec2(x, y) * 160.0; float h = hash12(floor(g));
    c += step(0.987, h) * smoothstep(0.12, 0.0, length(fract(g) - 0.5)) * night * 0.85;
    vec2 sp = vec2(sunX * 0.4 * aspect, 0.42 - e * 0.75);
    float sd = length(vec2(x, y) - sp);
    c += vec3(1.0, 0.86, 0.62) * smoothstep(0.028, 0.022, sd) * step(-0.04, e);
    c += vec3(1.0, 0.62, 0.36) * exp(-sd * 7.0) * (0.2 + golden * 0.6) * step(-0.25, e);
    // far range (blue, hazy), main peaks (snow), forested foothills
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float fx = x * (1.1 + fi * 0.8) + fi * 5.0;
        float hgt = ridged(fx, fi * 11.0);
        float top = 0.50 - hgt * (0.40 - fi * 0.15) + fi * 0.035;
        if (y > top) {
            float slope = (ridged(fx + 0.04, fi * 11.0) - ridged(fx - 0.04, fi * 11.0)) / 0.08;
            float facing = clamp(0.55 - slope * 0.6 * sunX, 0.15, 1.0);
            vec3 rock = mix(vec3(0.40, 0.44, 0.52), vec3(0.09, 0.15, 0.11), fi / 2.0);
            // snow on the high parts of the far and main ranges
            float alt = (0.50 - y) / 0.40;
            float snow = smoothstep(0.38, 0.5, alt + (noise2(vec2(x * 25.0, y * 25.0)) - 0.5) * 0.18) * (1.0 - fi * 0.5);
            vec3 m = mix(rock, vec3(0.94, 0.96, 1.0), snow);
            // rock texture: gullies and ledges so faces don't look like stripes
            float tex = noise2(vec2(x * 40.0, y * 90.0)) * 0.5 + noise2(vec2(x * 9.0 + y * 6.0, y * 20.0)) * 0.5;
            m *= (0.4 + 0.75 * mix(facing, tex, 0.45)) * (0.10 + 0.95 * day);
            m += vec3(1.0, 0.5, 0.3) * golden * snow * 0.4 * facing;
            m = mix(m, hor * mix(0.9, 0.45, night), (2.0 - fi) / 2.0 * 0.40);
            c = m;
        }
    }
    return c;
}

void main() {
    vec2 uv = qt_TexCoord0;
    float x = (uv.x - 0.5) * aspect, y = uv.y;
    float water = 0.56;
    vec3 hor;
    vec3 col;
    if (y < water) {
        col = land(x, y, sunElev, hor);
    } else {
        // reflection with ripples, darker and bluer
        float d = y - water;
        float rip = sin(d * 260.0 / (d + 0.08) - time * 1.2 + noise2(vec2(x * 8.0, d * 40.0)) * 4.0) * 0.004 * (d * 3.0 + 0.2);
        col = land(x + rip, water - d * 0.9, sunElev, hor) * vec3(0.55, 0.65, 0.75);
        col += vec3(0.6, 0.7, 0.8) * pow(noise2(vec2(x * 60.0, d * 300.0 - time * 0.6)), 6.0) * 0.12 * smoothstep(-0.1, 0.3, sunElev);
        // pebbly shore at the very bottom
        float shore = smoothstep(0.93, 0.97, y + noise2(vec2(x * 12.0, 0.0)) * 0.02);
        col = mix(col, vec3(0.16, 0.15, 0.13) * (0.2 + 0.8 * smoothstep(-0.1, 0.25, sunElev)), shore);
    }
    col += (hash12(uv * 1931.0 + fract(time)) - 0.5) / 255.0;
    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0) * qt_Opacity;
}
