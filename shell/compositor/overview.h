/* Mission Control layout for gosaab-wm (pure function, unit-tested).
 * Places n windows in a tidy grid inside an area, never enlarging them. */
#ifndef GOSAAB_OVERVIEW_H
#define GOSAAB_OVERVIEW_H

#include <math.h>

struct gs_slot {
	double cx, cy;  /* centre of the window in the overview */
	double scale;   /* <= 1 */
};

static inline void gs_overview_layout(int n, const int *w, const int *h,
		int ax, int ay, int aw, int ah, struct gs_slot *out) {
	if (n <= 0) {
		return;
	}
	/* pick the column count that wastes the least space for this screen's shape */
	int best_cols = 1;
	double best_score = -1;
	for (int cols = 1; cols <= n; cols++) {
		int rows = (n + cols - 1) / cols;
		double cw = (double)aw / cols, ch = (double)ah / rows;
		double score = 0;
		for (int i = 0; i < n; i++) {
			double s = fmin(1.0, fmin(cw * 0.86 / (w[i] > 0 ? w[i] : 1), ch * 0.86 / (h[i] > 0 ? h[i] : 1)));
			score += s * s * w[i] * h[i];
		}
		if (score > best_score + 1e-6) {
			best_score = score;
			best_cols = cols;
		}
	}
	int cols = best_cols, rows = (n + cols - 1) / cols;
	double cw = (double)aw / cols, ch = (double)ah / rows;
	for (int i = 0; i < n; i++) {
		int r = i / cols, c = i % cols;
		int in_row = (r == rows - 1) ? n - r * cols : cols; /* centre a short last row */
		double row_x = ax + (aw - in_row * cw) / 2.0;
		out[i].cx = row_x + c * cw + cw / 2.0;
		out[i].cy = ay + r * ch + ch / 2.0;
		out[i].scale = fmin(1.0, fmin(cw * 0.86 / (w[i] > 0 ? w[i] : 1), ch * 0.86 / (h[i] > 0 ? h[i] : 1)));
	}
}

#endif
