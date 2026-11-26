#version 440
// Gill(OS) live wallpaper "Dunes": desert ridges under a sky that follows the real time of day:
// dawn glow, bright noon, golden evening, then a starry night. Sand drifts slowly off the crests.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;    // seconds
    float aspect;  // width / height
    float daytime; // 0..1 through the local day (0.5 = noon)
    float dark;    // 0 light mode .. 1 dark mode
};

float hash11(float p) { p = fract(p * 0.1031); p *= p + 33.33; p *= p + p; return fract(p); }
float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}
float noise1(float x) { float i = floor(x), f = fract(x); return mix(hash11(i), hash11(i + 1.0), f * f * (3.0 - 2.0 * f)); }
float noise2(vec2 x) {
    vec2 i = floor(x), f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y);
}
// a dune ridge: long smooth swells with a sharp crest
float ridge(float x, float seed) {
    float n = noise1(x * 0.9 + seed * 13.0);
    float h = pow(1.0 - abs(n * 2.0 - 1.0), 1.4) * 0.8;   // long swells with a sharp crest
    h += noise1(x * 2.3 + seed * 7.0) * 0.18;              // gentle unevenness
    h += noise1(x * 6.0 + seed * 3.0) * 0.03;
    return h;
}

void main() {
    vec2 uv = qt_TexCoord0;
    float x = (uv.x - 0.5) * aspect, y = uv.y;
    // the sun's height through the day: -1 midnight, 1 noon
    float t = daytime;
    float elev = -cos(t * 6.28318);
    float sunX = (t - 0.5) * 1.6 * aspect;
    float sunY = 0.62 - elev * 0.48;
    float dayAmt = smoothstep(-0.12, 0.35, elev);
    float golden = exp(-pow(elev / 0.22, 2.0));
    float night = 1.0 - smoothstep(-0.25, 0.02, elev);
    // sky
    vec3 zenith = mix(vec3(0.015, 0.025, 0.07), vec3(0.20, 0.42, 0.78), dayAmt);
    vec3 horizon = mix(vec3(0.05, 0.07, 0.16), vec3(0.72, 0.82, 0.92), dayAmt);
    horizon = mix(horizon, vec3(1.0, 0.55, 0.32), golden * 0.85);
    zenith = mix(zenith, vec3(0.28, 0.22, 0.42), golden * 0.5);
    vec3 col = mix(zenith, horizon, pow(smoothstep(0.0, 0.62, y), 1.6));
    // the sun (or its glow below the horizon)
    float sd = length(vec2(x - sunX, (y - sunY) * 1.0));
    col += vec3(1.0, 0.85, 0.6) * smoothstep(0.035, 0.028, sd) * step(-0.1, elev) * 1.2;
    col += vec3(1.0, 0.6, 0.35) * exp(-sd * 6.0) * (0.25 + golden * 0.5) * smoothstep(-0.3, 0.0, elev);
    // stars at night
    vec2 g = vec2(x, y) * 160.0;
    float h = hash12(floor(g));
    float star = step(0.985, h) * smoothstep(0.12, 0.0, length(fract(g) - 0.5)) * (0.6 + 0.4 * sin(time * 1.5 + h * 90.0));
    col += star * night * smoothstep(0.62, 0.1, y) * 0.9;
    // a faint band of the galaxy at night
    float band = exp(-pow((y - 0.25 + x * 0.25) / 0.12, 2.0)) * noise2(vec2(x, y) * 6.0);
    col += vec3(0.25, 0.25, 0.4) * band * night * 0.25;
    // dunes, far to near
    vec3 sand = mix(vec3(0.85, 0.55, 0.32), vec3(0.95, 0.72, 0.48), dayAmt);
    sand = mix(sand, vec3(0.95, 0.45, 0.22), golden * 0.6);
    vec3 nightSand = vec3(0.085, 0.10, 0.18);
    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float depth = fi / 4.0;                  // 0 far .. 1 near
        float drift = time * (0.0008 + depth * 0.0025);
        float scale = 1.2 + depth * 1.4;
        float base = 0.56 + depth * 0.15;
        float amp = 0.05 + depth * 0.075;
        float xs = x * scale + drift + fi * 3.7;
        float top = base - ridge(xs, fi) * amp;
        if (y > top) {
            // which side of the crest are we on? lit faces the sun
            float e = 0.04;
            float slope = (ridge(xs + e, fi) - ridge(xs - e, fi)) / (2.0 * e);
            float below = (y - top) / amp;                       // 0 at the crest, ~1 at the foot
            // the face toward the sun is lit; the slip face away from it falls into shadow
            float lightX = clamp(sunX / (0.8 * aspect), -1.0, 1.0); // sun to the left or right
            float toward = slope * lightX;
            // leeward faces sit in a soft shadow that fades down the dune (no hard columns)
            float shadow = smoothstep(0.05, -0.25, toward) * exp(-below * 2.2) * (0.35 + 0.65 * abs(lightX));
            vec3 lit = sand * (0.78 + 0.40 * exp(-below * 2.5));
            vec3 shade = mix(sand * 0.5, vec3(0.42, 0.33, 0.48) * 0.6, 0.4);
            vec3 c = mix(lit, shade, shadow);
            c *= 1.0 - smoothstep(0.2, 1.6, below) * 0.22;
            // wind ripples on the nearer dunes
            float rip = sin((xs * 220.0 + y * 900.0 * (0.4 + depth)) + noise2(vec2(xs * 8.0, y * 30.0)) * 6.0);
            c *= 1.0 + rip * 0.035 * depth;
            // crest glow and blowing sand
            float crest = exp(-(y - top) * (140.0 + depth * 200.0));
            c += vec3(1.0, 0.8, 0.6) * crest * 0.25 * dayAmt;
            float blow = noise2(vec2(xs * 30.0 - time * 0.4, y * 60.0)) * crest;
            c += vec3(1.0, 0.85, 0.7) * blow * 0.12 * (0.3 + dayAmt);
            // night: cool moonlit sand; distance: haze into the sky
            c = mix(c, nightSand * (1.0 - 0.4 * shadow), night * 0.92);
            c += vec3(0.35, 0.42, 0.65) * crest * 0.35 * night; // moonlit crests
            c = mix(c, horizon, (1.0 - depth) * 0.45 * (0.6 + 0.4 * dayAmt));
            // lower down a little darker (the Dock sits there)
            c *= 1.0 - smoothstep(0.75, 1.0, y) * 0.25;
            col = c;
        }
    }
    col += (hash12(uv * 1931.0 + fract(time)) - 0.5) / 255.0;
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
