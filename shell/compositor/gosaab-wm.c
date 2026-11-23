/*
 * gosaab-wm: the Gill-OSaab window manager (Wayland compositor).
 *
 * Built on wlroots 0.20 + scenefx 0.5 (blur, rounded corners, shadows).
 * Started from scenefx's tinywl example (MIT) and grown into Gill-OSaab's own:
 *   - macOS-style window chrome: title bars with traffic-light buttons, centred title,
 *     rounded corners, soft drop shadows, background blur, inactive windows dimmed
 *   - macOS/iOS-style motion: windows spring open and fade/shrink closed
 *   - layer-shell for the Gill-OSaab bar, dock and wallpaper
 *   - new windows centred, zoom (maximise), minimise, fullscreen, Alt/Super+Tab
 *   - screencopy + xdg-output so screenshots (and tests) work
 *
 * Every window has a "frame": its scene tree sits at the frame's top-left corner;
 * the title bar (server-side windows only) is at the top, the app's content below it.
 *
 * Run:  gosaab-wm [-s "startup command"]
 * Keys: Super+Q close, Super+M minimise, Super+F zoom, Super+Return terminal,
 *       Alt/Super+Tab switch windows
 * Test hooks: SIGUSR1 closes the focused window; SIGUSR2 minimises it;
 *             GOSAAB_TEST_CLICKS=<file> replays "x y" clicks written to that file;
 *             the socket name is written to $XDG_RUNTIME_DIR/gosaab-wm.socket;
 *             GOSAAB_ANIM_SLOWDOWN=10 plays animations 10x slower.
 */
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <fcntl.h>
#include <getopt.h>
#include <math.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <scenefx/render/fx_renderer/fx_renderer.h>
#include <scenefx/types/fx/clipped_region.h>
#include <scenefx/types/wlr_scene.h>
#include <wayland-server-core.h>
#include <wlr/backend.h>
#include <wlr/backend/headless.h>
#include <wlr/render/allocator.h>
#include <wlr/render/wlr_renderer.h>
#include <wlr/types/wlr_buffer.h>
#include <wlr/types/wlr_compositor.h>
#include <wlr/types/wlr_cursor.h>
#include <wlr/types/wlr_cursor_shape_v1.h>
#include <wlr/types/wlr_data_control_v1.h>
#include <wlr/types/wlr_data_device.h>
#include <wlr/types/wlr_export_dmabuf_v1.h>
#include <wlr/types/wlr_foreign_toplevel_management_v1.h>
#include <wlr/types/wlr_fractional_scale_v1.h>
#include <wlr/types/wlr_gamma_control_v1.h>
#include <wlr/types/wlr_idle_inhibit_v1.h>
#include <wlr/types/wlr_idle_notify_v1.h>
#include <wlr/types/wlr_input_device.h>
#include <wlr/types/wlr_keyboard.h>
#include <wlr/types/wlr_layer_shell_v1.h>
#include <wlr/types/wlr_output.h>
#include <wlr/types/wlr_output_layout.h>
#include <wlr/types/wlr_pointer.h>
#include <wlr/types/wlr_pointer_constraints_v1.h>
#include <wlr/types/wlr_relative_pointer_v1.h>
#include <wlr/types/wlr_session_lock_v1.h>
#include <wlr/types/wlr_xdg_activation_v1.h>
#include <wlr/types/wlr_presentation_time.h>
#include <wlr/types/wlr_primary_selection.h>
#include <wlr/types/wlr_primary_selection_v1.h>
#include <wlr/types/wlr_screencopy_v1.h>
#include <wlr/types/wlr_seat.h>
#include <wlr/types/wlr_single_pixel_buffer_v1.h>
#include <wlr/types/wlr_subcompositor.h>
#include <wlr/types/wlr_viewporter.h>
#include <wlr/types/wlr_xcursor_manager.h>
#include <wlr/types/wlr_xdg_decoration_v1.h>
#include <wlr/types/wlr_xdg_output_v1.h>
#include <wlr/types/wlr_xdg_shell.h>
#include <wlr/util/edges.h>
#include <wlr/util/log.h>
#include <xkbcommon/xkbcommon.h>

#include "anim.h"
#include "frame.h"
#include "overview.h"
#include "text.h"

#define CORNER_RADIUS 10
#define SHADOW_SIGMA 22.0f
#define SHADOW_OFFSET_Y 8
#define OPEN_MS 280.0
#define CLOSE_MS 200.0
#define TITLE_FONT "Inter Semi-Bold 10"
#define DOUBLE_CLICK_MS 400
#define MINIMIZE_MS 380.0
#define OVERVIEW_MS 340.0

/* Colours (premultiplied alpha) */
static const float COLOR_TITLE_ACTIVE[4] = { 0.165f, 0.165f, 0.180f, 1.0f };
static const float COLOR_TITLE_INACTIVE[4] = { 0.125f, 0.125f, 0.137f, 1.0f };
static const float COLOR_TEXT_ACTIVE[4] = { 0.90f, 0.90f, 0.92f, 1.0f };
static const float COLOR_TEXT_INACTIVE[4] = { 0.55f, 0.55f, 0.59f, 1.0f };
static const float COLOR_BUTTONS[3][4] = {
	{ 1.000f, 0.373f, 0.341f, 1.0f }, /* close  #ff5f57 */
	{ 0.996f, 0.737f, 0.180f, 1.0f }, /* min    #febc2e */
	{ 0.157f, 0.784f, 0.251f, 1.0f }, /* zoom   #28c840 */
};
static const float COLOR_BUTTON_INACTIVE[4] = { 0.30f, 0.30f, 0.32f, 1.0f };

enum gs_cursor_mode { CURSOR_PASSTHROUGH, CURSOR_MOVE, CURSOR_RESIZE };

struct gs_server {
	struct wl_display *display;
	struct wlr_backend *backend;
	struct wlr_renderer *renderer;
	struct wlr_allocator *allocator;
	struct wlr_scene *scene;
	struct wlr_scene_output_layout *scene_layout;
	struct {
		struct wlr_scene_tree *background, *bottom, *dim, *toplevels, *closing, *top, *overlay;
		struct wlr_scene_rect *dim_rect; /* darkens the desktop behind Mission Control */
		struct wlr_scene_optimized_blur *blur;
		struct wlr_scene_rect *backdrop;
	} layers;

	struct wlr_xdg_shell *xdg_shell;
	struct wl_listener new_xdg_toplevel, new_xdg_popup;
	struct wl_list toplevels; /* gs_toplevel.link, most recently focused first */
	struct wl_list closing;   /* gs_closing.link */

	struct wlr_layer_shell_v1 *layer_shell;
	struct wl_listener new_layer_surface;
	struct wl_list layer_surfaces; /* gs_layer.link */

	struct wlr_xdg_decoration_manager_v1 *decoration_mgr;
	struct wl_listener new_decoration;

	struct wlr_foreign_toplevel_manager_v1 *foreign_mgr; /* lets the dock list and control windows */

	/* games: pointer lock + raw mouse motion */
	struct wlr_relative_pointer_manager_v1 *relative_pointer_mgr;
	struct wlr_pointer_constraints_v1 *pointer_constraints;
	struct wlr_pointer_constraint_v1 *active_constraint;
	struct wl_listener new_constraint, constraint_destroy;

	struct wlr_xdg_activation_v1 *xdg_activation;
	struct wl_listener request_activate;

	/* lock screen (ext-session-lock-v1) */
	struct wlr_session_lock_manager_v1 *lock_mgr;
	struct wl_listener new_lock, lock_new_surface, lock_unlock, lock_destroy;
	struct wlr_session_lock_v1 *lock;
	bool locked;
	struct wlr_scene_tree *lock_tree;
	struct wlr_scene_rect *lock_bg;

	struct wlr_cursor *cursor;
	struct wlr_xcursor_manager *cursor_mgr;
	struct wlr_cursor_shape_manager_v1 *cursor_shape_mgr;
	struct wl_listener cursor_motion, cursor_motion_absolute, cursor_button, cursor_axis, cursor_frame;
	struct wl_listener request_cursor_shape;

	struct wlr_seat *seat;
	struct wl_listener new_input, request_cursor, request_set_selection, request_set_primary_selection;
	struct wl_list keyboards;
	enum gs_cursor_mode cursor_mode;
	struct gs_toplevel *grabbed;
	double grab_x, grab_y;
	struct wlr_box grab_frame; /* frame box (layout coords) when a resize started */
	uint32_t resize_edges;
	struct gs_toplevel *last_click_toplevel;
	double last_click_ms;
	float scale; /* output scale, for crisp title text */

	bool overview;              /* Mission Control is showing */
	bool overview_entering;
	struct gs_anim overview_anim;
	double overview_t;          /* 0 = normal desktop, 1 = full Mission Control */
	double overview_from;

	struct wlr_output_layout *output_layout;
	struct wl_list outputs;
	struct wl_listener new_output;
};

struct gs_output {
	struct wl_list link;
	struct gs_server *server;
	struct wlr_output *wlr_output;
	struct wlr_box usable; /* layout coords, after bar/dock exclusive zones */
	struct wl_listener frame, request_state, destroy;
};

struct gs_titlebar {
	struct wlr_scene_tree *tree;
	struct wlr_scene_rect *bg;
	struct wlr_scene_rect *buttons[3];
	struct wlr_scene_buffer *title;
	struct wlr_buffer *title_buffer; /* our reference; reused by the close animation */
	int title_w, title_h;
};

struct gs_toplevel {
	struct wl_list link;
	struct gs_server *server;
	struct wlr_xdg_toplevel *xdg_toplevel;
	struct wlr_scene_tree *tree;     /* at the frame's top-left corner */
	struct wlr_scene_tree *xdg_tree; /* client content */
	struct wlr_scene_shadow *shadow;
	struct wlr_scene_blur *blur;
	struct gs_titlebar tb;
	struct wl_listener map, unmap, commit, destroy, set_title, set_app_id;
	struct wlr_foreign_toplevel_handle_v1 *ftl;
	struct wl_listener ftl_activate, ftl_close, ftl_maximize, ftl_minimize, ftl_fullscreen, ftl_rectangle;
	struct wlr_box dock_rect;   /* where this app's Dock icon is (layout coords), for minimise */
	struct gs_anim min_anim;    /* minimise into / restore out of the Dock */
	struct gs_slot ov;          /* place in Mission Control */
	struct wl_listener request_move, request_resize, request_maximize, request_minimize, request_fullscreen;
	bool mapped, placed, maximized, minimized, fullscreen, ssd, activated;
	struct wlr_box saved; /* frame box before zoom/fullscreen */
	struct wlr_xdg_toplevel_decoration_v1 *decoration;
	struct wlr_buffer *last_buffer; /* latest frame, kept for the close animation */
	int last_w, last_h;
	struct gs_anim open;
};

struct gs_closing_buffer {
	struct wlr_scene_buffer *buffer;
	int x, y, w, h; /* relative to the closing tree, unscaled */
};

struct gs_closing_rect {
	struct wlr_scene_rect *rect;
	int x, y, w, h, radius;
	float color[4];
	bool top_only;
};

struct gs_closing {
	struct wl_list link;
	struct gs_server *server;
	struct wlr_scene_tree *tree;
	struct wlr_scene_shadow *shadow;
	struct gs_closing_buffer bufs[2];
	struct gs_closing_rect rects[4];
	int nbufs, nrects, width, height;
	struct gs_anim anim;
};

struct gs_layer {
	struct wl_list link;
	struct gs_server *server;
	struct wlr_layer_surface_v1 *layer_surface;
	struct wlr_scene_layer_surface_v1 *scene;
	struct wlr_scene_blur *blur; /* frosted glass behind Gill-OSaab's own bar/dock/panels */
	struct wl_listener map, unmap, commit, destroy;
	bool mapped;
};

struct gs_popup {
	struct wlr_xdg_popup *xdg_popup;
	struct wl_listener commit, destroy;
};

struct gs_keyboard {
	struct wl_list link;
	struct gs_server *server;
	struct wlr_keyboard *wlr_keyboard;
	struct wl_listener modifiers, key, destroy;
};

struct gs_decoration {
	struct wlr_xdg_toplevel_decoration_v1 *decoration;
	struct wl_listener request_mode, destroy;
};

static void focus_toplevel(struct gs_toplevel *t);
static void set_maximized(struct gs_toplevel *t, bool maximized);
static void set_fullscreen(struct gs_toplevel *t, bool fullscreen);
static void close_toplevel(struct gs_toplevel *t);

/* ------------------------------------------------------------------ helpers */

static double now_ms(void) {
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
}

static double anim_ms(double ms) {
	static double factor = -1;
	if (factor < 0) {
		const char *env = getenv("GOSAAB_ANIM_SLOWDOWN");
		factor = env ? atof(env) : 1.0;
		if (factor <= 0) {
			factor = 1.0;
		}
	}
	return ms * factor;
}

static void scale_color(const float in[4], float alpha, float out[4]) {
	for (int i = 0; i < 4; i++) {
		out[i] = in[i] * alpha;
	}
}

static void schedule_frames(struct gs_server *server) {
	struct gs_output *output;
	wl_list_for_each(output, &server->outputs, link) {
		wlr_output_schedule_frame(output->wlr_output);
	}
}

static struct gs_output *first_output(struct gs_server *server) {
	if (wl_list_empty(&server->outputs)) {
		return NULL;
	}
	struct gs_output *output = wl_container_of(server->outputs.next, output, link);
	return output;
}

static struct wlr_box output_full_area(struct gs_server *server) {
	struct gs_output *output = first_output(server);
	struct wlr_box box = { 0, 0, 1280, 720 };
	if (output) {
		wlr_output_layout_get_box(server->output_layout, output->wlr_output, &box);
	}
	return box;
}

