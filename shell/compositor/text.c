/* Text rendered with Pango into a wlroots buffer (for title bars). */
#include <drm_fourcc.h>
#include <pango/pangocairo.h>
#include <stdlib.h>
#include <wlr/interfaces/wlr_buffer.h>
#include "text.h"

struct gs_text_buffer {
	struct wlr_buffer base;
	cairo_surface_t *surface;
};

static void text_buffer_destroy(struct wlr_buffer *wlr_buffer) {
	struct gs_text_buffer *buffer = wl_container_of(wlr_buffer, buffer, base);
	cairo_surface_destroy(buffer->surface);
	free(buffer);
}

static bool text_buffer_begin_access(struct wlr_buffer *wlr_buffer, uint32_t flags,
		void **data, uint32_t *format, size_t *stride) {
	struct gs_text_buffer *buffer = wl_container_of(wlr_buffer, buffer, base);
	if (flags & WLR_BUFFER_DATA_PTR_ACCESS_WRITE) {
		return false;
	}
	*data = cairo_image_surface_get_data(buffer->surface);
	*stride = cairo_image_surface_get_stride(buffer->surface);
	*format = DRM_FORMAT_ARGB8888;
	return true;
}

static void text_buffer_end_access(struct wlr_buffer *wlr_buffer) {
}

static const struct wlr_buffer_impl text_buffer_impl = {
	.destroy = text_buffer_destroy,
	.begin_data_ptr_access = text_buffer_begin_access,
	.end_data_ptr_access = text_buffer_end_access,
};

struct wlr_buffer *gs_text_render(const char *text, const char *font, const float color[4],
		int max_width, float scale, int *logical_w, int *logical_h) {
	if (text == NULL || text[0] == '\0' || max_width <= 0) {
		return NULL;
	}
	/* Measure */
	cairo_surface_t *probe = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 1, 1);
	cairo_t *cr = cairo_create(probe);
	PangoLayout *layout = pango_cairo_create_layout(cr);
	PangoFontDescription *desc = pango_font_description_from_string(font);
	pango_font_description_set_absolute_size(desc,
		pango_font_description_get_size(desc) * scale * 96.0 / 72.0);
	pango_layout_set_font_description(layout, desc);
	pango_layout_set_text(layout, text, -1);
	pango_layout_set_single_paragraph_mode(layout, TRUE);
	pango_layout_set_ellipsize(layout, PANGO_ELLIPSIZE_END);
	pango_layout_set_width(layout, (int)(max_width * scale) * PANGO_SCALE);
	int w, h;
	pango_layout_get_pixel_size(layout, &w, &h);
	g_object_unref(layout);
	cairo_destroy(cr);
	cairo_surface_destroy(probe);
	if (w <= 0 || h <= 0) {
		pango_font_description_free(desc);
		return NULL;
	}

	/* Draw */
	cairo_surface_t *surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, w, h);
	cr = cairo_create(surface);
	cairo_font_options_t *options = cairo_font_options_create();
	cairo_font_options_set_antialias(options, CAIRO_ANTIALIAS_GRAY);
	cairo_font_options_set_hint_style(options, CAIRO_HINT_STYLE_SLIGHT);
	cairo_set_font_options(cr, options);
	layout = pango_cairo_create_layout(cr);
	pango_cairo_context_set_font_options(pango_layout_get_context(layout), options);
	pango_layout_set_font_description(layout, desc);
	pango_layout_set_text(layout, text, -1);
	pango_layout_set_single_paragraph_mode(layout, TRUE);
	pango_layout_set_ellipsize(layout, PANGO_ELLIPSIZE_END);
	pango_layout_set_width(layout, (int)(max_width * scale) * PANGO_SCALE);
	cairo_set_source_rgba(cr, color[0], color[1], color[2], color[3]);
	pango_cairo_show_layout(cr, layout);
	g_object_unref(layout);
	cairo_font_options_destroy(options);
	cairo_destroy(cr);
	pango_font_description_free(desc);
	cairo_surface_flush(surface);

	struct gs_text_buffer *buffer = calloc(1, sizeof(*buffer));
	if (buffer == NULL) {
		cairo_surface_destroy(surface);
		return NULL;
	}
	buffer->surface = surface;
	wlr_buffer_init(&buffer->base, &text_buffer_impl, w, h);
	*logical_w = (int)(w / scale + 0.5f);
	*logical_h = (int)(h / scale + 0.5f);
	return &buffer->base;
}
