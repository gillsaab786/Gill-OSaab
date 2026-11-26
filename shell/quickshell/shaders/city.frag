#version 440
// Gill(OS) live wallpaper "City": a skyline under the real sky where you are (sun position from
// your location and the clock): sunrise glow, daylight, golden hour, then thousands of lit
// windows and a few blinking aircraft lights at night.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float aspect;
    float dark;
    float sunElev; // radians above the horizon (negative: below)
    float sunX;    // -1 left .. 1 right (where the sun is across the view)
};

float hash11(float p) { p = fract(p * 0.1031); p *= p + 33.33; p *= p + p; return fract(p); }
float hash12(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }

void main() {
    vec2 uv = qt_TexCoord0;
    float x = (uv.x - 0.5) * aspect, y = uv.y;
    float e = sunElev;
    float day = smoothstep(-0.10, 0.25, e);
    float golden = exp(-pow((e - 0.03) / 0.12, 2.0));
    float night = 1.0 - smoothstep(-0.20, 0.0, e);
    vec3 zen = mix(vec3(0.01, 0.015, 0.05), vec3(0.18, 0.40, 0.78), day);
    vec3 hor = mix(vec3(0.05, 0.06, 0.14), vec3(0.70, 0.80, 0.92), day);
    hor = mix(hor, vec3(1.0, 0.55, 0.30), golden * 0.85);
    zen = mix(zen, vec3(0.25, 0.20, 0.42), golden * 0.45);
    vec3 col = mix(zen, hor, pow(smoothstep(0.0, 0.72, y), 1.5));
    // city glow on the sky at night
    col += vec3(0.35, 0.18, 0.08) * night * pow(smoothstep(0.35, 0.72, y), 2.0) * 0.5;
    // stars
    vec2 g = vec2(x, y) * 150.0;
    float h = hash12(floor(g));
    col += step(0.988, h) * smoothstep(0.12, 0.0, length(fract(g) - 0.5)) * night * smoothstep(0.55, 0.1, y) * 0.8;
    // sun / moon disc
    vec2 sp = vec2(sunX * 0.42 * aspect, 0.70 - e * 0.9);
    float sd = length(vec2(x, y) - sp);
    col += vec3(1.0, 0.86, 0.62) * smoothstep(0.03, 0.024, sd) * step(-0.05, e);
    col += vec3(1.0, 0.6, 0.35) * exp(-sd * 7.0) * (0.25 + golden * 0.6) * step(-0.25, e);
    // three rows of towers, far to near
    for (int row = 0; row < 3; row++) {
        float fr = float(row);
        float depth = fr / 2.0;                       // 0 far .. 1 near
        float cell = 0.085 - fr * 0.012;
        float bx = x / cell + fr * 37.0;
        float id = floor(bx);
        float fx = fract(bx);
        float wfrac = 0.55 + 0.4 * hash11(id * 3.1 + fr);  // tower width within its lot
        float off = (1.0 - wfrac) * hash11(id * 5.7 + fr);
        float lx = (fx - off) / wfrac;                      // 0..1 across the tower
        float hgt = 0.08 + 0.30 * pow(hash11(id * 1.7 + fr), 1.8);
        if (hash11(id + 99.0 + fr) > 0.9) hgt += 0.14;     // a few skyscrapers
        float base = 0.90;
        float top = base - hgt * (0.55 + 0.45 * (1.0 - depth)) - (1.0 - depth) * 0.06;
        // stepped crowns on some towers
        if (hash11(id + 7.0) > 0.6 && (lx < 0.2 || lx > 0.8)) top += 0.025;
        if (y > top && lx >= 0.0 && lx <= 1.0) {
            vec3 wall = mix(vec3(0.42, 0.46, 0.54), vec3(0.17, 0.19, 0.25), depth);
            float lit = mix(0.78, 1.08, step(0.5, lx) * (0.5 + 0.5 * sunX) + step(lx, 0.5) * (0.5 - 0.5 * sunX));
            vec3 c = wall * lit * (0.22 + 0.9 * day) + vec3(0.55, 0.32, 0.2) * golden * 0.22 * (1.0 - depth * 0.5);
            // windows: a grid on each tower, lit at random at night
            vec2 wg = vec2(lx * (5.0 + floor(hash11(id) * 4.0)), (y - top) * (95.0 - fr * 20.0));
            vec2 wid = floor(wg);
            float win = step(0.22, fract(wg.x)) * step(fract(wg.x), 0.78) * step(0.3, fract(wg.y)) * step(fract(wg.y), 0.78);
            float on = step(0.62, hash12(wid + id * 13.1 + fr * 7.0));
            float flick = 0.8 + 0.2 * sin(time * (0.2 + hash12(wid + id)) + id);
            c += win * on * vec3(1.0, 0.76, 0.42) * night * 0.95 * flick;
            c *= 1.0 - win * 0.08 * day;                       // windows read as glass in the day
            c = mix(c, hor * 0.85, (1.0 - depth) * 0.42 * (0.5 + 0.5 * day));
            if (hgt > 0.36 && y < top + 0.005 && abs(lx - 0.5) < 0.1)
                c += vec3(1.0, 0.12, 0.1) * step(0.6, fract(time * 0.5 + id * 0.37)) * night;
            col = c;
        }
    }
    // water in front, reflecting the lights
    if (y > 0.90) {
        vec3 refl = mix(hor * 0.4, vec3(1.0, 0.7, 0.4) * night * 0.25, 0.5);
        refl *= 0.7 + 0.3 * sin(y * 300.0 + time * 0.8 + x * 8.0);
        col = mix(vec3(0.03, 0.05, 0.08), refl, 0.6) * (0.5 + 0.5 * day) + vec3(0.02, 0.03, 0.05);
    }
    col += (hash12(uv * 1931.0 + fract(time)) - 0.5) / 255.0;
    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0) * qt_Opacity;
}
