/* Unit tests for the Mission Control layout. */
#include <stdio.h>
#include "../anim.h"
#include "../overview.h"

static int failures;
#define EXPECT(c) do { if (!(c)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); failures++; } } while (0)

int main(void) {
	struct gs_slot s[9];
	int w1[] = { 800 }, h1[] = { 500 };
	gs_overview_layout(1, w1, h1, 0, 0, 1920, 1080, s);
	EXPECT(s[0].scale == 1.0 && s[0].cx == 960 && s[0].cy == 540); /* one small window: centred, not enlarged */

	int w4[] = { 1920, 1920, 1000, 600 }, h4[] = { 1080, 1080, 700, 400 };
	gs_overview_layout(4, w4, h4, 0, 0, 1920, 1080, s);
	for (int i = 0; i < 4; i++) {
		EXPECT(s[i].scale > 0.2 && s[i].scale <= 1.0);
		double hw = w4[i] * s[i].scale / 2, hh = h4[i] * s[i].scale / 2;
		EXPECT(s[i].cx - hw >= 0 && s[i].cx + hw <= 1920 && s[i].cy - hh >= 0 && s[i].cy + hh <= 1080);
		for (int j = 0; j < i; j++) { /* no two windows overlap */
			double hw2 = w4[j] * s[j].scale / 2, hh2 = h4[j] * s[j].scale / 2;
			int apart = s[i].cx + hw <= s[j].cx - hw2 || s[j].cx + hw2 <= s[i].cx - hw ||
				s[i].cy + hh <= s[j].cy - hh2 || s[j].cy + hh2 <= s[i].cy - hh;
			EXPECT(apart);
		}
	}
	int w3[] = { 900, 900, 900 }, h3[] = { 600, 600, 600 };
	gs_overview_layout(3, w3, h3, 0, 30, 1920, 960, s);
	EXPECT(s[0].cy >= 30);

	EXPECT(gs_ease_in_out_cubic(0) == 0 && gs_ease_in_out_cubic(1) == 1);
	EXPECT(gs_ease_in_out_cubic(0.5) > 0.49 && gs_ease_in_out_cubic(0.5) < 0.51);
	EXPECT(gs_lerp(10, 20, 0.25) == 12.5);
	if (!failures) {
		printf("all overview tests passed\n");
	}
	return failures ? 1 : 0;
}
