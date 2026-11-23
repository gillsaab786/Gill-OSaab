/* Unit tests for frame.h: where clicks land on a window's title bar and edges. */
#include <stdio.h>
#include "../frame.h"

static int failures;
#define EXPECT(cond) do { if (!(cond)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

int main(void) {
	unsigned e;
	int w = 800, h = 500; /* content height; frame height = 530 with a title bar */
	EXPECT(gs_frame_hit(w, h, true, gs_button_cx(0), 15, &e) == GS_PART_CLOSE);
	EXPECT(gs_frame_hit(w, h, true, gs_button_cx(1), 15, &e) == GS_PART_MINIMIZE);
	EXPECT(gs_frame_hit(w, h, true, gs_button_cx(2), 15, &e) == GS_PART_ZOOM);
	EXPECT(gs_frame_hit(w, h, true, gs_button_cx(2) + GS_BUTTON_D + GS_BUTTON_GAP, 15, &e) == GS_PART_TITLE);
	EXPECT(gs_frame_hit(w, h, true, 400, 10, &e) == GS_PART_TITLE);
	EXPECT(gs_frame_hit(w, h, true, 400, GS_TITLE_H, &e) == GS_PART_CONTENT);
	EXPECT(gs_frame_hit(w, h, true, 400, h + GS_TITLE_H - 1, &e) == GS_PART_CONTENT);
	EXPECT(gs_frame_hit(w, h, true, -3, 200, &e) == GS_PART_RESIZE && e == GS_EDGE_LEFT);
	EXPECT(gs_frame_hit(w, h, true, 803, h + GS_TITLE_H + 3, &e) == GS_PART_RESIZE && e == (GS_EDGE_RIGHT | GS_EDGE_BOTTOM));
	EXPECT(gs_frame_hit(w, h, true, 100, -2, &e) == GS_PART_RESIZE && e == GS_EDGE_TOP);
	EXPECT(gs_frame_hit(w, h, true, -20, 200, &e) == GS_PART_NONE);
	/* client-side decorations: no title bar, no outside resize grips */
	EXPECT(gs_frame_hit(w, h, false, gs_button_cx(0), 15, &e) == GS_PART_CONTENT);
	EXPECT(gs_frame_hit(w, h, false, -3, 200, &e) == GS_PART_NONE);
	/* buttons are evenly spaced and don't overlap */
	EXPECT(gs_button_cx(1) - gs_button_cx(0) == GS_BUTTON_D + GS_BUTTON_GAP);
	EXPECT(gs_button_cx(0) - GS_BUTTON_D / 2 == GS_BUTTON_X0);
	if (failures == 0) {
		printf("all frame tests passed\n");
	}
	return failures ? 1 : 0;
}
