/* Unit tests for frame.h: where clicks land on a window's title bar and edges, and window zones. */
#include <stdio.h>
#include "../frame.h"

static int failures;
#define EXPECT(cond) do { if (!(cond)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

static void chrome_tests(const struct gs_chrome *c) {
	unsigned e;
	int w = 800, h = 500;
	int cy = c->title_h / 2;
	/* buttons on the right: close outermost, then minimise, then zoom (full screen) */
	EXPECT(gs_frame_hit(c, w, h, true, gs_button_cx(c, w, 0), cy, &e) == GS_PART_CLOSE);
	EXPECT(gs_frame_hit(c, w, h, true, gs_button_cx(c, w, 1), cy, &e) == GS_PART_MINIMIZE);
	EXPECT(gs_frame_hit(c, w, h, true, gs_button_cx(c, w, 2), cy, &e) == GS_PART_ZOOM);
	EXPECT(gs_button_cx(c, w, 0) > gs_button_cx(c, w, 1) && gs_button_cx(c, w, 1) > gs_button_cx(c, w, 2));
	EXPECT(gs_button_cx(c, w, 0) + c->d / 2 == w - c->margin);
	EXPECT(gs_button_cx(c, w, 0) - gs_button_cx(c, w, 1) == c->d + c->gap);
	EXPECT(gs_frame_hit(c, w, h, true, gs_button_cx(c, w, 2) - c->d - c->gap, cy, &e) == GS_PART_TITLE);
	EXPECT(gs_frame_hit(c, w, h, true, 30, cy, &e) == GS_PART_TITLE); /* left side is just title bar now */
	EXPECT(gs_frame_hit(c, w, h, true, 400, 10, &e) == GS_PART_TITLE);
	EXPECT(gs_frame_hit(c, w, h, true, 400, c->title_h, &e) == GS_PART_CONTENT);
	EXPECT(gs_frame_hit(c, w, h, true, 400, h + c->title_h - 1, &e) == GS_PART_CONTENT);
	EXPECT(gs_frame_hit(c, w, h, true, -3, 200, &e) == GS_PART_RESIZE && e == GS_EDGE_LEFT);
	EXPECT(gs_frame_hit(c, w, h, true, 803, h + c->title_h + 3, &e) == GS_PART_RESIZE && e == (GS_EDGE_RIGHT | GS_EDGE_BOTTOM));
	EXPECT(gs_frame_hit(c, w, h, true, 100, -2, &e) == GS_PART_RESIZE && e == GS_EDGE_TOP);
	EXPECT(gs_frame_hit(c, w, h, true, -20, 200, &e) == GS_PART_NONE);
	/* client-side decorations: no title bar, no outside resize grips */
	EXPECT(gs_frame_hit(c, w, h, false, gs_button_cx(c, w, 0), cy, &e) == GS_PART_CONTENT);
	EXPECT(gs_frame_hit(c, w, h, false, -3, 200, &e) == GS_PART_NONE);
	/* the title stays clear of the buttons */
	EXPECT(gs_buttons_left(c, w) < gs_button_cx(c, w, 2) - c->d / 2 + 1);
}

int main(void) {
	chrome_tests(&GS_CHROME_MAC);
	chrome_tests(&GS_CHROME_TOUCH);
	/* Mac look is macOS-sized; touch look is clearly bigger for fingers */
	EXPECT(GS_CHROME_MAC.d <= 14 && GS_CHROME_MAC.pill == 0);
	EXPECT(GS_CHROME_TOUCH.d >= 24 && GS_CHROME_TOUCH.title_h > GS_CHROME_MAC.title_h);

	/* zones */
	int b[4];
	gs_zone_box(GS_ZONE_LEFT, 0, 0, 1000, 800, 6, b);
	EXPECT(b[0] == 6 && b[1] == 6 && b[2] == 500 - 3 - 6 && b[3] == 800 - 12);
	gs_zone_box(GS_ZONE_RIGHT, 0, 0, 1000, 800, 6, b);
	EXPECT(b[0] == 503 && b[0] + b[2] == 994);
	gs_zone_box(GS_ZONE_FILL, 10, 20, 1000, 800, 6, b);
	EXPECT(b[0] == 10 && b[1] == 20 && b[2] == 1000 && b[3] == 800);
	gs_zone_box(GS_ZONE_BR, 0, 0, 1000, 800, 6, b);
	EXPECT(b[0] == 503 && b[1] == 403 && b[0] + b[2] == 994 && b[1] + b[3] == 794);
	gs_zone_box(GS_ZONE_CENTRE3, 0, 0, 900, 600, 6, b);
	EXPECT(b[0] == 303 && b[0] + b[2] == 597);
	gs_zone_box(GS_ZONE_LEFT23, 0, 0, 900, 600, 6, b);
	EXPECT(b[0] == 6 && b[0] + b[2] == 597);
	/* drags */
	EXPECT(gs_drag_zone(0, 0, 1920, 1080, 0, 500) == GS_ZONE_LEFT);
	EXPECT(gs_drag_zone(0, 0, 1920, 1080, 1919, 500) == GS_ZONE_RIGHT);
	EXPECT(gs_drag_zone(0, 0, 1920, 1080, 900, 0) == GS_ZONE_FILL);
	EXPECT(gs_drag_zone(0, 0, 1920, 1080, 0, 20) == GS_ZONE_TL);
	EXPECT(gs_drag_zone(0, 0, 1920, 1080, 1919, 1070) == GS_ZONE_BR);
	EXPECT(gs_drag_zone(0, 0, 1920, 1080, 900, 500) == GS_ZONE_NONE);
	if (failures == 0) {
		printf("all frame tests passed\n");
	}
	return failures ? 1 : 0;
}
