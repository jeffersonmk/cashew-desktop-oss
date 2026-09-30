#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  FlMethodChannel* window_channel;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// ---------------------------------------------------------------------------
// Cashew Desktop: remember the window size (and position where the system
// allows it) between runs. Stored in
//   ~/.config/io.github.jeffersonmk.CashewDesktop/window.ini
// Wayland does not let apps read or set their own position, so there only the
// size and the maximized state are restored; on X11 the position is too.
// ---------------------------------------------------------------------------
static const gint kDefaultWidth = 1280;
static const gint kDefaultHeight = 720;
static const gint kMinSize = 360;

static gchar* window_state_path() {
  return g_build_filename(g_get_user_config_dir(), APPLICATION_ID,
                          "window.ini", nullptr);
}

static gboolean running_on_x11(GtkWindow* window) {
#ifdef GDK_WINDOWING_X11
  return GDK_IS_X11_DISPLAY(gtk_widget_get_display(GTK_WIDGET(window)));
#else
  return FALSE;
#endif
}

static void restore_window_state(GtkWindow* window) {
  gint width = kDefaultWidth, height = kDefaultHeight;
  g_autofree gchar* path = window_state_path();
  g_autoptr(GKeyFile) file = g_key_file_new();
  if (!g_key_file_load_from_file(file, path, G_KEY_FILE_NONE, nullptr)) {
    gtk_window_set_default_size(window, width, height);
    return;
  }
  g_autoptr(GError) error = nullptr;
  gint w = g_key_file_get_integer(file, "window", "width", &error);
  if (error == nullptr && w >= kMinSize) width = w;
  g_clear_error(&error);
  gint h = g_key_file_get_integer(file, "window", "height", &error);
  if (error == nullptr && h >= kMinSize) height = h;
  g_clear_error(&error);
  gtk_window_set_default_size(window, width, height);

  if (running_on_x11(window) && g_key_file_has_key(file, "window", "x", nullptr) &&
      g_key_file_has_key(file, "window", "y", nullptr)) {
    gint x = g_key_file_get_integer(file, "window", "x", nullptr);
    gint y = g_key_file_get_integer(file, "window", "y", nullptr);
    // Only restore the position if it is still on a connected monitor.
    GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(window));
    GdkMonitor* monitor = gdk_display_get_monitor_at_point(display, x + 50, y + 50);
    if (monitor != nullptr) {
      GdkRectangle area;
      gdk_monitor_get_workarea(monitor, &area);
      if (x + 50 >= area.x && y + 50 >= area.y &&
          x + 50 < area.x + area.width && y + 50 < area.y + area.height) {
        gtk_window_move(window, x, y);
      }
    }
  }

  if (g_key_file_get_boolean(file, "window", "maximized", nullptr)) {
    gtk_window_maximize(window);
  }
}

static void save_window_state(GtkWindow* window) {
  g_autofree gchar* path = window_state_path();
  g_autofree gchar* dir = g_path_get_dirname(path);
  g_mkdir_with_parents(dir, 0700);

  g_autoptr(GKeyFile) file = g_key_file_new();
  // Keep the last normal size when closing while maximized.
  g_key_file_load_from_file(file, path, G_KEY_FILE_NONE, nullptr);

  // Tiling compositors (e.g. Hyprland) report every window as maximized and
  // tiled, even floating ones. Only treat the window as maximized when it is
  // maximized and not tiled; otherwise remember its current size.
  GdkWindow* gdk_window = gtk_widget_get_window(GTK_WIDGET(window));
  GdkWindowState state =
      gdk_window != nullptr ? gdk_window_get_state(gdk_window)
                            : (GdkWindowState)0;
  gboolean tiled = (state & GDK_WINDOW_STATE_TILED) != 0;
  gboolean maximized = gtk_window_is_maximized(window) && !tiled;
  g_key_file_set_boolean(file, "window", "maximized", maximized);
  if (!maximized) {
    gint width = 0, height = 0;
    gtk_window_get_size(window, &width, &height);
    if (width >= kMinSize && height >= kMinSize) {
      g_key_file_set_integer(file, "window", "width", width);
      g_key_file_set_integer(file, "window", "height", height);
    }
    if (running_on_x11(window)) {
      gint x = 0, y = 0;
      gtk_window_get_position(window, &x, &y);
      g_key_file_set_integer(file, "window", "x", x);
      g_key_file_set_integer(file, "window", "y", y);
    }
  }

  g_autoptr(GError) error = nullptr;
  if (!g_key_file_save_to_file(file, path, &error)) {
    g_warning("Could not save window state: %s", error->message);
  }
}