static struct wlr_box output_usable_area(struct gs_server *server) {
	struct gs_output *output = first_output(server);
	if (output && output->usable.width > 0 && output->usable.height > 0) {
		return output->usable;
	}
	return output_full_area(server);
}

static struct gs_toplevel *focused_toplevel(struct gs_server *server) {
	struct gs_toplevel *t;
	wl_list_for_each(t, &server->toplevels, link) {
		if (!t->minimized) {
			return t;
		}
	}
	return NULL;
}

/* ------------------------------------------------------------------ frame geometry */

static struct wlr_box *content_geo(struct gs_toplevel *t) {
	return &t->xdg_toplevel->base->geometry;
}

static int title_h(struct gs_toplevel *t) {
	return gs_title_height(t->ssd && !t->fullscreen);
}

static int frame_w(struct gs_toplevel *t) {
	return content_geo(t)->width;
}

static int frame_h(struct gs_toplevel *t) {
	return content_geo(t)->height + title_h(t);
}

static struct fx_corner_radii content_corners(struct gs_toplevel *t) {
	if (t->maximized || t->fullscreen) {
		return corner_radii_none();
	}
	return title_h(t) > 0 ? corner_radii_bottom(CORNER_RADIUS) : corner_radii_all(CORNER_RADIUS);
}

/* ------------------------------------------------------------------ title bar */

static void titlebar_render_title(struct gs_toplevel *t) {
	struct gs_titlebar *tb = &t->tb;
	if (tb->title) {
		wlr_scene_node_destroy(&tb->title->node);
		tb->title = NULL;
	}
	if (tb->title_buffer) {
		wlr_buffer_drop(tb->title_buffer);
		tb->title_buffer = NULL;
	}
	const char *title = t->xdg_toplevel->title;
	if (title == NULL || title[0] == '\0') {
		title = t->xdg_toplevel->app_id;
	}
	int max_w = frame_w(t) - 2 * (GS_BUTTON_X0 + 3 * (GS_BUTTON_D + GS_BUTTON_GAP)) - 8;
	if (title == NULL || max_w < 20) {
		return;
	}
	float scale = t->server->scale > 0 ? t->server->scale : 1.0f;
	if (scale < 2.0f) {
		scale = 2.0f; /* supersample so text stays crisp when scaled during animations */
	}
	struct wlr_buffer *buffer = gs_text_render(title, TITLE_FONT,
		t->activated ? COLOR_TEXT_ACTIVE : COLOR_TEXT_INACTIVE, max_w, scale, &tb->title_w, &tb->title_h);
	if (buffer == NULL) {
		return;
	}
	tb->title = wlr_scene_buffer_create(tb->tree, buffer);
	tb->title_buffer = buffer; /* our own reference, dropped on re-render/destroy */
}

/* Lay out the title bar at the given scale/opacity (for animations), at (ox, oy). */
static void titlebar_layout(struct gs_toplevel *t, int ox, int oy, float scale, float alpha) {
	struct gs_titlebar *tb = &t->tb;
	bool show = title_h(t) > 0;
	wlr_scene_node_set_enabled(&tb->tree->node, show);
	if (!show) {
		return;
	}
	int w = (int)lroundf(frame_w(t) * scale);
	int h = (int)lroundf(GS_TITLE_H * scale);
	wlr_scene_node_set_position(&tb->tree->node, ox, oy);
	float c[4];
	scale_color(t->activated ? COLOR_TITLE_ACTIVE : COLOR_TITLE_INACTIVE, alpha, c);
	wlr_scene_rect_set_size(tb->bg, w, h);
	wlr_scene_rect_set_color(tb->bg, c);
	wlr_scene_rect_set_corner_radii(tb->bg, t->maximized ? corner_radii_none() :
		corner_radii_top((int)lroundf(CORNER_RADIUS * scale)));
	int d = (int)lroundf(GS_BUTTON_D * scale);
	for (int i = 0; i < 3; i++) {
		scale_color(t->activated ? COLOR_BUTTONS[i] : COLOR_BUTTON_INACTIVE, alpha, c);
		wlr_scene_rect_set_size(tb->buttons[i], d, d);
		wlr_scene_rect_set_color(tb->buttons[i], c);
		wlr_scene_rect_set_corner_radii(tb->buttons[i], corner_radii_all(d / 2));
		int cx = (int)lroundf(gs_button_cx(i) * scale);
		wlr_scene_node_set_position(&tb->buttons[i]->node, cx - d / 2, (h - d) / 2);
	}
	if (tb->title) {
		int tw = (int)lroundf(tb->title_w * scale), th = (int)lroundf(tb->title_h * scale);
		wlr_scene_buffer_set_dest_size(tb->title, tw, th);
		wlr_scene_buffer_set_opacity(tb->title, alpha);
		wlr_scene_node_set_position(&tb->title->node, (w - tw) / 2, (h - th) / 2);
	}
}

static void titlebar_create(struct gs_toplevel *t) {
	struct gs_titlebar *tb = &t->tb;
	tb->tree = wlr_scene_tree_create(t->tree);
	tb->bg = wlr_scene_rect_create(tb->tree, 0, 0, COLOR_TITLE_ACTIVE);
	for (int i = 0; i < 3; i++) {
		tb->buttons[i] = wlr_scene_rect_create(tb->tree, GS_BUTTON_D, GS_BUTTON_D, COLOR_BUTTONS[i]);
	}
	wlr_scene_node_set_enabled(&tb->tree->node, false);
}

/* ------------------------------------------------------------------ visuals */

struct visual_args {
	struct gs_toplevel *toplevel;
	float scale, alpha;
};

static void style_buffer(struct wlr_scene_buffer *buffer, int sx, int sy, void *data) {
	struct visual_args *args = data;
	struct wlr_scene_surface *scene_surface = wlr_scene_surface_try_from_buffer(buffer);
	if (scene_surface == NULL) {
		return;
	}
	struct wlr_surface *surface = scene_surface->surface;
	wlr_scene_buffer_set_opacity(buffer, args->alpha);
	struct wlr_xdg_surface *xdg = wlr_xdg_surface_try_from_wlr_surface(surface);
	if (xdg && xdg->role == WLR_XDG_SURFACE_ROLE_TOPLEVEL) {
		wlr_scene_buffer_set_corner_radii(buffer, content_corners(args->toplevel));
		wlr_scene_blur_set_transparency_mask_source(args->toplevel->blur, buffer);
		int w = surface->current.width, h = surface->current.height;
		if (args->scale < 0.999f) {
			wlr_scene_buffer_set_dest_size(buffer, (int)lroundf(w * args->scale), (int)lroundf(h * args->scale));
		} else {
			wlr_scene_buffer_set_dest_size(buffer, w, h);
		}
	}
}

/* Draw the whole window (title bar, content, shadow, blur) at a scale about its centre. */
static void apply_toplevel_visual(struct gs_toplevel *t, float scale, float alpha, double ox, double oy) {
	struct wlr_box *geo = content_geo(t);
	int fw = frame_w(t), fh = frame_h(t), th = title_h(t);
	int dx = (int)lroundf(fw * (1.0f - scale) / 2.0f + ox);
	int dy = (int)lroundf(fh * (1.0f - scale) / 2.0f + oy);
	int sw = (int)lroundf(fw * scale), sh = (int)lroundf(fh * scale);
	int sth = (int)lroundf(th * scale);

	titlebar_layout(t, dx, dy, scale, alpha);
	wlr_scene_node_set_position(&t->xdg_tree->node,
		dx + (int)lroundf(-geo->x * scale), dy + sth + (int)lroundf(-geo->y * scale));
	struct visual_args args = { t, scale, alpha };
	wlr_scene_node_for_each_buffer(&t->xdg_tree->node, style_buffer, &args);

	bool flat = t->maximized || t->fullscreen;
	wlr_scene_node_set_enabled(&t->shadow->node, !flat && sw > 0 && sh > 0);
	wlr_scene_node_set_enabled(&t->blur->node, sw > 0 && sh > 0);
	if (sw <= 0 || sh <= 0) {
		return;
	}
	int sigma = (int)SHADOW_SIGMA;
	int radius = flat ? 0 : CORNER_RADIUS;
	int sradius = (int)lroundf(radius * scale);
	wlr_scene_blur_set_size(t->blur, sw, sh);
	wlr_scene_blur_set_corner_radii(t->blur, corner_radii_all(sradius));
	wlr_scene_blur_set_alpha(t->blur, alpha);
	wlr_scene_node_set_position(&t->blur->node, dx, dy);
	float shadow_color[4] = { 0.0f, 0.0f, 0.0f, (t->activated ? 0.55f : 0.35f) * alpha };
	wlr_scene_shadow_set_color(t->shadow, shadow_color);
	wlr_scene_shadow_set_size(t->shadow, sw + sigma * 2, sh + sigma * 2);
	wlr_scene_node_set_position(&t->shadow->node, dx - sigma, dy - sigma + SHADOW_OFFSET_Y);
	wlr_scene_shadow_set_clipped_region(t->shadow, (struct clipped_region){
		.corners = corner_radii_all(sradius),
		.area = { sigma, sigma - SHADOW_OFFSET_Y, sw, sh },
	});
	wlr_scene_subsurface_tree_set_clip(&t->xdg_tree->node, geo);
}

/* Where a minimised window flies to: its Dock icon, or the bottom middle of the screen. */
static struct wlr_box minimize_target(struct gs_toplevel *t) {
	if (t->dock_rect.width > 0 && t->dock_rect.height > 0) {
		return t->dock_rect;
	}
	struct wlr_box full = output_full_area(t->server);
	return (struct wlr_box){ full.x + full.width / 2 - 32, full.y + full.height - 72, 64, 64 };
}

/* Work out how a window should look right now from everything animating it
 * (opening, minimising/restoring, Mission Control) and draw it. Returns true while animating. */
static bool update_toplevel_visual(struct gs_toplevel *t, double now) {
	struct gs_server *server = t->server;
	double scale = 1, alpha = 1, ox = 0, oy = 0;
	bool running = false;
	int fw = frame_w(t), fh = frame_h(t);
	double cx = t->tree->node.x + fw / 2.0, cy = t->tree->node.y + fh / 2.0;
	if (t->open.active) {
		double p = gs_anim_progress(&t->open, now), e = gs_ease_spring(p);
		scale *= 0.94 + 0.06 * e;
		alpha *= fmin(1.0, e * 1.15);
		if (p >= 1.0) {
			t->open.active = false;
		} else {
			running = true;
		}
	}
	if (t->min_anim.active) {
		double p = gs_anim_progress(&t->min_anim, now);
		double m = t->minimized ? gs_ease_in_out_cubic(p) : 1.0 - gs_ease_spring(p);
		struct wlr_box r = minimize_target(t);
		double ts = fmin((double)r.width / (fw > 0 ? fw : 1), (double)r.height / (fh > 0 ? fh : 1));
		scale *= gs_lerp(1.0, ts, m);
		ox += (r.x + r.width / 2.0 - cx) * m;
		oy += (r.y + r.height / 2.0 - cy) * m;
		alpha *= 1.0 - 0.6 * m * m;
		if (p >= 1.0) {
			t->min_anim.active = false;
			if (t->minimized) {
				wlr_scene_node_set_enabled(&t->tree->node, false);
			}
		} else {
			running = true;
		}
	}
	if (server->overview_t > 0 && !t->minimized) {
		double o = server->overview_t;
		scale *= gs_lerp(1.0, t->ov.scale, o);
		ox += (t->ov.cx - cx) * o;
		oy += (t->ov.cy - cy) * o;
	}
	apply_toplevel_visual(t, (float)scale, (float)alpha, ox, oy);
	return running;
}

static void refresh_toplevel(struct gs_toplevel *t) {
	update_toplevel_visual(t, now_ms());
}

/* Advance every running animation; returns true while any is still running. */
static bool tick_animations(struct gs_server *server) {
	double now = now_ms();
	bool running = false;
	bool overview_moving = server->overview_anim.active;
	if (overview_moving) {
		double p = gs_anim_progress(&server->overview_anim, now);
		server->overview_t = gs_lerp(server->overview_from, server->overview_entering ? 1.0 : 0.0, gs_ease_spring(p));
		if (p >= 1.0) {
			server->overview_anim.active = false;
			server->overview_t = server->overview_entering ? 1.0 : 0.0;
		} else {
			running = true;
		}
		float dim[4] = { 0, 0, 0, (float)(0.45 * server->overview_t) };
		wlr_scene_rect_set_color(server->layers.dim_rect, dim);
		wlr_scene_node_set_enabled(&server->layers.dim_rect->node, server->overview_t > 0.001);
	}
	struct gs_toplevel *t;
	wl_list_for_each(t, &server->toplevels, link) {
		if (t->open.active || t->min_anim.active || overview_moving) {
			running = update_toplevel_visual(t, now) || running;
		}
	}
	struct gs_closing *c, *tmp;
	wl_list_for_each_safe(c, tmp, &server->closing, link) {
		double p = gs_anim_progress(&c->anim, now);
		double e = gs_ease_in_cubic(p);
		float scale = (float)(1.0 - 0.07 * e), alpha = (float)(1.0 - e);
		int dx = (int)lroundf(c->width * (1.0f - scale) / 2.0f);
		int dy = (int)lroundf(c->height * (1.0f - scale) / 2.0f);
		for (int i = 0; i < c->nbufs; i++) {
			struct gs_closing_buffer *b = &c->bufs[i];
			wlr_scene_node_set_position(&b->buffer->node, dx + (int)lroundf(b->x * scale),
				dy + (int)lroundf(b->y * scale));
			wlr_scene_buffer_set_dest_size(b->buffer, (int)lroundf(b->w * scale), (int)lroundf(b->h * scale));
			wlr_scene_buffer_set_opacity(b->buffer, alpha);
		}
		for (int i = 0; i < c->nrects; i++) {
			struct gs_closing_rect *r = &c->rects[i];
			float col[4];
			scale_color(r->color, alpha, col);
			wlr_scene_rect_set_color(r->rect, col);
			wlr_scene_rect_set_size(r->rect, (int)lroundf(r->w * scale), (int)lroundf(r->h * scale));
			wlr_scene_node_set_position(&r->rect->node, dx + (int)lroundf(r->x * scale),
				dy + (int)lroundf(r->y * scale));
			int rad = (int)lroundf(r->radius * scale);
			wlr_scene_rect_set_corner_radii(r->rect, r->top_only ? corner_radii_top(rad) : corner_radii_all(rad));
		}
		float shadow_color[4] = { 0.0f, 0.0f, 0.0f, 0.55f * alpha };
		wlr_scene_shadow_set_color(c->shadow, shadow_color);
		if (p >= 1.0) {
			wlr_scene_node_destroy(&c->tree->node);
			wl_list_remove(&c->link);
			free(c);
		} else {
			running = true;
		}
	}
	return running;
}

