#version 440
// Gill(OS) live wallpaper "Earth": our planet from orbit with the real day and night.
// The sun's position comes from the clock (UTC), the side facing you from your time zone,
// so the line between day and night moves through the day; city lights come on at night and the
// clouds drift. Everything is procedural (no photos).
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;    // seconds, for drifting clouds and twinkling stars
    float aspect;  // width / height
    float sunLon;  // radians: longitude where the sun is overhead now
    float sunLat;  // radians: the sun's declination (season)
    float viewLon; // radians: longitude facing you
    float dark;    // 0 light mode .. 1 dark mode
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
    for (int i = 0; i < 7; i++) {
        if (i >= octaves) break;
        s += a * noise3(p);
        p = p * 2.02 + vec3(17.1, 9.2, 4.7);
        a *= 0.5;
    }
    return s;
}
mat3 rotY(float a) { float c = cos(a), s = sin(a); return mat3(c, 0, -s, 0, 1, 0, s, 0, c); }
mat3 rotX(float a) { float c = cos(a), s = sin(a); return mat3(1, 0, 0, 0, c, s, 0, -s, c); }

vec3 stars(vec2 uv) {
    vec3 col = vec3(0.0);
    for (int layer = 0; layer < 3; layer++) {
        float scale = 90.0 + float(layer) * 70.0;
        vec2 g = uv * scale;
        vec2 id = floor(g);
        float h = hash12(id + float(layer) * 37.0);
        if (h > 0.965) {
            vec2 c = vec2(hash12(id + 1.3), hash12(id + 7.1));
            float d = length(fract(g) - c);
            float tw = 0.65 + 0.35 * sin(time * (0.6 + h * 2.0) + h * 40.0);
            float b = smoothstep(0.09, 0.0, d) * (h - 0.965) * 28.0 * tw;
            col += b * mix(vec3(0.7, 0.8, 1.0), vec3(1.0, 0.9, 0.75), hash12(id + 3.7));
        }
    }
    return col;
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 p = (uv - 0.5) * vec2(aspect, 1.0);
    // space: deep blue-black with a faint glow
    vec3 col = mix(vec3(0.004, 0.006, 0.016), vec3(0.012, 0.02, 0.05), smoothstep(0.9, -0.2, p.y));
    col += stars(p);
    // the planet: big, low and to the right, so its curve sweeps across the screen
    vec2 c = vec2(0.12 * aspect, 0.58);
    float R = 0.66;
    vec2 d = (p - c) / R;
    float r2 = dot(d, d);
    mat3 M = rotY(viewLon) * rotX(-0.32); // view -> Earth, tilted so more of the globe shows
    vec3 sunW = vec3(cos(sunLat) * sin(sunLon), sin(sunLat), cos(sunLat) * cos(sunLon));
    vec3 sunV = transpose(M) * sunW; // sun direction seen from here
    float rr = sqrt(r2);
    if (r2 < 1.0) {
        vec3 n = vec3(d.x, -d.y, sqrt(1.0 - r2)); // view-space normal
        vec3 w = M * n;                           // point on Earth (unit vector)
        float lat = asin(clamp(w.y, -1.0, 1.0));
        // continents and their colours
        vec3 q = w * 1.6;
        float h = fbm(q + fbm(q * 2.0, 3) * 0.6, 7);
        float land = smoothstep(0.492, 0.505, h);
        float shore = smoothstep(0.45, 0.492, h) * (1.0 - land);
        float alat = abs(lat);
        float dry = smoothstep(0.45, 0.65, fbm(w * 3.0 + 11.0, 4)) * smoothstep(0.75, 0.25, abs(alat - 0.42));
        vec3 green = mix(vec3(0.10, 0.20, 0.07), vec3(0.20, 0.27, 0.11), fbm(w * 9.0, 3));
        vec3 desert = mix(vec3(0.52, 0.40, 0.24), vec3(0.66, 0.53, 0.33), fbm(w * 7.0 + 3.0, 3));
        vec3 ground = mix(green, desert, dry);
        ground = mix(ground, vec3(0.30, 0.28, 0.24), smoothstep(0.62, 0.72, h)); // mountains
        float ice = smoothstep(1.12, 1.25, alat + (fbm(w * 5.0, 3) - 0.5) * 0.25);
        vec3 ocean = mix(vec3(0.006, 0.03, 0.10), vec3(0.02, 0.14, 0.26), shore);
        vec3 surf = mix(ocean, ground, land);
        surf = mix(surf, vec3(0.86, 0.9, 0.95), ice);
        // clouds: swirled, drifting
        vec3 cw = rotY(time * 0.0035) * w;
        float warp = fbm(cw * 2.2 + 5.0, 3);
        float cl = smoothstep(0.46, 0.74, fbm(cw * 3.4 + warp * 1.6, 6));
        cl = max(cl, smoothstep(0.86, 1.1, alat) * 0.35 * cl);
        // light: day, the soft orange edge of night, then city lights
        float ndl = dot(w, sunW);
        float day = smoothstep(-0.06, 0.25, ndl);
        vec3 lit = mix(surf, vec3(0.95, 0.97, 1.0), cl * 0.92) * (0.035 + 1.05 * day);
        lit += vec3(0.010, 0.016, 0.035) * (1.0 - day) * (0.4 + cl); // moonlit night side
        float spec = pow(max(dot(n, normalize(sunV + vec3(0.0, 0.0, 1.0))), 0.0), 70.0) * (1.0 - land) * (1.0 - cl) * day;
        lit += vec3(1.0, 0.92, 0.75) * spec * 0.9;
        float dusk = exp(-pow((ndl - 0.02) / 0.05, 2.0));
        lit += vec3(1.0, 0.42, 0.15) * dusk * 0.30 * (0.15 + 0.85 * cl);
        float city = smoothstep(0.55, 0.95, noise3(w * 140.0)) * smoothstep(0.45, 0.7, fbm(w * 10.0 + 2.0, 3));
        city *= land * (1.0 - ice) * (1.0 - cl * 0.8) * (1.0 - smoothstep(-0.12, 0.02, ndl));
        lit += vec3(1.0, 0.70, 0.36) * city * 1.6;
        // air: blue at the rim on the day side
        float rim = pow(1.0 - n.z, 2.6);
        lit += vec3(0.25, 0.5, 1.0) * rim * (0.15 + 0.85 * smoothstep(-0.2, 0.4, dot(n, sunV)));
        col = mix(col, lit, smoothstep(1.0, 0.996, rr));
    }
    // the glow of the atmosphere around the edge
    float outside = max(rr - 1.0, 0.0) * R;
    vec2 dir = rr > 0.0 ? d / rr : vec2(0.0);
    float side = smoothstep(-0.4, 0.6, dot(vec3(dir.x, -dir.y, 0.0), sunV));
    col += vec3(0.28, 0.55, 1.0) * exp(-outside * 38.0) * (0.25 + 0.75 * side) * step(1.0, rr) * 0.75;
    // gentle grain so the gradients never band
    col += (hash12(uv * 1931.0 + fract(time)) - 0.5) / 255.0;
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
