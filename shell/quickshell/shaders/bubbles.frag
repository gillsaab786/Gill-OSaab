#version 440
// Gill(OS) live wallpaper "Bubbles": big soft glass bubbles in bright colours drifting and gently
// merging, over a clean pastel (Light) or deep (Dark) background.
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
vec3 bubbleColour(int i) {
    if (i == 0) return vec3(1.00, 0.42, 0.36);
    if (i == 1) return vec3(0.25, 0.62, 1.00);
    if (i == 2) return vec3(0.44, 0.89, 0.67);
    if (i == 3) return vec3(1.00, 0.78, 0.25);
    if (i == 4) return vec3(0.68, 0.46, 1.00);
    return vec3(0.30, 0.85, 0.95);
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 p = (uv - 0.5) * vec2(aspect, 1.0);
    float t = time * 0.05;
    vec3 bgLight = mix(vec3(0.97, 0.96, 0.95), vec3(0.92, 0.93, 0.97), uv.y);
    vec3 bgDark = mix(vec3(0.05, 0.05, 0.09), vec3(0.015, 0.015, 0.03), uv.y);
    vec3 col = mix(bgLight, bgDark, dark);
    // metaball field: bubbles that melt together where they touch
    for (int i = 0; i < 6; i++) {
        float fi = float(i);
        vec2 c = vec2(sin(t * (0.6 + fi * 0.13) + fi * 2.1) * 0.55 * aspect * 0.5,
                      cos(t * (0.5 + fi * 0.11) + fi * 1.3) * 0.32);
        float r = 0.15 + 0.08 * fract(sin(fi * 12.9) * 43.7);
        vec2 q = (p - c) / r;
        float d = length(q);
        vec3 bc = bubbleColour(i);
        // soft shadow under the bubble
        float sh = smoothstep(1.25, 0.6, length(q - vec2(0.12, 0.22)));
        col = mix(col, col * mix(0.82, 0.55, dark), sh * (1.0 - smoothstep(0.98, 1.0, 1.0 - d)) * 0.45);
        float inside = smoothstep(1.0, 0.985, d);
        // a glossy sphere: lit from the upper left, deeper colour towards the edge, bright rim
        float z = sqrt(max(1.0 - d * d, 0.0));
        vec3 n = vec3(q.x, -q.y, z);
        float diff = 0.55 + 0.45 * max(dot(n, normalize(vec3(-0.5, 0.6, 0.65))), 0.0);
        vec3 ball = bc * diff * mix(0.92, 1.0, z);
        ball += vec3(1.0) * pow(max(dot(n, normalize(vec3(-0.35, 0.45, 0.85))), 0.0), 40.0) * 0.8;
        ball += bc * pow(1.0 - z, 3.0) * 0.35;
        col = mix(col, ball, inside);
    }
    col += (hash12(uv * 1931.0 + fract(time)) - 0.5) / 255.0;
    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0) * qt_Opacity;
}
