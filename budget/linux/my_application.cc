#include "my_application.h"

#include <dlfcn.h>
#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  FlMethodChannel* window_channel;
  GtkWindow* window;
  // Tray icon (AppIndicator / StatusNotifierItem), nullptr when disabled.
  GObject* indicator;
  gboolean close_to_tray;
  // Started with --minimized (e.g. from autostart): keep the window hidden.
  gboolean start_minimized;
  // Desktop notifications: notification id -> payload for Dart.
  GHashTable* notification_payloads;
  guint notification_action_signal;
  guint notification_closed_signal;
  // Translated labels sent by Dart ("setLabels"); English until then.
  gchar* label_open_app;
  gchar* label_quit;
  gchar* label_notification_open;
  GtkWidget* tray_open_item;
  GtkWidget* tray_quit_item;
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

// Path of a file shipped in the bundle's data/ folder (next to the binary),
// so it works both from the build folder and inside the AppImage.
static gchar* bundle_data_file(const gchar* name) {
  g_autofree gchar* exe_path = g_file_read_link("/proc/self/exe", nullptr);
  if (exe_path == nullptr) return nullptr;
  g_autofree gchar* exe_dir = g_path_get_dirname(exe_path);
  return g_build_filename(exe_dir, "data", name, nullptr);
}

static void invoke_dart(MyApplication* self, const gchar* method,
                        FlValue* args) {
  if (self->window_channel == nullptr) return;
  fl_method_channel_invoke_method(self->window_channel, method, args, nullptr,
                                  nullptr, nullptr);
}

// ---------------------------------------------------------------------------
// Drag and drop: files dropped on the window are sent to Dart ("filesDropped"
// with a list of local paths). Only file:// URIs are accepted.
// ---------------------------------------------------------------------------

static void on_drag_data_received(GtkWidget* widget, GdkDragContext* context,
                                  gint x, gint y, GtkSelectionData* data,
                                  guint info, guint time, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  g_auto(GStrv) uris = gtk_selection_data_get_uris(data);
  g_autoptr(FlValue) paths = fl_value_new_list();
  if (uris != nullptr) {
    for (gint i = 0; uris[i] != nullptr; i++) {
      g_autofree gchar* path = g_filename_from_uri(uris[i], nullptr, nullptr);
      if (path != nullptr) fl_value_append_take(paths, fl_value_new_string(path));
    }
  }
  gboolean ok = fl_value_get_length(paths) > 0;
  if (ok) {
    g_autoptr(FlValue) args = fl_value_new_map();
    fl_value_set_string_take(args, "paths", fl_value_ref(paths));
    // Flutter coordinates are logical pixels, same as GTK widget coordinates.
    fl_value_set_string_take(args, "x", fl_value_new_float(x));
    fl_value_set_string_take(args, "y", fl_value_new_float(y));
    invoke_dart(self, "filesDropped", args);
  }
  gtk_drag_finish(context, ok, FALSE, time);
}

static void setup_drag_and_drop(MyApplication* self, GtkWidget* target) {
  gtk_drag_dest_set(target, GTK_DEST_DEFAULT_ALL, nullptr, 0, GDK_ACTION_COPY);
  gtk_drag_dest_add_uri_targets(target);
  g_signal_connect(target, "drag-data-received",
                   G_CALLBACK(on_drag_data_received), self);
}

static void show_main_window(MyApplication* self) {
  if (self->window == nullptr) return;
  self->start_minimized = FALSE;
  gtk_widget_set_opacity(GTK_WIDGET(self->window), 1.0);
  gtk_widget_show(GTK_WIDGET(self->window));
  gtk_window_present(self->window);
  invoke_dart(self, "windowShown", nullptr);
}

// Save the window size, hide the window and stop the main loop; the process
// then exits normally from main(). Letting GTK destroy the window crashed the
// Flutter engine (segfault on close), so the window is never destroyed.
static void quit_app(MyApplication* self) {
  if (self->window != nullptr &&
      gtk_widget_get_visible(GTK_WIDGET(self->window))) {
    save_window_state(self->window);
    gtk_widget_hide(GTK_WIDGET(self->window));
  }
  g_application_quit(G_APPLICATION(self));
}

