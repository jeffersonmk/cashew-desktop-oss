// Cashew Desktop: desktop integration (Linux).
//
// - Tray icon: closing the window keeps the app running in the tray.
// - Start with the system: an XDG autostart entry
//   (~/.config/autostart/io.github.jeffersonmk.CashewDesktop.desktop) that
//   starts the app minimized to the tray.
// - Notifications: Linux has no system scheduler for app notifications, so
//   while the app is running (window open or in the tray) a timer checks
//   once a minute whether a reminder is due and shows it through the
//   desktop's notification service. Reminders only work while the app runs;
//   the tray + autostart options make that automatic.
//
// The native side lives in linux/my_application.cc ("cashew/window" channel).

import 'dart:async';
import 'dart:io';

import 'package:budget/database/tables.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/initializeNotifications.dart';
import 'package:budget/struct/notificationsGlobal.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/notificationsSettings.dart';
import 'package:budget/widgets/transactionEntry/transactionLabel.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const MethodChannel desktopChannel = MethodChannel("cashew/window");

const String _appId = "io.github.jeffersonmk.CashewDesktop";

bool get isLinuxDesktop => !kIsWeb && Platform.isLinux;

class DesktopCapabilities {
  bool tray = false;
  bool notifications = false;
  bool startedMinimized = false;
}

final DesktopCapabilities desktopCapabilities = DesktopCapabilities();

// ---------------------------------------------------------------------------
// Startup
// ---------------------------------------------------------------------------

Future<void> initializeDesktopIntegration() async {
  if (!isLinuxDesktop) return;
  desktopChannel.setMethodCallHandler(_onNativeCall);
  try {
    Map? caps = await desktopChannel.invokeMapMethod("capabilities");
    desktopCapabilities.tray = caps?["tray"] == true;
    desktopCapabilities.notifications = caps?["notifications"] == true;
    desktopCapabilities.startedMinimized = caps?["startedMinimized"] == true;
  } catch (e) {
    print("Desktop capabilities not available: " + e.toString());
  }
  if (!desktopCapabilities.startedMinimized) await recordWindowOpened();
  await applyCloseToTray();
  // Keep the autostart entry pointing at the current executable/AppImage
  // (the AppImage may have been moved or updated).
  if (appStateSettings["desktopStartWithSystem"] == true) {
    await setStartWithSystem(true);
  }
  DesktopNotificationScheduler.instance.start();
}

Future<dynamic> _onNativeCall(MethodCall call) async {
  switch (call.method) {
    case "notificationClicked":
      notificationPayload = call.arguments?.toString();
      runNotificationPayLoadsNoContext();
      break;
    case "windowShown":
      await recordWindowOpened();
      break;
  }
  return null;
}

// Used by the "only if the app was not opened today" daily reminder.
Future<void> recordWindowOpened() async {
  DateTime now = DateTime.now();
  String today =
      now.year.toString() + "-" + now.month.toString() + "-" + now.day.toString();
  if (appStateSettings["desktopLastWindowOpenedDay"] != today) {
    await updateSettings("desktopLastWindowOpenedDay", today,
        updateGlobalState: false);
  }
}

// ---------------------------------------------------------------------------
// Tray
// ---------------------------------------------------------------------------

Future<bool> applyCloseToTray() async {
  if (!isLinuxDesktop) return false;
  try {
    bool? active = await desktopChannel.invokeMethod<bool>(
        "setCloseToTray", appStateSettings["desktopCloseToTray"] == true);
    return active == true;
  } catch (e) {
    print("Tray error: " + e.toString());
    return false;
  }
}

// ---------------------------------------------------------------------------
// Start with the system (XDG autostart)
// ---------------------------------------------------------------------------

String _autostartFilePath() {
  String configHome = Platform.environment["XDG_CONFIG_HOME"] ?? "";
  if (configHome.trim() == "") {
    configHome = (Platform.environment["HOME"] ?? "") + "/.config";
  }
  return configHome + "/autostart/" + _appId + ".desktop";
}

// The AppImage runtime sets $APPIMAGE to the .AppImage file; otherwise use
// the running binary (installed build).
String _executablePath() {
  String? appImage = Platform.environment["APPIMAGE"];
  if (appImage != null && appImage.trim() != "") return appImage;
  return Platform.resolvedExecutable;
}

// Quote a path for the Exec= key of a .desktop file.
String _desktopExecQuote(String path) {
  String escaped = path
      .replaceAll("\\", "\\\\\\\\")
      .replaceAll("\"", "\\\\\"")
      .replaceAll("`", "\\\\`")
      .replaceAll("\$", "\\\\\$");
  return "\"" + escaped + "\"";
}

bool isStartWithSystemEnabled() {
  if (!isLinuxDesktop) return false;
  return File(_autostartFilePath()).existsSync();
}

