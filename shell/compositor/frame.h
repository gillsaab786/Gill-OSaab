/* Window frame geometry for gosaab-wm (pure functions, unit-tested). */
#ifndef GOSAAB_FRAME_H
#define GOSAAB_FRAME_H

#include <stdbool.h>

/* Title bar and traffic-light sizes. Two looks:
 *  - Mac: macOS-sized buttons (14 px) in a 32 px title bar, for mouse and touchpad
 *  - touch: big buttons in a Liquid Glass pill, for fingers, for a while after the screen is touched
 * The buttons sit on the RIGHT of the title bar, close outermost: [zoom] [minimise] [close]. */
struct gs_chrome {
	int title_h; /* title bar height */
	int d;       /* button diameter */
	int gap;     /* space between buttons */
	int margin;  /* frame's right edge to the close button's right edge */
	int pill;    /* glass pill padding around the buttons (0: no pill, like macOS) */
};

static const struct gs_chrome GS_CHROME_MAC = { 32, 14, 8, 13, 0 };
static const struct gs_chrome GS_CHROME_TOUCH = { 48, 26, 14, 16, 7 };

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

static inline int gs_title_height(const struct gs_chrome *c, bool ssd) {
	return ssd ? c->title_h : 0;
}

/* x of the centre of traffic-light button i (0 close, 1 minimise, 2 zoom) in a frame w wide:
 * close at the right edge, then minimise, then zoom (full screen) to its left */
static inline int gs_button_cx(const struct gs_chrome *c, int w, int i) {
	return w - c->margin - c->d / 2 - i * (c->d + c->gap);
}

/* the strip holding the three buttons (frame-local x range), e.g. to keep the title clear of it */
static inline int gs_buttons_left(const struct gs_chrome *c, int w) {
	return gs_button_cx(c, w, 2) - c->d / 2 - c->pill;
}

/* Which part of a frame (width w, content height h, server-side title bar or not) is at
 * frame-local point (x, y). Points just outside the frame return GS_PART_RESIZE with *edges set. */
static inline enum gs_frame_part gs_frame_hit(const struct gs_chrome *c, int w, int h, bool ssd,
		double x, double y, unsigned *edges) {
	int th = gs_title_height(c, ssd);
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
		/* each button owns the space up to halfway to the next: easy to hit, no dead gaps */
		double dx = x - gs_button_cx(c, w, i);
		double half = c->d / 2.0 + c->gap / 2.0;
		if (dx >= -half && dx < half && y >= cy - half - 2 && y <= cy + half + 2) {
			return (enum gs_frame_part)(GS_PART_CLOSE + i);
		}
	}
	return GS_PART_TITLE;
}

/* ---- window layouts: halves, quarters, thirds (the green button's menu, drags, Super+arrows) */
enum gs_zone {
	GS_ZONE_NONE, GS_ZONE_LEFT, GS_ZONE_RIGHT, GS_ZONE_FILL, GS_ZONE_TOP, GS_ZONE_BOTTOM,
	GS_ZONE_TL, GS_ZONE_TR, GS_ZONE_BL, GS_ZONE_BR,
	GS_ZONE_LEFT3, GS_ZONE_CENTRE3, GS_ZONE_RIGHT3, GS_ZONE_LEFT23, GS_ZONE_RIGHT23,
	GS_ZONE_COUNT,
};

/* The zone as fractions of the usable screen: x0, y0, x1, y1. */
static inline void gs_zone_frac(int zone, double f[4]) {
	static const double t[GS_ZONE_COUNT][4] = {
		{ 0, 0, 1, 1 }, { 0, 0, 0.5, 1 }, { 0.5, 0, 1, 1 }, { 0, 0, 1, 1 }, { 0, 0, 1, 0.5 }, { 0, 0.5, 1, 1 },
		{ 0, 0, 0.5, 0.5 }, { 0.5, 0, 1, 0.5 }, { 0, 0.5, 0.5, 1 }, { 0.5, 0.5, 1, 1 },
		{ 0, 0, 1 / 3.0, 1 }, { 1 / 3.0, 0, 2 / 3.0, 1 }, { 2 / 3.0, 0, 1, 1 }, { 0, 0, 2 / 3.0, 1 }, { 1 / 3.0, 0, 1, 1 },
	};
	int z = zone >= 0 && zone < GS_ZONE_COUNT ? zone : 0;
	for (int i = 0; i < 4; i++) {
		f[i] = t[z][i];
	}
}

/* The zone's box inside an area (ax, ay, aw, ah) with a small gap between windows and around the
 * edges (none for Fill). Writes x, y, w, h. */
static inline void gs_zone_box(int zone, int ax, int ay, int aw, int ah, int gap, int out[4]) {
	double f[4];
	gs_zone_frac(zone, f);
	if (zone == GS_ZONE_FILL || zone == GS_ZONE_NONE) {
		gap = 0;
	}
	int x0 = ax + (int)(aw * f[0] + 0.5) + (f[0] == 0 ? gap : gap / 2);
	int y0 = ay + (int)(ah * f[1] + 0.5) + (f[1] == 0 ? gap : gap / 2);
	int x1 = ax + (int)(aw * f[2] + 0.5) - (f[2] == 1 ? gap : gap - gap / 2);
	int y1 = ay + (int)(ah * f[3] + 0.5) - (f[3] == 1 ? gap : gap - gap / 2);
	out[0] = x0;
	out[1] = y0;
	out[2] = x1 - x0;
	out[3] = y1 - y0;
}

/* Where a window dragged to (x, y) on a screen (ax, ay, aw, ah) will land:
 * left/right edge -> half, near a corner -> quarter, top edge -> fill. */
static inline int gs_drag_zone(int ax, int ay, int aw, int ah, double x, double y) {
	bool left = x <= ax + 4, right = x >= ax + aw - 5, top = y <= ay + 4, bottom = y >= ay + ah - 5;
	double corner = ah * 0.18;
	if (left || right) {
		if (y <= ay + corner) return left ? GS_ZONE_TL : GS_ZONE_TR;
		if (y >= ay + ah - corner) return left ? GS_ZONE_BL : GS_ZONE_BR;
		return left ? GS_ZONE_LEFT : GS_ZONE_RIGHT;
	}
	if (top) {
		if (x <= ax + aw * 0.12) return GS_ZONE_TL;
		if (x >= ax + aw * 0.88) return GS_ZONE_TR;
		return GS_ZONE_FILL;
	}
	(void)bottom;
	return GS_ZONE_NONE;
}

#endif