/* ------------------------------------------------------------------ focus */

static void focus_surface(struct gs_server *server, struct wlr_surface *surface) {
	if (surface == NULL) {
		return;
	}
	if (server->locked && wlr_session_lock_surface_v1_try_from_wlr_surface(surface) == NULL) {
		return; /* while locked, only the lock screen gets the keyboard */
	}
	struct wlr_keyboard *keyboard = wlr_seat_get_keyboard(server->seat);
	if (keyboard) {
		wlr_seat_keyboard_notify_enter(server->seat, surface, keyboard->keycodes,
			keyboard->num_keycodes, &keyboard->modifiers);
	} else {
		wlr_seat_keyboard_notify_enter(server->seat, surface, NULL, 0, NULL);
	}
}

static bool exclusive_layer_has_focus(struct gs_server *server) {
	struct gs_layer *l;
	wl_list_for_each(l, &server->layer_surfaces, link) {
		if (l->mapped && l->layer_surface->current.keyboard_interactive ==
				ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_EXCLUSIVE &&
				l->layer_surface->current.layer >= ZWLR_LAYER_SHELL_V1_LAYER_TOP) {
			return true;
		}
	}
	return false;
}

static void set_activated(struct gs_toplevel *t, bool activated) {
	if (t->activated == activated) {
		return;
	}
	t->activated = activated;
	wlr_xdg_toplevel_set_activated(t->xdg_toplevel, activated);
	if (t->ftl) {
		wlr_foreign_toplevel_handle_v1_set_activated(t->ftl, activated);
	}
	if (t->ssd && t->mapped) {
		titlebar_render_title(t);
	}
	refresh_toplevel(t);
}

static void focus_toplevel(struct gs_toplevel *t) {
	if (t == NULL) {
		return;
	}
	struct gs_server *server = t->server;
	if (t->minimized) {
		t->minimized = false;
		if (t->ftl) {
			wlr_foreign_toplevel_handle_v1_set_minimized(t->ftl, false);
		}
		wlr_scene_node_set_enabled(&t->tree->node, true);
		gs_anim_start(&t->min_anim, now_ms(), anim_ms(MINIMIZE_MS));
		schedule_frames(server);
	}
	struct gs_toplevel *other;
	wl_list_for_each(other, &server->toplevels, link) {
		if (other != t) {
			set_activated(other, false);
		}
	}
	wlr_scene_node_raise_to_top(&t->tree->node);
	wl_list_remove(&t->link);
	wl_list_insert(&server->toplevels, &t->link);
	set_activated(t, true);
	if (!exclusive_layer_has_focus(server)) {
		focus_surface(server, t->xdg_toplevel->base->surface);
	}
}

static void focus_next_toplevel(struct gs_server *server) {
	if (wl_list_length(&server->toplevels) < 2) {
		return;
	}
	struct gs_toplevel *last = wl_container_of(server->toplevels.prev, last, link);
	focus_toplevel(last);
}

static void minimize_toplevel(struct gs_toplevel *t) {
	if (t == NULL || t->minimized) {
		return;
	}
	struct gs_server *server = t->server;
	t->minimized = true;
	if (t->ftl) {
		wlr_foreign_toplevel_handle_v1_set_minimized(t->ftl, true);
	}
	set_activated(t, false);
	/* fly into the Dock; the window is hidden when the animation ends */
	gs_anim_start(&t->min_anim, now_ms(), anim_ms(MINIMIZE_MS));
	schedule_frames(server);
	if (server->seat->keyboard_state.focused_surface == t->xdg_toplevel->base->surface) {
		wlr_seat_keyboard_clear_focus(server->seat);
	}
	/* move to the back of the focus order, then focus the next visible window */
	wl_list_remove(&t->link);
	wl_list_insert(server->toplevels.prev, &t->link);
	struct gs_toplevel *next = focused_toplevel(server);
	if (next) {
		focus_toplevel(next);
	}
}

/* ------------------------------------------------------------------ Mission Control */

/* Show every window side by side (or go back). `pick` gets focus when leaving. */
static void overview_set(struct gs_server *server, bool on, struct gs_toplevel *pick) {
	if (server->overview == on) {
		return;
	}
	if (on) {
		struct gs_toplevel *list[64];
		int w[64], h[64], n = 0;
		struct gs_toplevel *t;
		wl_list_for_each_reverse(t, &server->toplevels, link) { /* oldest first: stable places */
			if (t->mapped && !t->minimized && n < 64) {
				list[n] = t;
				w[n] = frame_w(t);
				h[n] = frame_h(t);
				n++;
			}
		}
		if (n == 0) {
			return;
		}
		struct gs_slot slots[64];
		struct wlr_box area = output_usable_area(server);
		gs_overview_layout(n, w, h, area.x + 40, area.y + 40, area.width - 80, area.height - 80, slots);
		for (int i = 0; i < n; i++) {
			list[i]->ov = slots[i];
		}
		wlr_seat_pointer_clear_focus(server->seat);
		server->cursor_mode = CURSOR_PASSTHROUGH;
		server->grabbed = NULL;
	}
	server->overview = on;
	server->overview_entering = on;
	/* start from wherever the previous animation got to, so quick toggles don't jump */
	server->overview_from = server->overview_t;
	gs_anim_start(&server->overview_anim, now_ms(), anim_ms(OVERVIEW_MS));
	if (!on && pick) {
		focus_toplevel(pick);
	}
	schedule_frames(server);
}

/* ------------------------------------------------------------------ layer shell */

static void arrange_layers(struct gs_server *server) {
	struct gs_output *output = first_output(server);
	if (output == NULL) {
		return;
	}
	struct wlr_box full = output_full_area(server);
	struct wlr_box usable = full;
	for (int pass = 0; pass < 2; pass++) {
		for (int layer = ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY; layer >= ZWLR_LAYER_SHELL_V1_LAYER_BACKGROUND; layer--) {
			struct gs_layer *l;
			wl_list_for_each(l, &server->layer_surfaces, link) {
				struct wlr_layer_surface_v1 *ls = l->layer_surface;
				if (!ls->initialized || (int)ls->current.layer != layer) {
					continue;
				}
				bool exclusive = ls->current.exclusive_zone > 0;
				if ((pass == 0) != exclusive) {
					continue;
				}
				wlr_scene_layer_surface_v1_configure(l->scene, &full, &usable);
			}
		}
	}
	output->usable = usable;
	wlr_scene_rect_set_size(server->layers.backdrop, full.width, full.height);
	wlr_scene_node_set_position(&server->layers.backdrop->node, full.x, full.y);
	wlr_scene_rect_set_size(server->layers.dim_rect, full.width, full.height);
	wlr_scene_node_set_position(&server->layers.dim_rect->node, full.x, full.y);
}

static struct wlr_scene_tree *layer_tree(struct gs_server *server, enum zwlr_layer_shell_v1_layer layer) {
	switch (layer) {
	case ZWLR_LAYER_SHELL_V1_LAYER_BACKGROUND: return server->layers.background;
	case ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM: return server->layers.bottom;
	case ZWLR_LAYER_SHELL_V1_LAYER_TOP: return server->layers.top;
	default: return server->layers.overlay;
	}
}

static void find_surface_buffer(struct wlr_scene_buffer *buffer, int sx, int sy, void *data) {
	struct wlr_scene_buffer **out = data;
	if (*out == NULL && wlr_scene_surface_try_from_buffer(buffer) != NULL) {
		*out = buffer;
	}
}

/* Gill-OSaab's own panels (namespace "gosaab-*") get frosted glass behind them. The blur
 * follows the panel's own shape (its transparent pixels mask it), so rounded docks work.
 * An optional ":r<radius>" suffix in the namespace rounds the blur's corners too. */
static void layer_update_blur(struct gs_layer *l) {
	struct wlr_layer_surface_v1 *ls = l->layer_surface;
	if (ls->namespace == NULL || strncmp(ls->namespace, "gosaab-", 7) != 0 ||
			ls->current.layer == ZWLR_LAYER_SHELL_V1_LAYER_BACKGROUND) {
		return;
	}
	if (l->blur == NULL) {
		l->blur = wlr_scene_blur_create(l->scene->tree, 0, 0);
		wlr_scene_node_lower_to_bottom(&l->blur->node);
	}
	wlr_scene_blur_set_size(l->blur, ls->surface->current.width, ls->surface->current.height);
	const char *r = strstr(ls->namespace, ":r");
	if (r) {
		wlr_scene_blur_set_corner_radii(l->blur, corner_radii_all(atoi(r + 2)));
	}
	struct wlr_scene_buffer *buffer = NULL;
	wlr_scene_node_for_each_buffer(&l->scene->tree->node, find_surface_buffer, &buffer);
	if (buffer) {
		wlr_scene_blur_set_transparency_mask_source(l->blur, buffer);
	}
}

static void layer_commit(struct wl_listener *listener, void *data) {
	struct gs_layer *l = wl_container_of(listener, l, commit);
	struct wlr_layer_surface_v1 *ls = l->layer_surface;
	if (ls->current.committed & WLR_LAYER_SURFACE_V1_STATE_LAYER) {
		wlr_scene_node_reparent(&l->scene->tree->node, layer_tree(l->server, ls->current.layer));
	}
	if (ls->initial_commit || ls->current.committed) {
		arrange_layers(l->server);
	}
	if (l->mapped) {
		layer_update_blur(l);
	}
}

static void layer_map(struct wl_listener *listener, void *data) {
	struct gs_layer *l = wl_container_of(listener, l, map);
	l->mapped = true;
	arrange_layers(l->server);
	layer_update_blur(l);
	if (l->layer_surface->current.keyboard_interactive != ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_NONE &&
			l->layer_surface->current.layer >= ZWLR_LAYER_SHELL_V1_LAYER_TOP) {
		focus_surface(l->server, l->layer_surface->surface);
	}
}

static void layer_unmap(struct wl_listener *listener, void *data) {
	struct gs_layer *l = wl_container_of(listener, l, unmap);
	l->mapped = false;
	arrange_layers(l->server);
	struct gs_server *server = l->server;
	if (server->seat->keyboard_state.focused_surface == l->layer_surface->surface) {
		wlr_seat_keyboard_clear_focus(server->seat);
		struct gs_toplevel *t = focused_toplevel(server);
		if (t) {
			focus_surface(server, t->xdg_toplevel->base->surface);
		}
	}
}

static void layer_destroy(struct wl_listener *listener, void *data) {
	struct gs_layer *l = wl_container_of(listener, l, destroy);
	wl_list_remove(&l->link);
	wl_list_remove(&l->map.link);
	wl_list_remove(&l->unmap.link);
	wl_list_remove(&l->commit.link);
	wl_list_remove(&l->destroy.link);
	struct gs_server *server = l->server;
	free(l);
	arrange_layers(server);
}

static void server_new_layer_surface(struct wl_listener *listener, void *data) {
	struct gs_server *server = wl_container_of(listener, server, new_layer_surface);
	struct wlr_layer_surface_v1 *ls = data;
	struct gs_output *output = first_output(server);
	if (ls->output == NULL) {
		if (output == NULL) {
			wlr_layer_surface_v1_destroy(ls);
			return;
		}
		ls->output = output->wlr_output;
	}
	struct gs_layer *l = calloc(1, sizeof(*l));
	l->server = server;
	l->layer_surface = ls;
	l->scene = wlr_scene_layer_surface_v1_create(layer_tree(server, ls->pending.layer), ls);
	ls->data = l->scene->tree; /* parent tree for this surface's popups */
	l->map.notify = layer_map;
	wl_signal_add(&ls->surface->events.map, &l->map);
	l->unmap.notify = layer_unmap;
	wl_signal_add(&ls->surface->events.unmap, &l->unmap);
	l->commit.notify = layer_commit;
	wl_signal_add(&ls->surface->events.commit, &l->commit);
	l->destroy.notify = layer_destroy;
	wl_signal_add(&ls->events.destroy, &l->destroy);
	wl_list_insert(&server->layer_surfaces, &l->link);
}

/* ------------------------------------------------------------------ toplevels */

static void place_centered(struct gs_toplevel *t) {
	struct wlr_box area = output_usable_area(t->server);
	int x = area.x + (area.width - frame_w(t)) / 2;
	int y = area.y + (area.height - frame_h(t)) / 2;
	if (y < area.y) {
		y = area.y;
	}
	wlr_scene_node_set_position(&t->tree->node, x, y);
}

/* Ask the client for a content size that makes the frame w x h. */
static void request_frame_size(struct gs_toplevel *t, int w, int h) {
	int ch = h - title_h(t);
	wlr_xdg_toplevel_set_size(t->xdg_toplevel, w > 1 ? w : 1, ch > 1 ? ch : 1);
}

