#ifndef GOSAAB_TEXT_H
#define GOSAAB_TEXT_H

#include <wlr/types/wlr_buffer.h>

/* Render one line of text (ellipsised to max_width logical px) at the given scale.
 * Returns a buffer the caller owns (drop it after handing it to the scene), or NULL. */
struct wlr_buffer *gs_text_render(const char *text, const char *font, const float color[4],
	int max_width, float scale, int *logical_w, int *logical_h);

#endif