Future<bool> setStartWithSystem(bool enabled) async {
  if (!isLinuxDesktop) return false;
  File file = File(_autostartFilePath());
  try {
    if (enabled) {
      await file.parent.create(recursive: true);
      String contents = [
        "[Desktop Entry]",
        "Type=Application",
        "Name=Cashew Desktop",
        "Comment=Start Cashew Desktop minimized to the tray",
        "Exec=" + _desktopExecQuote(_executablePath()) + " --minimized",
        "Icon=" + _appId,
        "Terminal=false",
        "X-GNOME-Autostart-enabled=true",
        "",
      ].join("\n");
      if (!file.existsSync() || await file.readAsString() != contents) {
        await file.writeAsString(contents);
      }
    } else if (file.existsSync()) {
      await file.delete();
    }
    return true;
  } catch (e) {
    print("Autostart error: " + e.toString());
    return false;
  }
}

// ---------------------------------------------------------------------------
// Notifications
// ---------------------------------------------------------------------------

Future<bool> showDesktopNotification({
  required String title,
  required String body,
  String? payload,
}) async {
  if (!isLinuxDesktop) return false;
  try {
    int? id = await desktopChannel.invokeMethod<int>("notify", {
      "title": title,
      "body": body,
      "payload": payload ?? "",
    });
    return (id ?? 0) != 0;
  } catch (e) {
    print("Notification error: " + e.toString());
    return false;
  }
}

// Checks every minute whether the daily reminder or an upcoming transaction
// is due. What was already notified is stored in the settings so a restart
// does not repeat a notification.
class DesktopNotificationScheduler {
  DesktopNotificationScheduler._();
  static final DesktopNotificationScheduler instance =
      DesktopNotificationScheduler._();

  Timer? _timer;
  bool _checking = false;

  void start() {
    if (_timer != null) return;
    // First check shortly after startup, then once a minute.
    Future.delayed(Duration(seconds: 20), check);
    _timer = Timer.periodic(Duration(minutes: 1), (_) => check());
  }

  Future<void> check() async {
    if (_checking || !desktopCapabilities.notifications) return;
    _checking = true;
    try {
      await _checkDailyReminder();
      await _checkUpcomingTransactions();
    } catch (e) {
      print("Notification check error: " + e.toString());
    }
    _checking = false;
  }

  String _dayKey(DateTime d) =>
      d.year.toString() + "-" + d.month.toString() + "-" + d.day.toString();

  Future<void> _checkDailyReminder() async {
    if (appStateSettings["notifications"] != true) return;
    DateTime now = DateTime.now();
    String today = _dayKey(now);
    if (appStateSettings["desktopLastDailyReminder"] == today) return;

    ReminderNotificationType type = ReminderNotificationType
        .values[appStateSettings["notificationsReminderType"] ?? 0];
    int hour = appStateSettings["notificationHour"] ?? 20;
    int minute = appStateSettings["notificationMinute"] ?? 0;
    if (type == ReminderNotificationType.DayFromOpen) {
      hour = appStateSettings["appOpenedHour"] ?? hour;
      minute = appStateSettings["appOpenedMinute"] ?? minute;
    }
    DateTime due = DateTime(now.year, now.month, now.day, hour, minute);
    if (now.isBefore(due)) return;

    // "Only if the app was not opened today" (same meaning as on mobile):
    // skip when the window was opened today. Starting minimized in the tray
    // does not count as opening the app.
    if (type == ReminderNotificationType.IfAppNotOpened &&
        appStateSettings["desktopLastWindowOpenedDay"] == today) {
      return;
    }

    bool shown = await showDesktopNotification(
      title: "notification-reminder-title".tr(),
      body: ("notification-reminder-" +
              (1 + now.day % 26).toString())
          .tr(),
      payload: "addTransaction",
    );
    if (shown) {
      await updateSettings("desktopLastDailyReminder", today,
          updateGlobalState: false);
    }
  }

  Future<void> _checkUpcomingTransactions() async {
    if (appStateSettings["notificationsUpcomingTransactions"] != true) return;
    DateTime now = DateTime.now();
    // Due in the last 24 hours and not notified yet.
    List<Transaction> upcoming = await database.getAllUpcomingTransactions(
      startDate: now.subtract(Duration(days: 1)),
      endDate: now,
    );
    Map notified = Map.from(appStateSettings["desktopNotifiedUpcoming"] ?? {});
    // Forget entries older than 3 days.
    notified.removeWhere((key, value) =>
        DateTime.tryParse(value.toString())
            ?.isBefore(now.subtract(Duration(days: 3))) ??
        true);
    bool changed = false;
    for (Transaction transaction in upcoming) {
      if (transaction.upcomingTransactionNotification == false) continue;
      if (transaction.dateCreated.isAfter(now)) continue;
      String key = transaction.transactionPk +
          "@" +
          transaction.dateCreated.millisecondsSinceEpoch.toString();
      if (notified.containsKey(key)) continue;
      String label = await getTransactionLabel(transaction);
      bool shown = await showDesktopNotification(
        title: "notification-upcoming-transaction-title".tr(),
        body: label,
        payload: "upcomingTransaction",
      );
      if (shown) {
        notified[key] = now.toIso8601String();
        changed = true;
      }
    }
    if (changed || notified.length !=
        (appStateSettings["desktopNotifiedUpcoming"] ?? {}).length) {
      await updateSettings("desktopNotifiedUpcoming", notified,
          updateGlobalState: false);
    }
  }
}