static void set_maximized(struct gs_toplevel *t, bool maximized) {
	if (t->maximized == maximized) {
		return;
	}
	if (maximized) {
		t->saved = (struct wlr_box){ t->tree->node.x, t->tree->node.y, frame_w(t), frame_h(t) };
		struct wlr_box area = output_usable_area(t->server);
		wlr_scene_node_set_position(&t->tree->node, area.x, area.y);
		t->maximized = true;
		request_frame_size(t, area.width, area.height);
	} else {
		wlr_scene_node_set_position(&t->tree->node, t->saved.x, t->saved.y);
		t->maximized = false;
		request_frame_size(t, t->saved.width, t->saved.height);
	}
	wlr_xdg_toplevel_set_maximized(t->xdg_toplevel, maximized);
	if (t->ftl) {
		wlr_foreign_toplevel_handle_v1_set_maximized(t->ftl, maximized);
	}
	refresh_toplevel(t);
}

static void set_fullscreen(struct gs_toplevel *t, bool fullscreen) {
	if (t->fullscreen == fullscreen) {
		return;
	}
	if (fullscreen) {
		struct wlr_box full = output_full_area(t->server);
		t->saved = (struct wlr_box){ t->tree->node.x, t->tree->node.y, frame_w(t), frame_h(t) };
		t->fullscreen = true;
		wlr_scene_node_reparent(&t->tree->node, t->server->layers.overlay);
		wlr_scene_node_set_position(&t->tree->node, full.x, full.y);
		wlr_xdg_toplevel_set_size(t->xdg_toplevel, full.width, full.height);
	} else {
		t->fullscreen = false;
		wlr_scene_node_reparent(&t->tree->node, t->server->layers.toplevels);
		wlr_scene_node_set_position(&t->tree->node, t->saved.x, t->saved.y);
		request_frame_size(t, t->saved.width, t->saved.height);
	}
	wlr_xdg_toplevel_set_fullscreen(t->xdg_toplevel, fullscreen);
	if (t->ftl) {
		wlr_foreign_toplevel_handle_v1_set_fullscreen(t->ftl, fullscreen);
	}
	refresh_toplevel(t);
}

static void toplevel_set_title(struct wl_listener *listener, void *data) {
	struct gs_toplevel *t = wl_container_of(listener, t, set_title);
	if (t->ftl && t->xdg_toplevel->title) {
		wlr_foreign_toplevel_handle_v1_set_title(t->ftl, t->xdg_toplevel->title);
	}
	if (t->ssd && t->mapped) {
		titlebar_render_title(t);
		refresh_toplevel(t);
	}
}

static void toplevel_set_app_id(struct wl_listener *listener, void *data) {
	struct gs_toplevel *t = wl_container_of(listener, t, set_app_id);
	if (t->ftl && t->xdg_toplevel->app_id) {
		wlr_foreign_toplevel_handle_v1_set_app_id(t->ftl, t->xdg_toplevel->app_id);
	}
}

/* ---- requests from the dock / task switcher (wlr-foreign-toplevel-management) */

static void ftl_activate(struct wl_listener *listener, void *data) {
	struct gs_toplevel *t = wl_container_of(listener, t, ftl_activate);
	focus_toplevel(t);
}

static void ftl_close(struct wl_listener *listener, void *data) {
	struct gs_toplevel *t = wl_container_of(listener, t, ftl_close);
	close_toplevel(t);
}

static void ftl_maximize(struct wl_listener *listener, void *data) {
	struct gs_toplevel *t = wl_container_of(listener, t, ftl_maximize);
	struct wlr_foreign_toplevel_handle_v1_maximized_event *event = data;
	set_maximized(t, event->maximized);
	wlr_xdg_surface_schedule_configure(t->xdg_toplevel->base);
}

static void ftl_minimize(struct wl_listener *listener, void *data) {
	struct gs_toplevel *t = wl_container_of(listener, t, ftl_minimize);
	struct wlr_foreign_toplevel_handle_v1_minimized_event *event = data;
	if (event->minimized) {
		minimize_toplevel(t);
	} else {
		focus_toplevel(t);
	}
}

static void ftl_fullscreen(struct wl_listener *listener, void *data) {
	struct gs_toplevel *t = wl_container_of(listener, t, ftl_fullscreen);
	struct wlr_foreign_toplevel_handle_v1_fullscreen_event *event = data;
	set_fullscreen(t, event->fullscreen);
	wlr_xdg_surface_schedule_configure(t->xdg_toplevel->base);
}

static void ftl_rectangle(struct wl_listener *listener, void *data) {
	struct gs_toplevel *t = wl_container_of(listener, t, ftl_rectangle);
	struct wlr_foreign_toplevel_handle_v1_set_rectangle_event *event = data;
	t->dock_rect = (struct wlr_box){0};
	if (event->surface == NULL || event->width <= 0 || event->height <= 0) {
		return;
	}
	struct wlr_layer_surface_v1 *ls = wlr_layer_surface_v1_try_from_wlr_surface(event->surface);
	struct wlr_scene_tree *tree = ls ? ls->data : NULL;
	int lx, ly;
	if (tree && wlr_scene_node_coords(&tree->node, &lx, &ly)) {
		t->dock_rect = (struct wlr_box){ lx + event->x, ly + event->y, event->width, event->height };
	}
}

static void ftl_create(struct gs_toplevel *t) {
	struct gs_server *server = t->server;
	t->ftl = wlr_foreign_toplevel_handle_v1_create(server->foreign_mgr);
	if (t->ftl == NULL) {
		return;
	}
	if (t->xdg_toplevel->title) {
		wlr_foreign_toplevel_handle_v1_set_title(t->ftl, t->xdg_toplevel->title);
	}
	if (t->xdg_toplevel->app_id) {
		wlr_foreign_toplevel_handle_v1_set_app_id(t->ftl, t->xdg_toplevel->app_id);
	}
	struct gs_output *output = first_output(server);
	if (output) {
		wlr_foreign_toplevel_handle_v1_output_enter(t->ftl, output->wlr_output);
	}
	t->ftl_activate.notify = ftl_activate;
	wl_signal_add(&t->ftl->events.request_activate, &t->ftl_activate);
	t->ftl_close.notify = ftl_close;
	wl_signal_add(&t->ftl->events.request_close, &t->ftl_close);
	t->ftl_maximize.notify = ftl_maximize;
	wl_signal_add(&t->ftl->events.request_maximize, &t->ftl_maximize);
	t->ftl_minimize.notify = ftl_minimize;
	wl_signal_add(&t->ftl->events.request_minimize, &t->ftl_minimize);
	t->ftl_fullscreen.notify = ftl_fullscreen;
	wl_signal_add(&t->ftl->events.request_fullscreen, &t->ftl_fullscreen);
	t->ftl_rectangle.notify = ftl_rectangle;
	wl_signal_add(&t->ftl->events.set_rectangle, &t->ftl_rectangle);
}

static void ftl_destroy(struct gs_toplevel *t) {
	if (t->ftl == NULL) {
		return;
	}
	wl_list_remove(&t->ftl_activate.link);
	wl_list_remove(&t->ftl_close.link);
	wl_list_remove(&t->ftl_maximize.link);
	wl_list_remove(&t->ftl_minimize.link);
	wl_list_remove(&t->ftl_fullscreen.link);
	wl_list_remove(&t->ftl_rectangle.link);
	wlr_foreign_toplevel_handle_v1_destroy(t->ftl);
	t->ftl = NULL;
}

static void toplevel_commit(struct wl_listener *listener, void *data) {
	struct gs_toplevel *t = wl_container_of(listener, t, commit);
	if (t->xdg_toplevel->base->initial_commit) {
		if (t->decoration) {
			bool csd = getenv("GOSAAB_CSD") != NULL;
			wlr_xdg_toplevel_decoration_v1_set_mode(t->decoration, csd ?
				WLR_XDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE : WLR_XDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE);
			t->ssd = !csd;
		}
		wlr_xdg_toplevel_set_wm_capabilities(t->xdg_toplevel, WLR_XDG_TOPLEVEL_WM_CAPABILITIES_MAXIMIZE |
			WLR_XDG_TOPLEVEL_WM_CAPABILITIES_MINIMIZE | WLR_XDG_TOPLEVEL_WM_CAPABILITIES_FULLSCREEN);
		wlr_xdg_toplevel_set_size(t->xdg_toplevel, 0, 0);
		return;
	}
	struct wlr_surface *surface = t->xdg_toplevel->base->surface;
	if (surface->buffer != NULL && t->last_buffer != &surface->buffer->base) {
		if (t->last_buffer) {
			wlr_buffer_unlock(t->last_buffer);
		}
		t->last_buffer = wlr_buffer_lock(&surface->buffer->base);
	}
	if (surface->buffer != NULL) {
		t->last_w = surface->current.width;
		t->last_h = surface->current.height;
	}
	if (t->mapped && !t->placed && content_geo(t)->width > 0) {
		place_centered(t);
		t->placed = true;
	}
	if (t->ssd && t->mapped) {
		/* re-render the title when the width changes enough to matter */
		int max_w = frame_w(t) - 2 * (GS_BUTTON_X0 + 3 * (GS_BUTTON_D + GS_BUTTON_GAP)) - 8;
		if (t->tb.title == NULL || t->tb.title_w > max_w || t->tb.title_w + 4 < max_w) {
			titlebar_render_title(t);
		}
	}
	refresh_toplevel(t);
}

static void toplevel_map(struct wl_listener *listener, void *data) {
	struct gs_toplevel *t = wl_container_of(listener, t, map);
	overview_set(t->server, false, NULL);
	t->mapped = true;
	wlr_scene_node_set_enabled(&t->tree->node, true);
	if (!t->placed) {
		place_centered(t);
		t->placed = true;
	}
	wl_list_insert(&t->server->toplevels, &t->link);
	ftl_create(t);
	gs_anim_start(&t->open, now_ms(), anim_ms(OPEN_MS));
	focus_toplevel(t);
	if (t->ssd) {
		titlebar_render_title(t);
	}
	apply_toplevel_visual(t, 0.94f, 0.0f, 0, 0);
	schedule_frames(t->server);
}

static void closing_add_rect(struct gs_closing *c, int x, int y, int w, int h, int radius,
		const float color[4], bool top_only) {
	if (c->nrects >= (int)(sizeof(c->rects) / sizeof(c->rects[0]))) {
		return;
	}
	struct gs_closing_rect *r = &c->rects[c->nrects++];
	r->rect = wlr_scene_rect_create(c->tree, w, h, color);
	r->x = x; r->y = y; r->w = w; r->h = h; r->radius = radius; r->top_only = top_only;
	memcpy(r->color, color, sizeof(r->color));
	wlr_scene_node_set_position(&r->rect->node, x, y);
}

/* Keep a picture of the window and let it fade/shrink away (macOS-style close). */
static void start_close_animation(struct gs_toplevel *t) {
	struct gs_server *server = t->server;
	int fw = frame_w(t), fh = frame_h(t), th = title_h(t);
	if (fw <= 0 || fh <= 0 || t->minimized) {
		return;
	}
	struct gs_closing *c = calloc(1, sizeof(*c));
	c->server = server;
	c->tree = wlr_scene_tree_create(server->layers.closing);
	wlr_scene_node_set_position(&c->tree->node, t->tree->node.x, t->tree->node.y);
	c->width = fw;
	c->height = fh;
	int sigma = (int)SHADOW_SIGMA;
	c->shadow = wlr_scene_shadow_create(c->tree, fw + sigma * 2, fh + sigma * 2,
		CORNER_RADIUS, SHADOW_SIGMA, (float[4]){ 0.0f, 0.0f, 0.0f, 0.55f });
	wlr_scene_node_set_position(&c->shadow->node, -sigma, -sigma + SHADOW_OFFSET_Y);
	if (th > 0) {
		closing_add_rect(c, 0, 0, fw, th, CORNER_RADIUS,
			t->activated ? COLOR_TITLE_ACTIVE : COLOR_TITLE_INACTIVE, true);
		for (int i = 0; i < 3; i++) {
			closing_add_rect(c, gs_button_cx(i) - GS_BUTTON_D / 2, (th - GS_BUTTON_D) / 2, GS_BUTTON_D,
				GS_BUTTON_D, GS_BUTTON_D / 2, t->activated ? COLOR_BUTTONS[i] : COLOR_BUTTON_INACTIVE, false);
		}
		if (t->tb.title_buffer) {
			struct wlr_scene_buffer *title = wlr_scene_buffer_create(c->tree, t->tb.title_buffer);
			if (title) {
				int x = (fw - t->tb.title_w) / 2, y = (th - t->tb.title_h) / 2;
				c->bufs[c->nbufs++] = (struct gs_closing_buffer){ title, x, y, t->tb.title_w, t->tb.title_h };
			}
		}
	}
	struct wlr_box *geo = content_geo(t);
	if (t->last_buffer != NULL && t->last_w > 0 && t->last_h > 0) {
		struct wlr_scene_buffer *copy = wlr_scene_buffer_create(c->tree, t->last_buffer);
		if (copy != NULL) {
			wlr_scene_buffer_set_corner_radii(copy, content_corners(t));
			c->bufs[c->nbufs++] = (struct gs_closing_buffer){ copy, -geo->x, th - geo->y, t->last_w, t->last_h };
		}
	}
	gs_anim_start(&c->anim, now_ms(), anim_ms(CLOSE_MS));
	wl_list_insert(&server->closing, &c->link);
	tick_animations(server);
	schedule_frames(server);
}