// ---------------------------------------------------------------------------
// Cashew Desktop: tray icon.
// libayatana-appindicator is loaded at runtime (dlopen) so the app still runs
// on systems without it; the option is then shown as unavailable.
// ---------------------------------------------------------------------------
typedef GObject* (*AppIndicatorNewFn)(const gchar*, const gchar*, int);
typedef void (*AppIndicatorSetStatusFn)(GObject*, int);
typedef void (*AppIndicatorSetMenuFn)(GObject*, GtkMenu*);
typedef void (*AppIndicatorSetTitleFn)(GObject*, const gchar*);
typedef void (*AppIndicatorSetIconThemePathFn)(GObject*, const gchar*);
typedef void (*AppIndicatorSetSecondaryTargetFn)(GObject*, GtkWidget*);

static struct {
  gboolean tried;
  gboolean loaded;
  AppIndicatorNewFn new_indicator;
  AppIndicatorSetStatusFn set_status;
  AppIndicatorSetMenuFn set_menu;
  AppIndicatorSetTitleFn set_title;
  AppIndicatorSetIconThemePathFn set_icon_theme_path;
  AppIndicatorSetSecondaryTargetFn set_secondary_activate_target;
} appindicator;

static const int kIndicatorCategoryApplicationStatus = 0;
static const int kIndicatorStatusActive = 1;

static gboolean load_appindicator() {
  if (appindicator.tried) return appindicator.loaded;
  appindicator.tried = TRUE;
  const char* libraries[] = {"libayatana-appindicator3.so.1",
                             "libappindicator3.so.1", nullptr};
  for (int i = 0; libraries[i] != nullptr; i++) {
    void* handle = dlopen(libraries[i], RTLD_NOW | RTLD_LOCAL);
    if (handle == nullptr) continue;
    appindicator.new_indicator =
        (AppIndicatorNewFn)dlsym(handle, "app_indicator_new");
    appindicator.set_status =
        (AppIndicatorSetStatusFn)dlsym(handle, "app_indicator_set_status");
    appindicator.set_menu =
        (AppIndicatorSetMenuFn)dlsym(handle, "app_indicator_set_menu");
    appindicator.set_title =
        (AppIndicatorSetTitleFn)dlsym(handle, "app_indicator_set_title");
    appindicator.set_icon_theme_path = (AppIndicatorSetIconThemePathFn)dlsym(
        handle, "app_indicator_set_icon_theme_path");
    appindicator.set_secondary_activate_target =
        (AppIndicatorSetSecondaryTargetFn)dlsym(
            handle, "app_indicator_set_secondary_activate_target");
    if (appindicator.new_indicator && appindicator.set_status &&
        appindicator.set_menu) {
      appindicator.loaded = TRUE;
      return TRUE;
    }
    dlclose(handle);
  }
  return FALSE;
}

static gboolean session_bus_name_has_owner(const gchar* name) {
  g_autoptr(GDBusConnection) bus =
      g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, nullptr);
  if (bus == nullptr) return FALSE;
  g_autoptr(GVariant) result = g_dbus_connection_call_sync(
      bus, "org.freedesktop.DBus", "/org/freedesktop/DBus",
      "org.freedesktop.DBus", "NameHasOwner", g_variant_new("(s)", name),
      G_VARIANT_TYPE("(b)"), G_DBUS_CALL_FLAGS_NONE, 1000, nullptr, nullptr);
  if (result == nullptr) return FALSE;
  gboolean has_owner = FALSE;
  g_variant_get(result, "(b)", &has_owner);
  return has_owner;
}

// A tray needs the AppIndicator library and a panel that shows tray icons
// (StatusNotifierWatcher on the session bus).
static gboolean tray_available() {
  return load_appindicator() &&
         session_bus_name_has_owner("org.kde.StatusNotifierWatcher");
}

static void on_tray_open(GtkMenuItem* item, gpointer user_data) {
  show_main_window(MY_APPLICATION(user_data));
}

static void on_tray_quit(GtkMenuItem* item, gpointer user_data) {
  quit_app(MY_APPLICATION(user_data));
}

