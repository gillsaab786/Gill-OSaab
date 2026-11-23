/* Unit tests for gosaab-wm animation curves. */
#include <math.h>
#include <stdio.h>
#include "../anim.h"

static int failures = 0;
#define CHECK(cond, msg) do { if (!(cond)) { printf("FAIL: %s\n", msg); failures++; } } while (0)

int main(void) {
	CHECK(gs_ease_spring(0) == 0.0, "spring starts at 0");
	CHECK(fabs(gs_ease_spring(1) - 1.0) < 1e-9, "spring ends at 1");
	double prev = 0;
	for (int i = 1; i <= 100; i++) {
		double v = gs_ease_spring(i / 100.0);
		CHECK(v >= prev - 1e-12, "spring never goes backwards");
		CHECK(v <= 1.0 + 1e-9, "spring never overshoots");
		prev = v;
	}
	CHECK(gs_ease_spring(0.3) > 0.6, "spring is quick at the start (iOS feel)");
	CHECK(gs_ease_in_cubic(0.5) < 0.2, "close curve starts gently");
	CHECK(gs_ease_in_cubic(1.0) == 1.0, "close curve ends at 1");

	struct gs_anim a;
	gs_anim_start(&a, 1000, 200);
	CHECK(a.active, "animation active after start");
	CHECK(gs_anim_progress(&a, 900) == 0.0, "progress clamps below 0");
	CHECK(fabs(gs_anim_progress(&a, 1100) - 0.5) < 1e-9, "progress halfway");
	CHECK(gs_anim_progress(&a, 5000) == 1.0, "progress clamps above 1");
	gs_anim_start(&a, 0, 0);
	CHECK(gs_anim_progress(&a, 1) == 1.0, "zero duration finishes immediately");

	if (failures == 0) {
		printf("all animation tests passed\n");
	}
	return failures ? 1 : 0;
}
