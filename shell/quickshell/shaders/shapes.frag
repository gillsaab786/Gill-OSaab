#version 440
// Gill(OS) live wallpaper "Shapes": soft clay-like 3D shapes (a ring, a ribbed pill, a rounded
// cube and a ball) turning slowly in a calm, softly lit room. Pastel in Light, deep in Dark.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float aspect;
    float dark;
    float hue;
};

float hash12(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
mat2 rot(float a) { float c = cos(a), s = sin(a); return mat2(c, -s, s, c); }
float sdTorus(vec3 p, vec2 t) { vec2 q = vec2(length(p.xz) - t.x, p.y); return length(q) - t.y; }
float sdRoundBox(vec3 p, vec3 b, float r) { vec3 q = abs(p) - b; return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - r; }
float sdCapsule(vec3 p, float h, float r) { p.y -= clamp(p.y, -h, h); return length(p) - r; }

// returns distance; id in m (0 floor, 1 ring, 2 pill, 3 cube, 4 ball)
float scene(vec3 p, out float m) {
    float t = time * 0.25;
    float d = p.y + 1.0; m = 0.0;
    vec3 q = p - vec3(-1.55, -0.25, 0.4); q.xy = rot(0.5) * q.xy; q.xz = rot(t) * q.xz;
    float a = sdTorus(q, vec2(0.62, 0.22)); if (a < d) { d = a; m = 1.0; }
    q = p - vec3(0.15, -0.1, -0.2); q.xy = rot(0.35 + 0.2 * sin(t)) * q.xy; q.xz = rot(-t * 0.7) * q.xz;
    float ribs = 0.014 * sin(atan(q.z, q.x) * 14.0);
    a = sdCapsule(q, 0.55, 0.36) + ribs; if (a < d) { d = a; m = 2.0; }
    q = p - vec3(1.6, -0.45, 0.6); q.xz = rot(t * 0.8 + 0.6) * q.xz; q.yz = rot(0.4) * q.yz;
    a = sdRoundBox(q, vec3(0.36), 0.14); if (a < d) { d = a; m = 3.0; }
    q = p - vec3(0.9, -0.62 + 0.06 * sin(time * 0.6), -1.3);
    a = length(q) - 0.38; if (a < d) { d = a; m = 4.0; }
    return d;
}
float map(vec3 p) { float m; return scene(p, m); }
vec3 normalAt(vec3 p) {
    vec2 e = vec2(0.002, 0.0);
    return normalize(vec3(map(p + e.xyy) - map(p - e.xyy), map(p + e.yxy) - map(p - e.yxy), map(p + e.yyx) - map(p - e.yyx)));
}
float softShadow(vec3 ro, vec3 rd) {
    float res = 1.0, t = 0.03;
    for (int i = 0; i < 28; i++) {
        float h = map(ro + rd * t);
        res = min(res, 9.0 * h / t);
        t += clamp(h, 0.03, 0.4);
        if (res < 0.01 || t > 6.0) break;
    }
    return clamp(res, 0.0, 1.0);
}
vec3 shapeColour(float m) {
    vec3 light = m < 1.5 ? vec3(1.0, 0.55, 0.45) : m < 2.5 ? vec3(0.45, 0.62, 1.0) : m < 3.5 ? vec3(1.0, 0.82, 0.42) : vec3(0.48, 0.88, 0.7);
    return light;
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 p = (uv - 0.5) * vec2(aspect, 1.0);
    vec3 ro = vec3(0.0, 1.9, 7.4);
    vec3 rd = normalize(vec3(p.x, -p.y - 0.40, -1.75));
    vec3 bgL = vec3(0.93, 0.91, 0.90), bgD = vec3(0.07, 0.075, 0.11);
    vec3 bg = mix(bgL, bgD, dark);
    vec3 col = bg;
    float t = 0.0, m = 0.0;
    bool hit = false;
    for (int i = 0; i < 90; i++) {
        float d = scene(ro + rd * t, m);
        if (d < 0.001) { hit = true; break; }
        t += d * 0.85;
        if (t > 22.0) break;
    }
    if (hit) {
        vec3 pos = ro + rd * t;
        vec3 n = normalAt(pos);
        vec3 ld = normalize(vec3(-0.6, 0.9, 0.5));
        float sh = softShadow(pos + n * 0.01, ld);
        float dif = max(dot(n, ld), 0.0) * sh;
        float amb = 0.55 + 0.45 * n.y;
        float rim = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
        vec3 base = m < 0.5 ? bg * mix(1.0, 1.15, dark) : shapeColour(m);
        if (m > 0.5) base = mix(base, base * vec3(0.55, 0.6, 0.85), dark * 0.35);
        col = base * (0.35 * amb + 0.75 * dif);
        if (m > 0.5) col += vec3(1.0) * pow(max(dot(reflect(-ld, n), -rd), 0.0), 30.0) * 0.25 * sh + base * rim * 0.25;
        else col = mix(bg, col, 1.0) ; // floor shading only
        col = mix(col, bg, smoothstep(9.0, 20.0, t));
    }
    col += (hash12(uv * 1931.0 + fract(time)) - 0.5) / 255.0;
    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0) * qt_Opacity;
}