static void enable_tray(MyApplication* self) {
  if (self->indicator != nullptr || !tray_available()) return;
  // The icon is looked up by name in the bundle's data/ folder.
  g_autofree gchar* icon_path = bundle_data_file("app_icon.png");
  g_autofree gchar* icon_dir =
      icon_path != nullptr ? g_path_get_dirname(icon_path) : nullptr;
  self->indicator = appindicator.new_indicator(
      APPLICATION_ID, "app_icon", kIndicatorCategoryApplicationStatus);
  if (self->indicator == nullptr) return;
  if (appindicator.set_icon_theme_path != nullptr && icon_dir != nullptr) {
    appindicator.set_icon_theme_path(self->indicator, icon_dir);
  }
  if (appindicator.set_title != nullptr) {
    appindicator.set_title(self->indicator, "Cashew Desktop");
  }

  GtkWidget* menu = gtk_menu_new();
  GtkWidget* open_item = gtk_menu_item_new_with_label(
      self->label_open_app != nullptr ? self->label_open_app
                                      : "Open Cashew Desktop");
  self->tray_open_item = open_item;
  g_signal_connect(open_item, "activate", G_CALLBACK(on_tray_open), self);
  gtk_menu_shell_append(GTK_MENU_SHELL(menu), open_item);
  gtk_menu_shell_append(GTK_MENU_SHELL(menu), gtk_separator_menu_item_new());
  GtkWidget* quit_item = gtk_menu_item_new_with_label(
      self->label_quit != nullptr ? self->label_quit : "Quit");
  self->tray_quit_item = quit_item;
  g_signal_connect(quit_item, "activate", G_CALLBACK(on_tray_quit), self);
  gtk_menu_shell_append(GTK_MENU_SHELL(menu), quit_item);
  gtk_widget_show_all(menu);
  appindicator.set_menu(self->indicator, GTK_MENU(menu));
  // Middle click opens the window directly.
  if (appindicator.set_secondary_activate_target != nullptr) {
    appindicator.set_secondary_activate_target(self->indicator, open_item);
  }
  appindicator.set_status(self->indicator, kIndicatorStatusActive);
}

static void disable_tray(MyApplication* self) {
  g_clear_object(&self->indicator);
  self->tray_open_item = nullptr;
  self->tray_quit_item = nullptr;
}

// ---------------------------------------------------------------------------
// Cashew Desktop: desktop notifications (org.freedesktop.Notifications).
// Dart decides when to notify; clicking a notification opens the window and
// passes the payload back to Dart (same payloads as the mobile app).
// ---------------------------------------------------------------------------
static void on_notification_signal(GDBusConnection* connection,
                                   const gchar* sender,
                                   const gchar* object_path,
                                   const gchar* interface_name,
                                   const gchar* signal_name,
                                   GVariant* parameters, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (self->notification_payloads == nullptr) return;
  guint32 id = 0;
  if (g_strcmp0(signal_name, "ActionInvoked") == 0) {
    const gchar* action = nullptr;
    g_variant_get(parameters, "(u&s)", &id, &action);
    const gchar* payload = (const gchar*)g_hash_table_lookup(
        self->notification_payloads, GUINT_TO_POINTER(id));
    if (payload == nullptr) return;
    show_main_window(self);
    g_autoptr(FlValue) args = fl_value_new_string(payload);
    invoke_dart(self, "notificationClicked", args);
  } else if (g_strcmp0(signal_name, "NotificationClosed") == 0) {
    guint32 reason = 0;
    g_variant_get(parameters, "(uu)", &id, &reason);
    g_hash_table_remove(self->notification_payloads, GUINT_TO_POINTER(id));
  }
}

static void subscribe_notification_signals(MyApplication* self) {
  if (self->notification_payloads != nullptr) return;
  self->notification_payloads =
      g_hash_table_new_full(g_direct_hash, g_direct_equal, nullptr, g_free);
  g_autoptr(GDBusConnection) bus =
      g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, nullptr);
  if (bus == nullptr) return;
  self->notification_action_signal = g_dbus_connection_signal_subscribe(
      bus, nullptr, "org.freedesktop.Notifications", "ActionInvoked",
      "/org/freedesktop/Notifications", nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
      on_notification_signal, self, nullptr);
  self->notification_closed_signal = g_dbus_connection_signal_subscribe(
      bus, nullptr, "org.freedesktop.Notifications", "NotificationClosed",
      "/org/freedesktop/Notifications", nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
      on_notification_signal, self, nullptr);
}