static void toplevel_unmap(struct wl_listener *listener, void *data) {
	struct gs_toplevel *t = wl_container_of(listener, t, unmap);
	struct gs_server *server = t->server;
	overview_set(server, false, NULL);
	start_close_animation(t);
	ftl_destroy(t);
	t->min_anim.active = false;
	t->mapped = false;
	t->placed = false;
	t->minimized = false;
	t->activated = false;
	t->open.active = false;
	wlr_scene_node_set_enabled(&t->tree->node, false);
	if (t == server->grabbed) {
		server->cursor_mode = CURSOR_PASSTHROUGH;
		server->grabbed = NULL;
	}
	if (server->last_click_toplevel == t) {
		server->last_click_toplevel = NULL;
	}
	bool was_focused = server->seat->keyboard_state.focused_surface == t->xdg_toplevel->base->surface;
	wl_list_remove(&t->link);
	if (was_focused) {
		wlr_seat_keyboard_clear_focus(server->seat);
		focus_toplevel(focused_toplevel(server));
	}
}

static void toplevel_destroy(struct wl_listener *listener, void *data) {
	struct gs_toplevel *t = wl_container_of(listener, t, destroy);
	ftl_destroy(t);
	struct wl_listener *listeners[] = { &t->map, &t->unmap, &t->commit, &t->destroy, &t->set_title,
		&t->set_app_id,
		&t->request_move, &t->request_resize, &t->request_maximize, &t->request_minimize,
		&t->request_fullscreen };
	for (size_t i = 0; i < sizeof(listeners) / sizeof(listeners[0]); i++) {
		wl_list_remove(&listeners[i]->link);
	}
	if (t->last_buffer) {
		wlr_buffer_unlock(t->last_buffer);
	}
	wlr_scene_node_destroy(&t->tree->node);
	if (t->tb.title_buffer) {
		wlr_buffer_drop(t->tb.title_buffer);
	}
	free(t);
}

static void begin_interactive(struct gs_toplevel *t, enum gs_cursor_mode mode, uint32_t edges) {
	struct gs_server *server = t->server;
	if (t->maximized) {
		/* un-zoom under the cursor, keeping it at the same relative spot */
		double rel = (server->cursor->x - t->tree->node.x) / (frame_w(t) > 0 ? frame_w(t) : 1);
		set_maximized(t, false);
		wlr_scene_node_set_position(&t->tree->node, (int)(server->cursor->x - rel * t->saved.width),
			(int)server->cursor->y - GS_TITLE_H / 2);
	}
	server->grabbed = t;
	server->cursor_mode = mode;
	if (mode == CURSOR_MOVE) {
		server->grab_x = server->cursor->x - t->tree->node.x;
		server->grab_y = server->cursor->y - t->tree->node.y;
	} else {
		struct wlr_box frame = { t->tree->node.x, t->tree->node.y, frame_w(t), frame_h(t) };
		double bx = frame.x + ((edges & WLR_EDGE_RIGHT) ? frame.width : 0);
		double by = frame.y + ((edges & WLR_EDGE_BOTTOM) ? frame.height : 0);
		server->grab_x = server->cursor->x - bx;
		server->grab_y = server->cursor->y - by;
		server->grab_frame = frame;
		server->resize_edges = edges;
	}
}

static void toplevel_request_move(struct wl_listener *listener, void *data) {
	struct gs_toplevel *t = wl_container_of(listener, t, request_move);
	begin_interactive(t, CURSOR_MOVE, 0);
}

static void toplevel_request_resize(struct wl_listener *listener, void *data) {
	struct wlr_xdg_toplevel_resize_event *event = data;
	struct gs_toplevel *t = wl_container_of(listener, t, request_resize);
	begin_interactive(t, CURSOR_RESIZE, event->edges);
}

static void toplevel_request_maximize(struct wl_listener *listener, void *data) {
	struct gs_toplevel *t = wl_container_of(listener, t, request_maximize);
	if (t->xdg_toplevel->base->initialized) {
		set_maximized(t, t->xdg_toplevel->requested.maximized);
		wlr_xdg_surface_schedule_configure(t->xdg_toplevel->base);
	}
}

static void toplevel_request_minimize(struct wl_listener *listener, void *data) {
	struct gs_toplevel *t = wl_container_of(listener, t, request_minimize);
	if (t->mapped && t->xdg_toplevel->requested.minimized) {
		minimize_toplevel(t);
	}
}

static void toplevel_request_fullscreen(struct wl_listener *listener, void *data) {
	struct gs_toplevel *t = wl_container_of(listener, t, request_fullscreen);
	if (t->xdg_toplevel->base->initialized) {
		set_fullscreen(t, t->xdg_toplevel->requested.fullscreen);
		wlr_xdg_surface_schedule_configure(t->xdg_toplevel->base);
	}
}

static void server_new_xdg_toplevel(struct wl_listener *listener, void *data) {
	struct gs_server *server = wl_container_of(listener, server, new_xdg_toplevel);
	struct wlr_xdg_toplevel *xdg_toplevel = data;
	struct gs_toplevel *t = calloc(1, sizeof(*t));
	t->server = server;
	t->xdg_toplevel = xdg_toplevel;
	t->tree = wlr_scene_tree_create(server->layers.toplevels);
	t->tree->node.data = t;
	wlr_scene_node_set_enabled(&t->tree->node, false);
	t->blur = wlr_scene_blur_create(t->tree, 0, 0);
	wlr_scene_blur_set_should_only_blur_bottom_layer(t->blur, true);
	t->shadow = wlr_scene_shadow_create(t->tree, 0, 0, CORNER_RADIUS, SHADOW_SIGMA,
		(float[4]){ 0.0f, 0.0f, 0.0f, 0.55f });
	t->xdg_tree = wlr_scene_xdg_surface_create(t->tree, xdg_toplevel->base);
	xdg_toplevel->base->data = t->xdg_tree;
	titlebar_create(t);
	wlr_scene_node_lower_to_bottom(&t->shadow->node);
	wlr_scene_node_lower_to_bottom(&t->blur->node);

	t->map.notify = toplevel_map;
	wl_signal_add(&xdg_toplevel->base->surface->events.map, &t->map);
	t->unmap.notify = toplevel_unmap;
	wl_signal_add(&xdg_toplevel->base->surface->events.unmap, &t->unmap);
	t->commit.notify = toplevel_commit;
	wl_signal_add(&xdg_toplevel->base->surface->events.commit, &t->commit);
	t->destroy.notify = toplevel_destroy;
	wl_signal_add(&xdg_toplevel->events.destroy, &t->destroy);
	t->set_title.notify = toplevel_set_title;
	wl_signal_add(&xdg_toplevel->events.set_title, &t->set_title);
	t->set_app_id.notify = toplevel_set_app_id;
	wl_signal_add(&xdg_toplevel->events.set_app_id, &t->set_app_id);
	t->request_move.notify = toplevel_request_move;
	wl_signal_add(&xdg_toplevel->events.request_move, &t->request_move);
	t->request_resize.notify = toplevel_request_resize;
	wl_signal_add(&xdg_toplevel->events.request_resize, &t->request_resize);
	t->request_maximize.notify = toplevel_request_maximize;
	wl_signal_add(&xdg_toplevel->events.request_maximize, &t->request_maximize);
	t->request_minimize.notify = toplevel_request_minimize;
	wl_signal_add(&xdg_toplevel->events.request_minimize, &t->request_minimize);
	t->request_fullscreen.notify = toplevel_request_fullscreen;
	wl_signal_add(&xdg_toplevel->events.request_fullscreen, &t->request_fullscreen);
}

static void popup_commit(struct wl_listener *listener, void *data) {
	struct gs_popup *popup = wl_container_of(listener, popup, commit);
	if (popup->xdg_popup->base->initial_commit) {
		wlr_xdg_surface_schedule_configure(popup->xdg_popup->base);
	}
}

static void popup_destroy(struct wl_listener *listener, void *data) {
	struct gs_popup *popup = wl_container_of(listener, popup, destroy);
	wl_list_remove(&popup->commit.link);
	wl_list_remove(&popup->destroy.link);
	free(popup);
}

static void server_new_xdg_popup(struct wl_listener *listener, void *data) {
	struct wlr_xdg_popup *xdg_popup = data;
	struct wlr_scene_tree *parent_tree = NULL;
	struct wlr_xdg_surface *parent = wlr_xdg_surface_try_from_wlr_surface(xdg_popup->parent);
	if (parent != NULL) {
		parent_tree = parent->data;
	} else {
		struct wlr_layer_surface_v1 *ls = wlr_layer_surface_v1_try_from_wlr_surface(xdg_popup->parent);
		if (ls != NULL) {
			parent_tree = ls->data;
		}
	}
	if (parent_tree == NULL) {
		return;
	}
	struct gs_popup *popup = calloc(1, sizeof(*popup));
	popup->xdg_popup = xdg_popup;
	xdg_popup->base->data = wlr_scene_xdg_surface_create(parent_tree, xdg_popup->base);
	popup->commit.notify = popup_commit;
	wl_signal_add(&xdg_popup->base->surface->events.commit, &popup->commit);
	popup->destroy.notify = popup_destroy;
	wl_signal_add(&xdg_popup->events.destroy, &popup->destroy);
}

/* ------------------------------------------------------------------ decorations */

static struct gs_toplevel *toplevel_from_xdg(struct wlr_xdg_toplevel *xdg_toplevel) {
	struct wlr_scene_tree *xdg_tree = xdg_toplevel->base->data;
	if (xdg_tree == NULL || xdg_tree->node.parent == NULL) {
		return NULL;
	}
	return xdg_tree->node.parent->node.data;
}

/* Gill-OSaab draws the title bar (server-side) unless GOSAAB_CSD is set. The mode may only
 * be sent once the toplevel has made its initial commit. */
static void decoration_apply(struct gs_decoration *d) {
	if (!d->decoration->toplevel->base->initialized) {
		return;
	}
	bool csd = getenv("GOSAAB_CSD") != NULL;
	wlr_xdg_toplevel_decoration_v1_set_mode(d->decoration, csd ?
		WLR_XDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE : WLR_XDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE);
}

static void decoration_request_mode(struct wl_listener *listener, void *data) {
	struct gs_decoration *d = wl_container_of(listener, d, request_mode);
	decoration_apply(d);
}

static void decoration_destroy(struct wl_listener *listener, void *data) {
	struct gs_decoration *d = wl_container_of(listener, d, destroy);
	struct gs_toplevel *t = toplevel_from_xdg(d->decoration->toplevel);
	if (t && t->decoration == d->decoration) {
		t->decoration = NULL;
		t->ssd = false;
		if (t->mapped) {
			refresh_toplevel(t);
		}
	}
	wl_list_remove(&d->request_mode.link);
	wl_list_remove(&d->destroy.link);
	free(d);
}

static void handle_new_decoration(struct wl_listener *listener, void *data) {
	struct wlr_xdg_toplevel_decoration_v1 *decoration = data;
	struct gs_decoration *d = calloc(1, sizeof(*d));
	d->decoration = decoration;
	struct gs_toplevel *t = toplevel_from_xdg(decoration->toplevel);
	if (t) {
		t->decoration = decoration;
	}
	d->request_mode.notify = decoration_request_mode;
	wl_signal_add(&decoration->events.request_mode, &d->request_mode);
	d->destroy.notify = decoration_destroy;
	wl_signal_add(&decoration->events.destroy, &d->destroy);
	decoration_apply(d);
}

/* ------------------------------------------------------------------ lock screen */

struct gs_lock_surface {
	struct gs_server *server;
	struct wlr_session_lock_surface_v1 *lock_surface;
	struct wlr_scene_tree *tree;
	struct wl_listener map, destroy;
};

static void lock_surface_map(struct wl_listener *listener, void *data) {
	struct gs_lock_surface *ls = wl_container_of(listener, ls, map);
	focus_surface(ls->server, ls->lock_surface->surface);
	schedule_frames(ls->server);
}

static void lock_surface_destroy(struct wl_listener *listener, void *data) {
	struct gs_lock_surface *ls = wl_container_of(listener, ls, destroy);
	wl_list_remove(&ls->map.link);
	wl_list_remove(&ls->destroy.link);
	free(ls);
}

static void lock_new_surface(struct wl_listener *listener, void *data) {
	struct gs_server *server = wl_container_of(listener, server, lock_new_surface);
	struct wlr_session_lock_surface_v1 *lock_surface = data;
	struct gs_lock_surface *ls = calloc(1, sizeof(*ls));
	ls->server = server;
	ls->lock_surface = lock_surface;
	ls->tree = wlr_scene_subsurface_tree_create(server->lock_tree, lock_surface->surface);
	struct wlr_box box;
	wlr_output_layout_get_box(server->output_layout, lock_surface->output, &box);
	wlr_scene_node_set_position(&ls->tree->node, box.x, box.y);
	wlr_session_lock_surface_v1_configure(lock_surface, box.width, box.height);
	ls->map.notify = lock_surface_map;
	wl_signal_add(&lock_surface->surface->events.map, &ls->map);
	ls->destroy.notify = lock_surface_destroy;
	wl_signal_add(&lock_surface->events.destroy, &ls->destroy);
}

static void lock_release(struct gs_server *server) {
	wl_list_remove(&server->lock_new_surface.link);
	wl_list_remove(&server->lock_unlock.link);
	wl_list_remove(&server->lock_destroy.link);
	server->lock = NULL;
}

static void lock_unlock(struct wl_listener *listener, void *data) {
	struct gs_server *server = wl_container_of(listener, server, lock_unlock);
	lock_release(server);
	server->locked = false;
	wlr_scene_node_set_enabled(&server->lock_tree->node, false);
	wlr_seat_keyboard_clear_focus(server->seat);
	struct gs_toplevel *t = focused_toplevel(server);
	if (t) {
		focus_surface(server, t->xdg_toplevel->base->surface);
	}
	schedule_frames(server);
}

