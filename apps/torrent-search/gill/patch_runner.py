"""Adapt Flutter's generated Linux runner for Gill(OS): undecorated window (the app draws Gill(OS)
window buttons), a 'gill/window' channel for drag / minimise / zoom / full screen / close, the
app id the Dock knows, and a size that suits both handhelds and desktops."""
import re
import sys
from pathlib import Path

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
cm = root / "linux/CMakeLists.txt"
s = cm.read_text()
s = re.sub(r'set\(BINARY_NAME "[^"]*"\)', 'set(BINARY_NAME "torrent-search-engine")', s)
s = re.sub(r'set\(APPLICATION_ID "[^"]*"\)', 'set(APPLICATION_ID "org.gillosaab.TorrentSearch")', s)
cm.write_text(s)

app = root / "linux/runner/my_application.cc"
if not app.exists():
    app = root / "linux/my_application.cc"
s = app.read_text()

channel = r'''
// ---- Gill(OS) window channel: the app draws its own title bar with Gill(OS) buttons
static void gill_window_call(FlMethodChannel* channel, FlMethodCall* call, gpointer user_data) {
  GtkWindow* window = GTK_WINDOW(user_data);
  const gchar* m = fl_method_call_get_name(call);
  GdkWindow* gdk = gtk_widget_get_window(GTK_WIDGET(window));
  if (strcmp(m, "startDrag") == 0 && gdk != nullptr) {
    GdkSeat* seat = gdk_display_get_default_seat(gtk_widget_get_display(GTK_WIDGET(window)));
    GdkDevice* pointer = gdk_seat_get_pointer(seat);
    gint x = 0, y = 0;
    gdk_window_get_device_position(gdk, pointer, &x, &y, nullptr);
    gint ox = 0, oy = 0;
    gdk_window_get_origin(gdk, &ox, &oy);
    gtk_window_begin_move_drag(window, 1, ox + x, oy + y, GDK_CURRENT_TIME);
  } else if (strcmp(m, "minimize") == 0) {
    gtk_window_iconify(window);
  } else if (strcmp(m, "zoom") == 0) {
    if (gtk_window_is_maximized(window)) gtk_window_unmaximize(window); else gtk_window_maximize(window);
  } else if (strcmp(m, "fullscreen") == 0 && gdk != nullptr) {
    if (gdk_window_get_state(gdk) & GDK_WINDOW_STATE_FULLSCREEN) gtk_window_unfullscreen(window);
    else gtk_window_fullscreen(window);
  } else if (strcmp(m, "close") == 0) {
    gtk_window_close(window);
  }
  fl_method_call_respond_success(call, nullptr, nullptr);
}
'''
anchor = "static void my_application_activate(GApplication* application) {"
assert anchor in s, "activate() not found"
s = s.replace(anchor, channel + "\n" + anchor, 1)

if "#include <string.h>" not in s:
    s = "#include <string.h>\n" + s

m = re.search(r"GtkWindow\* window =\s*GTK_WINDOW\(gtk_application_window_new\(GTK_APPLICATION\(application\)\)\);", s)
assert m, "window creation not found"
s = s[:m.end()] + "\n  gtk_window_set_decorated(window, FALSE);  // Gill(OS) buttons are drawn by the app" + s[m.end():]

s = s.replace("gboolean use_header_bar = TRUE;", "gboolean use_header_bar = FALSE;")
s = re.sub(r"gtk_window_set_default_size\(window, \d+, \d+\);",
           "gtk_window_set_default_size(window, 1180, 760);\n  "
           "{ GdkGeometry g = {}; g.min_width = 720; g.min_height = 480;\n"
           "    gtk_window_set_geometry_hints(window, nullptr, &g, GDK_HINT_MIN_SIZE); }", s, count=1)
s = re.sub(r'gtk_window_set_title\(window, "[^"]*"\);', 'gtk_window_set_title(window, "Torrent Search Engine");', s)

reg = re.search(r"fl_register_plugins\(FL_PLUGIN_REGISTRY\((\w+)\)\);", s)
assert reg, "plugin registration not found"
view = reg.group(1)
s = s[:reg.end()] + f'''
  {{
    g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
    FlMethodChannel* gill = fl_method_channel_new(
        fl_engine_get_binary_messenger(fl_view_get_engine({view})), "gill/window", FL_METHOD_CODEC(codec));
    fl_method_channel_set_method_call_handler(gill, gill_window_call, window, nullptr);
    g_object_set_data_full(G_OBJECT(window), "gill-channel", gill, g_object_unref);
  }}''' + s[reg.end():]
app.write_text(s)
print("patched", app)