// Returns the notification id, or 0 on failure.
static guint32 show_notification(MyApplication* self, const gchar* title,
                                 const gchar* body, const gchar* payload) {
  subscribe_notification_signals(self);
  g_autoptr(GDBusConnection) bus =
      g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, nullptr);
  if (bus == nullptr) return 0;

  g_autofree gchar* icon_path = bundle_data_file("app_icon.png");
  g_autofree gchar* icon_uri =
      icon_path != nullptr ? g_filename_to_uri(icon_path, nullptr, nullptr)
                           : nullptr;

  GVariantBuilder actions;
  g_variant_builder_init(&actions, G_VARIANT_TYPE("as"));
  if (payload != nullptr && payload[0] != '\0') {
    g_variant_builder_add(&actions, "s", "default");
    g_variant_builder_add(&actions, "s",
                          self->label_notification_open != nullptr
                              ? self->label_notification_open
                              : "Open");
  }
  GVariantBuilder hints;
  g_variant_builder_init(&hints, G_VARIANT_TYPE("a{sv}"));
  g_variant_builder_add(&hints, "{sv}", "desktop-entry",
                        g_variant_new_string(APPLICATION_ID));
  if (icon_path != nullptr) {
    g_variant_builder_add(&hints, "{sv}", "image-path",
                          g_variant_new_string(icon_path));
  }

  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) result = g_dbus_connection_call_sync(
      bus, "org.freedesktop.Notifications", "/org/freedesktop/Notifications",
      "org.freedesktop.Notifications", "Notify",
      g_variant_new("(susssasa{sv}i)", "Cashew Desktop", 0,
                    icon_uri != nullptr ? icon_uri : "", title, body, &actions,
                    &hints, -1),
      G_VARIANT_TYPE("(u)"), G_DBUS_CALL_FLAGS_NONE, 3000, nullptr, &error);
  if (result == nullptr) {
    g_warning("Could not show notification: %s", error->message);
    return 0;
  }
  guint32 id = 0;
  g_variant_get(result, "(u)", &id);
  if (id != 0 && payload != nullptr && payload[0] != '\0') {
    g_hash_table_insert(self->notification_payloads, GUINT_TO_POINTER(id),
                        g_strdup(payload));
  }
  return id;
}

static gboolean on_window_delete(GtkWidget* widget, GdkEvent* event,
                                 gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (self->close_to_tray && self->indicator != nullptr) {
    // Keep running in the tray (reminders keep working).
    save_window_state(GTK_WINDOW(widget));
    gtk_widget_hide(widget);
    return TRUE;
  }
  quit_app(self);
  return TRUE;  // don't destroy the window
}

static const gchar* map_string(FlValue* args, const gchar* key) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP)
    return nullptr;
  FlValue* value = fl_value_lookup_string(args, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_STRING)
    return nullptr;
  return fl_value_get_string(value);
}