/* The lock screen app quit without unlocking: stay locked (blank) until a new one locks. */
static void lock_destroy(struct wl_listener *listener, void *data) {
	struct gs_server *server = wl_container_of(listener, server, lock_destroy);
	lock_release(server);
}

static void handle_new_lock(struct wl_listener *listener, void *data) {
	struct gs_server *server = wl_container_of(listener, server, new_lock);
	struct wlr_session_lock_v1 *lock = data;
	if (server->lock != NULL) {
		wlr_session_lock_v1_destroy(lock); /* already locked by someone else */
		return;
	}
	overview_set(server, false, NULL);
	server->lock = lock;
	server->locked = true;
	struct wlr_box full = output_full_area(server);
	wlr_scene_rect_set_size(server->lock_bg, full.width, full.height);
	wlr_scene_node_set_position(&server->lock_bg->node, full.x, full.y);
	wlr_scene_node_set_enabled(&server->lock_tree->node, true);
	wlr_scene_node_raise_to_top(&server->lock_tree->node);
	wlr_seat_keyboard_clear_focus(server->seat);
	wlr_seat_pointer_clear_focus(server->seat);
	server->lock_new_surface.notify = lock_new_surface;
	wl_signal_add(&lock->events.new_surface, &server->lock_new_surface);
	server->lock_unlock.notify = lock_unlock;
	wl_signal_add(&lock->events.unlock, &server->lock_unlock);
	server->lock_destroy.notify = lock_destroy;
	wl_signal_add(&lock->events.destroy, &server->lock_destroy);
	wlr_session_lock_v1_send_locked(lock);
	schedule_frames(server);
}

/* ------------------------------------------------------------------ pointer lock for games */

struct gs_constraint {
	struct gs_server *server;
	struct wlr_pointer_constraint_v1 *constraint;
	struct wl_listener destroy;
};

static void check_constraint(struct gs_server *server, struct wlr_surface *surface) {
	struct wlr_pointer_constraint_v1 *c = surface ?
		wlr_pointer_constraints_v1_constraint_for_surface(server->pointer_constraints, surface, server->seat) : NULL;
	if (c == server->active_constraint) {
		return;
	}
	if (server->active_constraint) {
		wlr_pointer_constraint_v1_send_deactivated(server->active_constraint);
	}
	server->active_constraint = c;
	if (c) {
		wlr_pointer_constraint_v1_send_activated(c);
	}
}

static void constraint_destroy(struct wl_listener *listener, void *data) {
	struct gs_constraint *gc = wl_container_of(listener, gc, destroy);
	if (gc->server->active_constraint == gc->constraint) {
		gc->server->active_constraint = NULL;
	}
	wl_list_remove(&gc->destroy.link);
	free(gc);
}

static void handle_new_constraint(struct wl_listener *listener, void *data) {
	struct gs_server *server = wl_container_of(listener, server, new_constraint);
	struct wlr_pointer_constraint_v1 *constraint = data;
	struct gs_constraint *gc = calloc(1, sizeof(*gc));
	gc->server = server;
	gc->constraint = constraint;
	gc->destroy.notify = constraint_destroy;
	wl_signal_add(&constraint->events.destroy, &gc->destroy);
	if (server->seat->pointer_state.focused_surface == constraint->surface) {
		check_constraint(server, constraint->surface);
	}
}

static void handle_request_activate(struct wl_listener *listener, void *data) {
	struct gs_server *server = wl_container_of(listener, server, request_activate);
	struct wlr_xdg_activation_v1_request_activate_event *event = data;
	struct wlr_xdg_toplevel *xdg = wlr_xdg_toplevel_try_from_wlr_surface(event->surface);
	struct gs_toplevel *t = xdg ? toplevel_from_xdg(xdg) : NULL;
	if (t && t->mapped && !server->locked) {
		focus_toplevel(t);
	}
}

/* ------------------------------------------------------------------ input */

static void spawn(const char *cmd) {
	if (cmd == NULL || cmd[0] == '\0') {
		return;
	}
	if (fork() == 0) {
		/* apps must not inherit our signal setup: the event loop blocks signals and we ignore
		 * SIGCHLD, and both survive exec (apps would then fail to wait for their own children) */
		sigset_t all;
		sigemptyset(&all);
		sigprocmask(SIG_SETMASK, &all, NULL);
		signal(SIGCHLD, SIG_DFL);
		signal(SIGPIPE, SIG_DFL);
		setsid();
		execl("/bin/sh", "/bin/sh", "-c", cmd, (void *)NULL);
		_exit(127);
	}
}

static void close_toplevel(struct gs_toplevel *t) {
	if (t) {
		wlr_xdg_toplevel_send_close(t->xdg_toplevel);
	}
}

/* Ask the Gill-OSaab shell (Quickshell) to do something, e.g. "spotlight toggle" */
static void shell_ipc(const char *call) {
	const char *ipc = getenv("GOSAAB_SHELL_IPC");
	char cmd[512];
	snprintf(cmd, sizeof(cmd), "%s %s", ipc ? ipc : "qs -c gill-osaab ipc call", call);
	spawn(cmd);
}

static bool handle_keybinding(struct gs_server *server, uint32_t mods, xkb_keysym_t sym) {
	if (server->locked) {
		return false; /* every key goes to the lock screen */
	}
	bool super = mods & WLR_MODIFIER_LOGO;
	bool alt = mods & WLR_MODIFIER_ALT;
	if ((super || alt) && sym == XKB_KEY_Tab) {
		focus_next_toplevel(server);
		return true;
	}
	if (server->overview && (sym == XKB_KEY_Escape || sym == XKB_KEY_Return)) {
		overview_set(server, false, sym == XKB_KEY_Return ? focused_toplevel(server) : NULL);
		return true;
	}
	if (sym == XKB_KEY_XF86LaunchA || (super && sym == XKB_KEY_Up)) { /* F3 / Super+Up: Mission Control */
		overview_set(server, !server->overview, NULL);
		return true;
	}
	if (sym == XKB_KEY_XF86LaunchB) {
		shell_ipc("launchpad toggle");
		return true;
	}
	if (!super) {
		return false;
	}
	struct gs_toplevel *t = focused_toplevel(server);
	switch (sym) {
	case XKB_KEY_q:
		close_toplevel(t);
		return true;
	case XKB_KEY_m:
		minimize_toplevel(t);
		return true;
	case XKB_KEY_f:
		if (t) {
			set_maximized(t, !t->maximized);
		}
		return true;
	case XKB_KEY_space:
		shell_ipc("spotlight toggle");
		return true;
	case XKB_KEY_l:
		shell_ipc("lock lock");
		return true;
	case XKB_KEY_g:
		shell_ipc("launchpad toggle");
		return true;
	case XKB_KEY_a:
		shell_ipc("controlcenter toggle");
		return true;
	case XKB_KEY_n:
		shell_ipc("notifications toggle");
		return true;
	case XKB_KEY_Return: {
		const char *term = getenv("GOSAAB_TERMINAL");
		spawn(term ? term : "foot");
		return true;
	}
	case XKB_KEY_Escape:
		if (getenv("GOSAAB_WM_DEBUG")) {
			wl_display_terminate(server->display);
			return true;
		}
		return false;
	default:
		return false;
	}
}

static void keyboard_modifiers(struct wl_listener *listener, void *data) {
	struct gs_keyboard *kb = wl_container_of(listener, kb, modifiers);
	wlr_seat_set_keyboard(kb->server->seat, kb->wlr_keyboard);
	wlr_seat_keyboard_notify_modifiers(kb->server->seat, &kb->wlr_keyboard->modifiers);
}

static void keyboard_key(struct wl_listener *listener, void *data) {
	struct gs_keyboard *kb = wl_container_of(listener, kb, key);
	struct gs_server *server = kb->server;
	struct wlr_keyboard_key_event *event = data;
	uint32_t keycode = event->keycode + 8;
	const xkb_keysym_t *syms;
	int nsyms = xkb_state_key_get_syms(kb->wlr_keyboard->xkb_state, keycode, &syms);
	bool handled = false;
	uint32_t mods = wlr_keyboard_get_modifiers(kb->wlr_keyboard);
	if (event->state == WL_KEYBOARD_KEY_STATE_PRESSED) {
		for (int i = 0; i < nsyms; i++) {
			handled = handle_keybinding(server, mods, syms[i]) || handled;
		}
	}
	if (!handled) {
		wlr_seat_set_keyboard(server->seat, kb->wlr_keyboard);
		wlr_seat_keyboard_notify_key(server->seat, event->time_msec, event->keycode, event->state);
	}
}

static void keyboard_destroy(struct wl_listener *listener, void *data) {
	struct gs_keyboard *kb = wl_container_of(listener, kb, destroy);
	wl_list_remove(&kb->modifiers.link);
	wl_list_remove(&kb->key.link);
	wl_list_remove(&kb->destroy.link);
	wl_list_remove(&kb->link);
	free(kb);
}

static void new_keyboard(struct gs_server *server, struct wlr_input_device *device) {
	struct wlr_keyboard *wlr_keyboard = wlr_keyboard_from_input_device(device);
	struct gs_keyboard *kb = calloc(1, sizeof(*kb));
	kb->server = server;
	kb->wlr_keyboard = wlr_keyboard;
	struct xkb_context *context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
	struct xkb_keymap *keymap = xkb_keymap_new_from_names(context, NULL, XKB_KEYMAP_COMPILE_NO_FLAGS);
	wlr_keyboard_set_keymap(wlr_keyboard, keymap);
	xkb_keymap_unref(keymap);
	xkb_context_unref(context);
	wlr_keyboard_set_repeat_info(wlr_keyboard, 30, 400);
	kb->modifiers.notify = keyboard_modifiers;
	wl_signal_add(&wlr_keyboard->events.modifiers, &kb->modifiers);
	kb->key.notify = keyboard_key;
	wl_signal_add(&wlr_keyboard->events.key, &kb->key);
	kb->destroy.notify = keyboard_destroy;
	wl_signal_add(&device->events.destroy, &kb->destroy);
	wlr_seat_set_keyboard(server->seat, wlr_keyboard);
	wl_list_insert(&server->keyboards, &kb->link);
}

static void server_new_input(struct wl_listener *listener, void *data) {
	struct gs_server *server = wl_container_of(listener, server, new_input);
	struct wlr_input_device *device = data;
	switch (device->type) {
	case WLR_INPUT_DEVICE_KEYBOARD:
		new_keyboard(server, device);
		break;
	case WLR_INPUT_DEVICE_POINTER:
		wlr_cursor_attach_input_device(server->cursor, device);
		break;
	default:
		break;
	}
	uint32_t caps = WL_SEAT_CAPABILITY_POINTER;
	if (!wl_list_empty(&server->keyboards)) {
		caps |= WL_SEAT_CAPABILITY_KEYBOARD;
	}
	wlr_seat_set_capabilities(server->seat, caps);
}

static void seat_request_cursor(struct wl_listener *listener, void *data) {
	struct gs_server *server = wl_container_of(listener, server, request_cursor);
	struct wlr_seat_pointer_request_set_cursor_event *event = data;
	if (server->seat->pointer_state.focused_client == event->seat_client) {
		wlr_cursor_set_surface(server->cursor, event->surface, event->hotspot_x, event->hotspot_y);
	}
}

static void request_cursor_shape(struct wl_listener *listener, void *data) {
	struct gs_server *server = wl_container_of(listener, server, request_cursor_shape);
	struct wlr_cursor_shape_manager_v1_request_set_shape_event *event = data;
	if (server->seat->pointer_state.focused_client == event->seat_client) {
		wlr_cursor_set_xcursor(server->cursor, server->cursor_mgr, wlr_cursor_shape_v1_name(event->shape));
	}
}

static void seat_request_set_selection(struct wl_listener *listener, void *data) {
	struct gs_server *server = wl_container_of(listener, server, request_set_selection);
	struct wlr_seat_request_set_selection_event *event = data;
	wlr_seat_set_selection(server->seat, event->source, event->serial);
}

static void seat_request_set_primary_selection(struct wl_listener *listener, void *data) {
	struct gs_server *server = wl_container_of(listener, server, request_set_primary_selection);
	struct wlr_seat_request_set_primary_selection_event *event = data;
	wlr_seat_set_primary_selection(server->seat, event->source, event->serial);
}

/* What is under a layout point: a client surface, a window frame part, or nothing. */
struct gs_hit {
	struct wlr_surface *surface;
	double sx, sy;
	struct gs_toplevel *toplevel;
	enum gs_frame_part part;
	unsigned edges;
};

static struct gs_hit hit_test(struct gs_server *server, double lx, double ly) {
	struct gs_hit hit = {0};
	double sx, sy;
	struct wlr_scene_node *node = wlr_scene_node_at(&server->scene->tree.node, lx, ly, &sx, &sy);
	if (node != NULL && node->type == WLR_SCENE_NODE_BUFFER) {
		struct wlr_scene_surface *scene_surface =
			wlr_scene_surface_try_from_buffer(wlr_scene_buffer_from_node(node));
		if (scene_surface) {
			hit.surface = scene_surface->surface;
			hit.sx = sx;
			hit.sy = sy;
		}
	}
	/* Walk up to a window's frame tree (only trust trees we know are ours) */
	for (struct wlr_scene_tree *tree = node ? node->parent : NULL; tree && !hit.toplevel;
			tree = tree->node.parent) {
		struct gs_toplevel *t;
		wl_list_for_each(t, &server->toplevels, link) {
			if (t->tree == tree) {
				hit.toplevel = t;
				break;
			}
		}
	}
	if (hit.toplevel && !hit.surface) {
		struct gs_toplevel *t = hit.toplevel;
		hit.part = gs_frame_hit(frame_w(t), content_geo(t)->height, title_h(t) > 0,
			lx - t->tree->node.x, ly - t->tree->node.y, &hit.edges);
		return hit;
	}
	if (hit.surface) {
		hit.part = hit.toplevel ? GS_PART_CONTENT : GS_PART_NONE;
		return hit;
	}
	/* Nothing drawn here: maybe just outside a server-side window's edge (resize grip) */
	struct gs_toplevel *t;
	wl_list_for_each(t, &server->toplevels, link) {
		if (t->minimized || !t->mapped || t->maximized || t->fullscreen || title_h(t) == 0) {
			continue;
		}
		unsigned edges;
		enum gs_frame_part part = gs_frame_hit(frame_w(t), content_geo(t)->height, true,
			lx - t->tree->node.x, ly - t->tree->node.y, &edges);
		if (part == GS_PART_RESIZE) {
			hit.toplevel = t;
			hit.part = part;
			hit.edges = edges;
			return hit;
		}
	}
	return hit;
}

