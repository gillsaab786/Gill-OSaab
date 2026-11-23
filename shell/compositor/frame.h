/* Window frame geometry for gosaab-wm (pure functions, unit-tested). */
#ifndef GOSAAB_FRAME_H
#define GOSAAB_FRAME_H

#include <stdbool.h>

/* Big enough for fingers on handheld touchscreens: 20 px buttons in a glass pill, 40 px title bar */
#define GS_TITLE_H 40
#define GS_BUTTON_D 20
#define GS_BUTTON_GAP 10
#define GS_BUTTON_X0 18
#define GS_PILL_PAD 6
#define GS_RESIZE_MARGIN 8

enum gs_frame_part {
	GS_PART_NONE,
	GS_PART_CONTENT,
	GS_PART_TITLE,
	GS_PART_CLOSE,
	GS_PART_MINIMIZE,
	GS_PART_ZOOM,
	GS_PART_RESIZE,
};

/* Edge bits match wlroots' WLR_EDGE_* values */
enum { GS_EDGE_TOP = 1, GS_EDGE_BOTTOM = 2, GS_EDGE_LEFT = 4, GS_EDGE_RIGHT = 8 };

static inline int gs_title_height(bool ssd) {
	return ssd ? GS_TITLE_H : 0;
}

/* x of the centre of traffic-light button i (0 close, 1 minimise, 2 zoom) */
static inline int gs_button_cx(int i) {
	return GS_BUTTON_X0 + GS_BUTTON_D / 2 + i * (GS_BUTTON_D + GS_BUTTON_GAP);
}

/* Which part of a frame (width w, content height h, server-side title bar or not) is at
 * frame-local point (x, y). Points just outside the frame return GS_PART_RESIZE with *edges set. */
static inline enum gs_frame_part gs_frame_hit(int w, int h, bool ssd, double x, double y,
		unsigned *edges) {
	int th = gs_title_height(ssd);
	int fh = h + th;
	*edges = 0;
	if (x < 0 || y < 0 || x >= w || y >= fh) {
		if (!ssd || x < -GS_RESIZE_MARGIN || y < -GS_RESIZE_MARGIN ||
				x >= w + GS_RESIZE_MARGIN || y >= fh + GS_RESIZE_MARGIN) {
			return GS_PART_NONE;
		}
		if (x < 0) *edges |= GS_EDGE_LEFT;
		if (x >= w) *edges |= GS_EDGE_RIGHT;
		if (y < 0) *edges |= GS_EDGE_TOP;
		if (y >= fh) *edges |= GS_EDGE_BOTTOM;
		return GS_PART_RESIZE;
	}
	if (y >= th) {
		return GS_PART_CONTENT;
	}
	double cy = th / 2.0;
	for (int i = 0; i < 3; i++) {
		double dx = x - gs_button_cx(i), dy = y - cy;
		double r = GS_BUTTON_D / 2.0 + GS_BUTTON_GAP / 2.0; /* the whole pill is a target: easy with a finger */
		if (dx * dx + dy * dy <= r * r) {
			return (enum gs_frame_part)(GS_PART_CLOSE + i);
		}
	}
	return GS_PART_TITLE;
}

#endif