// Cashew Desktop: "cashew/window" channel between Dart and the native side.
static void window_method_call_cb(FlMethodChannel* channel,
                                  FlMethodCall* method_call,
                                  gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (g_strcmp0(method, "quit") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    fl_method_call_respond(method_call, response, nullptr);
    quit_app(self);
    return;
  } else if (g_strcmp0(method, "capabilities") == 0) {
    g_autoptr(FlValue) result = fl_value_new_map();
    fl_value_set_string_take(result, "tray",
                             fl_value_new_bool(tray_available()));
    fl_value_set_string_take(
        result, "notifications",
        fl_value_new_bool(
            session_bus_name_has_owner("org.freedesktop.Notifications")));
    fl_value_set_string_take(result, "startedMinimized",
                             fl_value_new_bool(self->start_minimized));
    // Dart is running: finish the minimized start.
    if (self->start_minimized && self->window != nullptr) {
      gtk_widget_hide(GTK_WIDGET(self->window));
      gtk_widget_set_opacity(GTK_WIDGET(self->window), 1.0);
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (g_strcmp0(method, "setCloseToTray") == 0) {
    gboolean enabled = args != nullptr &&
                       fl_value_get_type(args) == FL_VALUE_TYPE_BOOL &&
                       fl_value_get_bool(args);
    self->close_to_tray = enabled;
    if (enabled) {
      enable_tray(self);
    } else {
      disable_tray(self);
    }
    // Started minimized but there is no tray to come back from: show it.
    if (self->indicator == nullptr && self->window != nullptr &&
        !gtk_widget_get_visible(GTK_WIDGET(self->window))) {
      show_main_window(self);
    }
    response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_bool(self->indicator != nullptr)));
  } else if (g_strcmp0(method, "notify") == 0) {
    const gchar* title = map_string(args, "title");
    const gchar* body = map_string(args, "body");
    const gchar* payload = map_string(args, "payload");
    guint32 id = show_notification(self, title != nullptr ? title : "",
                                   body != nullptr ? body : "", payload);
    response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_int(id)));
  } else if (g_strcmp0(method, "setLabels") == 0) {
    const gchar* open_app = map_string(args, "openApp");
    const gchar* quit = map_string(args, "quit");
    const gchar* notification_open = map_string(args, "notificationOpen");
    if (open_app != nullptr) {
      g_free(self->label_open_app);
      self->label_open_app = g_strdup(open_app);
      if (self->tray_open_item != nullptr)
        gtk_menu_item_set_label(GTK_MENU_ITEM(self->tray_open_item), open_app);
    }
    if (quit != nullptr) {
      g_free(self->label_quit);
      self->label_quit = g_strdup(quit);
      if (self->tray_quit_item != nullptr)
        gtk_menu_item_set_label(GTK_MENU_ITEM(self->tray_quit_item), quit);
    }
    if (notification_open != nullptr) {
      g_free(self->label_notification_open);
      self->label_notification_open = g_strdup(notification_open);
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "showWindow") == 0) {
    show_main_window(self);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  // Single instance: opening the app again (menu, autostart, tray) brings the
  // existing window back instead of starting a second copy.
  if (self->window != nullptr) {
    show_main_window(self);
    return;
  }
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  self->window = window;

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

  // Window icon (taskbar / alt-tab).
  {
    g_autofree gchar* icon_path = bundle_data_file("app_icon.png");
    if (icon_path != nullptr) {
      gtk_window_set_icon_from_file(window, icon_path, nullptr);
    }
  }
  g_signal_connect(window, "delete-event", G_CALLBACK(on_window_delete),
                   application);
  // --minimized (autostart): start in the tray with the window hidden. The
  // window is only realized so the Flutter engine can start. Dart then calls
  // setCloseToTray; if the tray option is off, the window is shown.
  if (self->start_minimized && tray_available()) {
    self->close_to_tray = TRUE;
    enable_tray(self);
  } else {
    self->start_minimized = FALSE;
  }
  // Flutter 3.22 only starts its engine once the window is shown, so a
  // minimized start shows the window fully transparent and hides it as soon
  // as Dart is running (see the "capabilities" call).
  if (self->start_minimized) {
    gtk_widget_set_opacity(GTK_WIDGET(window), 0.0);
  }
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
      self->window_channel, window_method_call_cb, self, nullptr);

  setup_drag_and_drop(self, GTK_WIDGET(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application, gchar*** arguments, int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);
  for (gchar** arg = *arguments + 1; *arg != nullptr; arg++) {
    if (g_strcmp0(*arg, "--minimized") == 0) self->start_minimized = TRUE;
  }

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
  MyApplication* self = MY_APPLICATION(application);
  if (self->window != nullptr &&
      gtk_widget_get_visible(GTK_WIDGET(self->window))) {
    save_window_state(self->window);
    gtk_widget_hide(GTK_WIDGET(self->window));
  }
  disable_tray(self);

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->window_channel);
  g_clear_object(&self->indicator);
  if (self->notification_action_signal != 0 ||
      self->notification_closed_signal != 0) {
    g_autoptr(GDBusConnection) bus =
        g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, nullptr);
    if (bus != nullptr) {
      if (self->notification_action_signal != 0)
        g_dbus_connection_signal_unsubscribe(bus,
                                             self->notification_action_signal);
      if (self->notification_closed_signal != 0)
        g_dbus_connection_signal_unsubscribe(bus,
                                             self->notification_closed_signal);
    }
    self->notification_action_signal = 0;
    self->notification_closed_signal = 0;
  }
  g_clear_pointer(&self->notification_payloads, g_hash_table_unref);
  g_clear_pointer(&self->label_open_app, g_free);
  g_clear_pointer(&self->label_quit, g_free);
  g_clear_pointer(&self->label_notification_open, g_free);
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
                                     // G_APPLICATION_FLAGS_NONE: G_APPLICATION_DEFAULT_FLAGS needs
                                     // GLib 2.74, the release build uses 2.72.
                                     "flags", G_APPLICATION_FLAGS_NONE,
                                     nullptr));
}