static const char *resize_cursor(unsigned edges) {
	switch (edges) {
	case GS_EDGE_TOP: return "n-resize";
	case GS_EDGE_BOTTOM: return "s-resize";
	case GS_EDGE_LEFT: return "w-resize";
	case GS_EDGE_RIGHT: return "e-resize";
	case GS_EDGE_TOP | GS_EDGE_LEFT: return "nw-resize";
	case GS_EDGE_TOP | GS_EDGE_RIGHT: return "ne-resize";
	case GS_EDGE_BOTTOM | GS_EDGE_LEFT: return "sw-resize";
	case GS_EDGE_BOTTOM | GS_EDGE_RIGHT: return "se-resize";
	default: return "default";
	}
}

static void process_cursor_resize(struct gs_server *server) {
	struct gs_toplevel *t = server->grabbed;
	double bx = server->cursor->x - server->grab_x;
	double by = server->cursor->y - server->grab_y;
	int min_w = 160, min_h = 80 + title_h(t);
	int left = server->grab_frame.x, right = server->grab_frame.x + server->grab_frame.width;
	int top = server->grab_frame.y, bottom = server->grab_frame.y + server->grab_frame.height;
	if (server->resize_edges & WLR_EDGE_TOP) {
		top = by < bottom - min_h ? by : bottom - min_h;
	} else if (server->resize_edges & WLR_EDGE_BOTTOM) {
		bottom = by > top + min_h ? by : top + min_h;
	}
	if (server->resize_edges & WLR_EDGE_LEFT) {
		left = bx < right - min_w ? bx : right - min_w;
	} else if (server->resize_edges & WLR_EDGE_RIGHT) {
		right = bx > left + min_w ? bx : left + min_w;
	}
	wlr_scene_node_set_position(&t->tree->node, left, top);
	request_frame_size(t, right - left, bottom - top);
}

static void process_cursor_motion(struct gs_server *server, uint32_t time) {
	if (server->cursor_mode == CURSOR_MOVE) {
		struct gs_toplevel *t = server->grabbed;
		wlr_scene_node_set_position(&t->tree->node, server->cursor->x - server->grab_x,
			server->cursor->y - server->grab_y);
		return;
	}
	if (server->cursor_mode == CURSOR_RESIZE) {
		process_cursor_resize(server);
		return;
	}
	if (server->overview) {
		wlr_cursor_set_xcursor(server->cursor, server->cursor_mgr, "default");
		wlr_seat_pointer_clear_focus(server->seat);
		check_constraint(server, NULL);
		return;
	}
	struct gs_hit hit = hit_test(server, server->cursor->x, server->cursor->y);
	if (server->locked && hit.surface && wlr_session_lock_surface_v1_try_from_wlr_surface(hit.surface) == NULL) {
		hit.surface = NULL; /* nothing but the lock screen is reachable while locked */
	}
	if (hit.surface == NULL) {
		wlr_cursor_set_xcursor(server->cursor, server->cursor_mgr,
			hit.part == GS_PART_RESIZE && !server->locked ? resize_cursor(hit.edges) : "default");
		wlr_seat_pointer_clear_focus(server->seat);
		check_constraint(server, NULL);
		return;
	}
	wlr_seat_pointer_notify_enter(server->seat, hit.surface, hit.sx, hit.sy);
	check_constraint(server, hit.surface);
	wlr_seat_pointer_notify_motion(server->seat, time, hit.sx, hit.sy);
}

static void cursor_motion(struct wl_listener *listener, void *data) {
	struct gs_server *server = wl_container_of(listener, server, cursor_motion);
	struct wlr_pointer_motion_event *event = data;
	/* games read raw mouse movement, even when the pointer is locked */
	wlr_relative_pointer_manager_v1_send_relative_motion(server->relative_pointer_mgr, server->seat,
		(uint64_t)event->time_msec * 1000, event->delta_x, event->delta_y, event->unaccel_dx, event->unaccel_dy);
	struct wlr_pointer_constraint_v1 *c = server->active_constraint;
	if (c && !server->locked && server->cursor_mode == CURSOR_PASSTHROUGH) {
		if (c->type == WLR_POINTER_CONSTRAINT_V1_LOCKED) {
			return; /* pointer stays put (mouse-look in games) */
		}
		/* confined: only move while staying on the game's surface */
		struct gs_hit hit = hit_test(server, server->cursor->x + event->delta_x, server->cursor->y + event->delta_y);
		if (hit.surface != c->surface) {
			return;
		}
	}
	wlr_cursor_move(server->cursor, &event->pointer->base, event->delta_x, event->delta_y);
	process_cursor_motion(server, event->time_msec);
}

static void cursor_motion_absolute(struct wl_listener *listener, void *data) {
	struct gs_server *server = wl_container_of(listener, server, cursor_motion_absolute);
	struct wlr_pointer_motion_absolute_event *event = data;
	wlr_cursor_warp_absolute(server->cursor, &event->pointer->base, event->x, event->y);
	process_cursor_motion(server, event->time_msec);
}

/* Handle a press at a layout point (also used by the test hook). */
static void press_at(struct gs_server *server, double lx, double ly) {
	if (server->locked) {
		return;
	}
	struct gs_hit hit = hit_test(server, lx, ly);
	if (server->overview) { /* pick a window, or click the desktop to go back */
		overview_set(server, false, (hit.toplevel && !hit.toplevel->minimized) ? hit.toplevel : NULL);
		return;
	}
	struct gs_toplevel *t = hit.toplevel;
	if (t == NULL) {
		if (hit.surface) {
			struct wlr_layer_surface_v1 *ls = wlr_layer_surface_v1_try_from_wlr_surface(hit.surface);
			if (ls && ls->current.keyboard_interactive != ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_NONE) {
				focus_surface(server, hit.surface);
			}
		}
		return;
	}
	focus_toplevel(t);
	double now = now_ms();
	switch (hit.part) {
	case GS_PART_CLOSE:
		close_toplevel(t);
		break;
	case GS_PART_MINIMIZE:
		minimize_toplevel(t);
		break;
	case GS_PART_ZOOM:
		set_maximized(t, !t->maximized);
		break;
	case GS_PART_TITLE:
		if (server->last_click_toplevel == t && now - server->last_click_ms < DOUBLE_CLICK_MS) {
			set_maximized(t, !t->maximized); /* double-click the title bar to zoom, like macOS */
			server->last_click_toplevel = NULL;
			return;
		}
		begin_interactive(t, CURSOR_MOVE, 0);
		break;
	case GS_PART_RESIZE:
		begin_interactive(t, CURSOR_RESIZE, hit.edges);
		break;
	default:
		break;
	}
	server->last_click_toplevel = t;
	server->last_click_ms = now;
}

static void cursor_button(struct wl_listener *listener, void *data) {
	struct gs_server *server = wl_container_of(listener, server, cursor_button);
	struct wlr_pointer_button_event *event = data;
	if (event->state == WL_POINTER_BUTTON_STATE_RELEASED) {
		wlr_seat_pointer_notify_button(server->seat, event->time_msec, event->button, event->state);
		server->cursor_mode = CURSOR_PASSTHROUGH;
		server->grabbed = NULL;
		return;
	}
	struct gs_hit hit = hit_test(server, server->cursor->x, server->cursor->y);
	if (hit.surface && !server->overview) {
		wlr_seat_pointer_notify_button(server->seat, event->time_msec, event->button, event->state);
	}
	press_at(server, server->cursor->x, server->cursor->y);
}

static void cursor_axis(struct wl_listener *listener, void *data) {
	struct gs_server *server = wl_container_of(listener, server, cursor_axis);
	struct wlr_pointer_axis_event *event = data;
	wlr_seat_pointer_notify_axis(server->seat, event->time_msec, event->orientation, event->delta,
		event->delta_discrete, event->source, event->relative_direction);
}

static void cursor_frame(struct wl_listener *listener, void *data) {
	struct gs_server *server = wl_container_of(listener, server, cursor_frame);
	wlr_seat_pointer_notify_frame(server->seat);
}

/* ------------------------------------------------------------------ outputs */

static void output_frame(struct wl_listener *listener, void *data) {
	struct gs_output *output = wl_container_of(listener, output, frame);
	struct gs_server *server = output->server;
	bool animating = tick_animations(server);
	struct wlr_scene_output *scene_output = wlr_scene_get_scene_output(server->scene, output->wlr_output);
	wlr_scene_output_commit(scene_output, NULL);
	struct timespec now;
	clock_gettime(CLOCK_MONOTONIC, &now);
	wlr_scene_output_send_frame_done(scene_output, &now);
	if (animating) {
		wlr_output_schedule_frame(output->wlr_output);
	}
}

static void output_request_state(struct wl_listener *listener, void *data) {
	struct gs_output *output = wl_container_of(listener, output, request_state);
	const struct wlr_output_event_request_state *event = data;
	wlr_output_commit_state(output->wlr_output, event->state);
	wlr_scene_optimized_blur_set_size(output->server->layers.blur, output->wlr_output->width,
		output->wlr_output->height);
	arrange_layers(output->server);
}

static void output_destroy(struct wl_listener *listener, void *data) {
	struct gs_output *output = wl_container_of(listener, output, destroy);
	wl_list_remove(&output->frame.link);
	wl_list_remove(&output->request_state.link);
	wl_list_remove(&output->destroy.link);
	wl_list_remove(&output->link);
	free(output);
}

static void server_new_output(struct wl_listener *listener, void *data) {
	struct gs_server *server = wl_container_of(listener, server, new_output);
	struct wlr_output *wlr_output = data;
	wlr_output_init_render(wlr_output, server->allocator, server->renderer);
	struct wlr_output_state state;
	wlr_output_state_init(&state);
	wlr_output_state_set_enabled(&state, true);
	struct wlr_output_mode *mode = wlr_output_preferred_mode(wlr_output);
	if (mode != NULL) {
		wlr_output_state_set_mode(&state, mode);
	} else if (wlr_output_is_headless(wlr_output)) {
		const char *size = getenv("GOSAAB_HEADLESS_SIZE");
		int w = 1920, h = 1080;
		if (size) {
			sscanf(size, "%dx%d", &w, &h);
		}
		wlr_output_state_set_custom_mode(&state, w, h, 60000);
	}
	wlr_output_commit_state(wlr_output, &state);
	wlr_output_state_finish(&state);
	if (wlr_output->scale > server->scale) {
		server->scale = wlr_output->scale;
	}

	struct gs_output *output = calloc(1, sizeof(*output));
	output->wlr_output = wlr_output;
	output->server = server;
	output->frame.notify = output_frame;
	wl_signal_add(&wlr_output->events.frame, &output->frame);
	output->request_state.notify = output_request_state;
	wl_signal_add(&wlr_output->events.request_state, &output->request_state);
	output->destroy.notify = output_destroy;
	wl_signal_add(&wlr_output->events.destroy, &output->destroy);
	wl_list_insert(&server->outputs, &output->link);

	struct wlr_output_layout_output *l_output = wlr_output_layout_add_auto(server->output_layout, wlr_output);
	struct wlr_scene_output *scene_output = wlr_scene_output_create(server->scene, wlr_output);
	wlr_scene_output_layout_add_output(server->scene_layout, l_output, scene_output);
	wlr_scene_optimized_blur_set_size(server->layers.blur, wlr_output->width, wlr_output->height);
	arrange_layers(server);
}

/* ------------------------------------------------------------------ signals and test hooks */

static int handle_sigusr1(int sig, void *data) {
	close_toplevel(focused_toplevel(data));
	return 0;
}

static int handle_sigusr2(int sig, void *data) {
	minimize_toplevel(focused_toplevel(data));
	return 0;
}

static int handle_sigoverview(int sig, void *data) {
	struct gs_server *server = data;
	overview_set(server, !server->overview, NULL);
	return 0;
}

static int handle_sigterm(int sig, void *data) {
	struct gs_server *server = data;
	wl_display_terminate(server->display);
	return 0;
}

/* GOSAAB_TEST_CLICKS: a file the test appends "x y" lines to; each new line is one click. */
static struct wl_event_source *test_click_timer;
static long test_click_offset;

static int test_click_tick(void *data) {
	struct gs_server *server = data;
	FILE *f = fopen(getenv("GOSAAB_TEST_CLICKS"), "r");
	if (f) {
		fseek(f, test_click_offset, SEEK_SET);
		char line[128];
		while (fgets(line, sizeof(line), f) != NULL && strchr(line, '\n') != NULL) {
			double x, y;
			if (strncmp(line, "overview", 8) == 0) {
				overview_set(server, !server->overview, NULL);
			} else if (sscanf(line, "%lf %lf", &x, &y) == 2) {
				wlr_cursor_warp(server->cursor, NULL, x, y);
				press_at(server, x, y);
				server->cursor_mode = CURSOR_PASSTHROUGH;
				server->grabbed = NULL;
			}
			schedule_frames(server);
			test_click_offset = ftell(f);
		}
		fclose(f);
	}
	wl_event_source_timer_update(test_click_timer, 100);
	return 0;
}

