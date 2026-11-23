#ifndef GOSAAB_TEXT_H
#define GOSAAB_TEXT_H

#include <wlr/types/wlr_buffer.h>

/* Render one line of text (ellipsised to max_width logical px) at the given scale.
 * Returns a buffer the caller owns (drop it after handing it to the scene), or NULL. */
struct wlr_buffer *gs_text_render(const char *text, const char *font, const float color[4],
	int max_width, float scale, int *logical_w, int *logical_h);

/* A traffic-light button symbol (0 close, 1 minimise, 2 zoom), size logical px, owned by caller. */
struct wlr_buffer *gs_glyph_render(int kind, int size, float scale, const float color[4]);

#endif