// Cashew Desktop: closing the window used to crash the app (segfault inside
// the Flutter engine while GTK destroyed the window). Instead of letting GTK
// destroy the window, hide it and stop the application's main loop; the
// process then exits normally from main().
static gboolean on_window_delete(GtkWidget* widget, GdkEvent* event,
                                 gpointer user_data) {
  save_window_state(GTK_WINDOW(widget));
  gtk_widget_hide(widget);
  g_application_quit(G_APPLICATION(user_data));
  return TRUE;  // don't destroy the window
}

// Cashew Desktop: "cashew/window" channel so Dart can close the app safely
// (Ctrl+Q). SystemNavigator.pop destroys the window, which crashes the
// engine; "quit" goes through the same path as the close button instead.
static void window_method_call_cb(FlMethodChannel* channel,
                                  FlMethodCall* method_call,
                                  gpointer user_data) {
  GtkWindow* window = GTK_WINDOW(user_data);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (g_strcmp0(fl_method_call_get_name(method_call), "quit") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    fl_method_call_respond(method_call, response, nullptr);
    GApplication* app = G_APPLICATION(gtk_window_get_application(window));
    save_window_state(window);
    gtk_widget_hide(GTK_WIDGET(window));
    g_application_quit(app);
    return;
  }
  response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  fl_method_call_respond(method_call, response, nullptr);
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Cashew Desktop");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Cashew Desktop");
  }

  restore_window_state(window);

  // Window icon (taskbar / alt-tab). Installed next to the binary under
  // data/, so it works both from the build folder and once packaged.
  {
    g_autofree gchar* exe_path = g_file_read_link("/proc/self/exe", nullptr);
    if (exe_path != nullptr) {
      g_autofree gchar* exe_dir = g_path_get_dirname(exe_path);
      g_autofree gchar* icon_path =
          g_build_filename(exe_dir, "data", "app_icon.png", nullptr);
      gtk_window_set_icon_from_file(window, icon_path, nullptr);
    }
  }
  g_signal_connect(window, "delete-event", G_CALLBACK(on_window_delete),
                   application);
  gtk_widget_show(GTK_WIDGET(window));

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_clear_object(&self->window_channel);
  self->window_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "cashew/window", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->window_channel, window_method_call_cb, window, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application, gchar*** arguments, int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
     g_warning("Failed to register: %s", error->message);
     *exit_status = 1;
     return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  //MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // Quitting without closing the window (e.g. Ctrl+Q) skips delete-event, so
  // save the window state here too if the window is still visible.
  for (GList* l = gtk_application_get_windows(GTK_APPLICATION(application));
       l != nullptr; l = l->next) {
    GtkWindow* window = GTK_WINDOW(l->data);
    if (gtk_widget_get_visible(GTK_WIDGET(window))) {
      save_window_state(window);
      gtk_widget_hide(GTK_WIDGET(window));
    }
  }

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->window_channel);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line = my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Use the application id as the Wayland app_id / X11 WM_CLASS so desktop
  // environments match the window with the installed .desktop file and icon.
  g_set_prgname(APPLICATION_ID);
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID,
                                     "flags", G_APPLICATION_NON_UNIQUE,
                                     nullptr));
}