/* X11 apps (Steam, Wine, older games) run through xwayland-satellite, which turns each X11
 * window into a normal Wayland window, so they get Gill-OSaab title bars and animations too. */
static bool in_path(const char *program) {
	const char *path = getenv("PATH");
	if (path == NULL) {
		path = "/usr/local/bin:/usr/bin:/bin";
	}
	char dirs[4096];
	snprintf(dirs, sizeof(dirs), "%s", path);
	for (char *save = NULL, *dir = strtok_r(dirs, ":", &save); dir; dir = strtok_r(NULL, ":", &save)) {
		char full[4352];
		snprintf(full, sizeof(full), "%s/%s", dir, program);
		if (access(full, X_OK) == 0) {
			return true;
		}
	}
	return false;
}

static void start_xwayland(void) {
	/* (not system(): SIGCHLD is ignored, so system() can't report the result) */
	if (getenv("GOSAAB_NO_XWAYLAND") || !in_path("xwayland-satellite")) {
		return;
	}
	for (int n = 0; n < 32; n++) {
		char sock[64], lock[64];
		snprintf(sock, sizeof(sock), "/tmp/.X11-unix/X%d", n);
		snprintf(lock, sizeof(lock), "/tmp/.X%d-lock", n);
		if (access(sock, F_OK) == 0 || access(lock, F_OK) == 0) {
			continue;
		}
		char display[16], cmd[64];
		snprintf(display, sizeof(display), ":%d", n);
		snprintf(cmd, sizeof(cmd), "exec xwayland-satellite %s", display);
		setenv("DISPLAY", display, true);
		spawn(cmd);
		const char *runtime = getenv("XDG_RUNTIME_DIR");
		if (runtime) { /* lets tests and helper scripts find the X11 display */
			char path[512];
			snprintf(path, sizeof(path), "%s/gosaab-wm.display", runtime);
			FILE *f = fopen(path, "w");
			if (f) {
				fprintf(f, "%s\n", display);
				fclose(f);
			}
		}
		wlr_log(WLR_INFO, "X11 apps: xwayland-satellite on DISPLAY=%s", display);
		return;
	}
}

static void write_socket_file(const char *socket) {
	const char *runtime = getenv("XDG_RUNTIME_DIR");
	if (runtime == NULL) {
		return;
	}
	char path[512];
	snprintf(path, sizeof(path), "%s/gosaab-wm.socket", runtime);
	FILE *f = fopen(path, "w");
	if (f) {
		fprintf(f, "%s\n", socket);
		fclose(f);
	}
}

/* ------------------------------------------------------------------ main */

int main(int argc, char *argv[]) {
	wlr_log_init(getenv("GOSAAB_WM_DEBUG") ? WLR_DEBUG : WLR_INFO, NULL);
	char *startup_cmd = NULL;
	int c;
	while ((c = getopt(argc, argv, "s:hv")) != -1) {
		switch (c) {
		case 's':
			startup_cmd = optarg;
			break;
		case 'v':
			printf("gosaab-wm %s\n", GOSAAB_WM_VERSION);
			return 0;
		default:
			printf("Usage: %s [-s startup command]\n", argv[0]);
			return 0;
		}
	}

	struct gs_server server = {0};
	server.scale = 1.0f;
	server.display = wl_display_create();
	struct wl_event_loop *loop = wl_display_get_event_loop(server.display);
	server.backend = wlr_backend_autocreate(loop, NULL);
	if (server.backend == NULL) {
		wlr_log(WLR_ERROR, "failed to create backend");
		return 1;
	}
	/* GOSAAB_RENDER_CARD lets tests render on a virtual KMS card (vkms) */
	const char *card = getenv("GOSAAB_RENDER_CARD");
	if (card != NULL) {
		int fd = open(card, O_RDWR | O_CLOEXEC);
		server.renderer = fd >= 0 ? fx_renderer_create_with_drm_fd(fd) : NULL;
	} else {
		server.renderer = fx_renderer_create(server.backend);
	}
	if (server.renderer == NULL) {
		wlr_log(WLR_ERROR, "failed to create renderer");
		return 1;
	}
	wlr_renderer_init_wl_display(server.renderer, server.display);
	server.allocator = wlr_allocator_autocreate(server.backend, server.renderer);
	if (server.allocator == NULL) {
		wlr_log(WLR_ERROR, "failed to create allocator");
		return 1;
	}

	wlr_compositor_create(server.display, 6, server.renderer);
	wlr_subcompositor_create(server.display);
	wlr_data_device_manager_create(server.display);
	wlr_primary_selection_v1_device_manager_create(server.display);
	wlr_data_control_manager_v1_create(server.display);
	wlr_viewporter_create(server.display);
	wlr_single_pixel_buffer_manager_v1_create(server.display);
	wlr_fractional_scale_manager_v1_create(server.display, 1);
	wlr_presentation_create(server.display, server.backend, 2);
	wlr_export_dmabuf_manager_v1_create(server.display);
	wlr_screencopy_manager_v1_create(server.display);
	wlr_gamma_control_manager_v1_create(server.display);
	wlr_idle_notifier_v1_create(server.display);
	wlr_idle_inhibit_v1_create(server.display);

	server.output_layout = wlr_output_layout_create(server.display);
	wlr_xdg_output_manager_v1_create(server.display, server.output_layout);
	wl_list_init(&server.outputs);
	server.new_output.notify = server_new_output;
	wl_signal_add(&server.backend->events.new_output, &server.new_output);

	/* Scene layers, bottom to top */
	server.scene = wlr_scene_create();
	server.scene_layout = wlr_scene_attach_output_layout(server.scene, server.output_layout);
	/* macOS-like frosted glass: soft, slightly darkened, colours a little more vivid */
	wlr_scene_set_blur_data(server.scene, 3, 6, 0.02f, 0.92f, 0.92f, 1.35f);
	server.layers.background = wlr_scene_tree_create(&server.scene->tree);
	server.layers.backdrop = wlr_scene_rect_create(server.layers.background, 0, 0,
		(float[4]){ 0.04f, 0.05f, 0.10f, 1.0f });
	server.layers.bottom = wlr_scene_tree_create(&server.scene->tree);
	server.layers.dim = wlr_scene_tree_create(&server.scene->tree);
	server.layers.dim_rect = wlr_scene_rect_create(server.layers.dim, 0, 0, (float[4]){ 0, 0, 0, 0 });
	wlr_scene_node_set_enabled(&server.layers.dim_rect->node, false);
	server.layers.blur = wlr_scene_optimized_blur_create(&server.scene->tree, 0, 0);
	server.layers.toplevels = wlr_scene_tree_create(&server.scene->tree);
	server.layers.closing = wlr_scene_tree_create(&server.scene->tree);
	server.layers.top = wlr_scene_tree_create(&server.scene->tree);
	server.layers.overlay = wlr_scene_tree_create(&server.scene->tree);
	server.lock_tree = wlr_scene_tree_create(&server.scene->tree);
	server.lock_bg = wlr_scene_rect_create(server.lock_tree, 0, 0, (float[4]){ 0.02f, 0.02f, 0.04f, 1.0f });
	wlr_scene_node_set_enabled(&server.lock_tree->node, false);

	wl_list_init(&server.toplevels);
	wl_list_init(&server.closing);
	server.xdg_shell = wlr_xdg_shell_create(server.display, 6);
	server.new_xdg_toplevel.notify = server_new_xdg_toplevel;
	wl_signal_add(&server.xdg_shell->events.new_toplevel, &server.new_xdg_toplevel);
	server.new_xdg_popup.notify = server_new_xdg_popup;
	wl_signal_add(&server.xdg_shell->events.new_popup, &server.new_xdg_popup);

	wl_list_init(&server.layer_surfaces);
	server.layer_shell = wlr_layer_shell_v1_create(server.display, 4);
	server.new_layer_surface.notify = server_new_layer_surface;
	wl_signal_add(&server.layer_shell->events.new_surface, &server.new_layer_surface);

	server.foreign_mgr = wlr_foreign_toplevel_manager_v1_create(server.display);
	server.relative_pointer_mgr = wlr_relative_pointer_manager_v1_create(server.display);
	server.pointer_constraints = wlr_pointer_constraints_v1_create(server.display);
	server.new_constraint.notify = handle_new_constraint;
	wl_signal_add(&server.pointer_constraints->events.new_constraint, &server.new_constraint);
	server.xdg_activation = wlr_xdg_activation_v1_create(server.display);
	server.request_activate.notify = handle_request_activate;
	wl_signal_add(&server.xdg_activation->events.request_activate, &server.request_activate);
	server.lock_mgr = wlr_session_lock_manager_v1_create(server.display);
	server.new_lock.notify = handle_new_lock;
	wl_signal_add(&server.lock_mgr->events.new_lock, &server.new_lock);
	server.decoration_mgr = wlr_xdg_decoration_manager_v1_create(server.display);
	server.new_decoration.notify = handle_new_decoration;
	wl_signal_add(&server.decoration_mgr->events.new_toplevel_decoration, &server.new_decoration);

	server.cursor = wlr_cursor_create();
	wlr_cursor_attach_output_layout(server.cursor, server.output_layout);
	server.cursor_mgr = wlr_xcursor_manager_create(getenv("XCURSOR_THEME"), 24);
	server.cursor_shape_mgr = wlr_cursor_shape_manager_v1_create(server.display, 1);
	server.request_cursor_shape.notify = request_cursor_shape;
	wl_signal_add(&server.cursor_shape_mgr->events.request_set_shape, &server.request_cursor_shape);
	server.cursor_motion.notify = cursor_motion;
	wl_signal_add(&server.cursor->events.motion, &server.cursor_motion);
	server.cursor_motion_absolute.notify = cursor_motion_absolute;
	wl_signal_add(&server.cursor->events.motion_absolute, &server.cursor_motion_absolute);
	server.cursor_button.notify = cursor_button;
	wl_signal_add(&server.cursor->events.button, &server.cursor_button);
	server.cursor_axis.notify = cursor_axis;
	wl_signal_add(&server.cursor->events.axis, &server.cursor_axis);
	server.cursor_frame.notify = cursor_frame;
	wl_signal_add(&server.cursor->events.frame, &server.cursor_frame);

	wl_list_init(&server.keyboards);
	server.new_input.notify = server_new_input;
	wl_signal_add(&server.backend->events.new_input, &server.new_input);
	server.seat = wlr_seat_create(server.display, "seat0");
	server.request_cursor.notify = seat_request_cursor;
	wl_signal_add(&server.seat->events.request_set_cursor, &server.request_cursor);
	server.request_set_selection.notify = seat_request_set_selection;
	wl_signal_add(&server.seat->events.request_set_selection, &server.request_set_selection);
	server.request_set_primary_selection.notify = seat_request_set_primary_selection;
	wl_signal_add(&server.seat->events.request_set_primary_selection, &server.request_set_primary_selection);

	wl_event_loop_add_signal(loop, SIGUSR1, handle_sigusr1, &server);
	wl_event_loop_add_signal(loop, SIGUSR2, handle_sigusr2, &server);
	wl_event_loop_add_signal(loop, SIGRTMIN + 1, handle_sigoverview, &server); /* the shell asks for Mission Control */
	wl_event_loop_add_signal(loop, SIGTERM, handle_sigterm, &server);
	wl_event_loop_add_signal(loop, SIGINT, handle_sigterm, &server);
	signal(SIGCHLD, SIG_IGN);
	signal(SIGPIPE, SIG_IGN); /* a client vanishing mid-write must never take the desktop down */
	if (getenv("GOSAAB_TEST_CLICKS")) {
		test_click_timer = wl_event_loop_add_timer(loop, test_click_tick, &server);
		wl_event_source_timer_update(test_click_timer, 100);
	}

	const char *socket = wl_display_add_socket_auto(server.display);
	if (!socket) {
		wlr_backend_destroy(server.backend);
		return 1;
	}
	if (!wlr_backend_start(server.backend)) {
		wlr_backend_destroy(server.backend);
		wl_display_destroy(server.display);
		return 1;
	}
	setenv("WAYLAND_DISPLAY", socket, true);
	setenv("XDG_CURRENT_DESKTOP", "Gill-OSaab", true);
	start_xwayland();
	write_socket_file(socket);
	spawn(startup_cmd);
	wlr_log(WLR_INFO, "gosaab-wm %s running on WAYLAND_DISPLAY=%s", GOSAAB_WM_VERSION, socket);
	wl_display_run(server.display);

	if (test_click_timer) {
		wl_event_source_remove(test_click_timer);
	}
	wl_display_destroy_clients(server.display);
	struct wl_listener *server_listeners[] = {
		&server.new_xdg_toplevel, &server.new_xdg_popup, &server.new_layer_surface, &server.new_decoration,
		&server.cursor_motion, &server.cursor_motion_absolute, &server.cursor_button, &server.cursor_axis,
		&server.cursor_frame, &server.request_cursor_shape, &server.new_input, &server.request_cursor,
		&server.request_set_selection, &server.request_set_primary_selection, &server.new_output,
		&server.new_constraint, &server.request_activate, &server.new_lock,
	};
	for (size_t i = 0; i < sizeof(server_listeners) / sizeof(server_listeners[0]); i++) {
		wl_list_remove(&server_listeners[i]->link);
	}
	wlr_scene_node_destroy(&server.scene->tree.node);
	wlr_xcursor_manager_destroy(server.cursor_mgr);
	wlr_cursor_destroy(server.cursor);
	wlr_allocator_destroy(server.allocator);
	wlr_renderer_destroy(server.renderer);
	wlr_backend_destroy(server.backend);
	wl_display_destroy(server.display);
	return 0;
}
