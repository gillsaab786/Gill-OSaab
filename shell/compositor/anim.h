/* Animation timing and easing for gosaab-wm (header-only, unit-tested). */
#ifndef GOSAAB_ANIM_H
#define GOSAAB_ANIM_H

#include <math.h>
#include <stdbool.h>

struct gs_anim {
	double start_ms;
	double duration_ms;
	bool active;
};

static inline void gs_anim_start(struct gs_anim *a, double now_ms, double duration_ms) {
	a->start_ms = now_ms;
	a->duration_ms = duration_ms > 0 ? duration_ms : 1;
	a->active = true;
}

/* 0..1 progress, clamped */
static inline double gs_anim_progress(const struct gs_anim *a, double now_ms) {
	double p = (now_ms - a->start_ms) / a->duration_ms;
	return p < 0 ? 0 : (p > 1 ? 1 : p);
}

/* Critically damped spring (iOS/macOS feel): fast start, soft landing, no bounce.
 * Exactly 0 at 0 and 1 at 1. */
static inline double gs_ease_spring(double t) {
	if (t <= 0) {
		return 0;
	}
	if (t >= 1) {
		return 1;
	}
	const double w = 9.0;
	double v = 1.0 - (1.0 + w * t) * exp(-w * t);
	double end = 1.0 - (1.0 + w) * exp(-w);
	return v / end;
}

/* Used for closing: starts gently, accelerates away */
static inline double gs_ease_in_cubic(double t) {
	if (t <= 0) {
		return 0;
	}
	if (t >= 1) {
		return 1;
	}
	return t * t * t;
}

/* Minimise to the Dock: smooth start and stop */
static inline double gs_ease_in_out_cubic(double t) {
	if (t <= 0) {
		return 0;
	}
	if (t >= 1) {
		return 1;
	}
	return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2;
}

static inline double gs_lerp(double a, double b, double t) {
	return a + (b - a) * t;
}

#endif
