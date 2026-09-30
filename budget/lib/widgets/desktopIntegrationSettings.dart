// Cashew Desktop: "Desktop" section in Settings (Linux).

import 'package:budget/struct/desktopIntegration.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/globalSnackbar.dart';
import 'package:budget/widgets/openSnackbar.dart';
import 'package:budget/widgets/settingsContainers.dart';
import 'package:flutter/material.dart';

class DesktopIntegrationSettings extends StatefulWidget {
  const DesktopIntegrationSettings({super.key});

  @override
  State<DesktopIntegrationSettings> createState() =>
      _DesktopIntegrationSettingsState();
}

class _DesktopIntegrationSettingsState
    extends State<DesktopIntegrationSettings> {
  bool startWithSystem = isStartWithSystemEnabled();

  @override
  Widget build(BuildContext context) {
    bool outlined = appStateSettings["outlinedIcons"] == true;
    bool trayAvailable = desktopCapabilities.tray;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsHeader(title: "Desktop"),
        Opacity(
          opacity: trayAvailable ? 1 : 0.5,
          child: SettingsContainerSwitch(
            title: "Keep running in the tray",
            descriptionWithValue: (value) => trayAvailable
                ? (value
                    ? "Closing the window keeps the app in the tray, so reminders keep working"
                    : "Closing the window quits the app")
                : "Not available: no tray found (needs a panel with tray icons and libayatana-appindicator)",
            initialValue: appStateSettings["desktopCloseToTray"] == true,
            icon: outlined
                ? Icons.move_to_inbox_outlined
                : Icons.move_to_inbox_rounded,
            onSwitched: (value) async {
              if (!trayAvailable && value == true) {
                openSnackbar(SnackbarMessage(
                  title: "Tray not available",
                  description:
                      "Your desktop has no tray (system tray / StatusNotifier)",
                  icon: Icons.warning_rounded,
                ));
                return false;
              }
              await updateSettings("desktopCloseToTray", value,
                  updateGlobalState: false);
              await applyCloseToTray();
              setState(() {});
              return true;
            },
          ),
        ),
        SettingsContainerSwitch(
          title: "Start with the system",
          descriptionWithValue: (value) => value
              ? (appStateSettings["desktopCloseToTray"] == true && trayAvailable
                  ? "Opens minimized to the tray when you log in"
                  : "Opens when you log in")
              : "Off",
          initialValue: startWithSystem,
          syncWithInitialValue: false,
          icon: outlined
              ? Icons.power_settings_new_outlined
              : Icons.power_settings_new_rounded,
          onSwitched: (value) async {
            bool ok = await setStartWithSystem(value);
            if (!ok) {
              openSnackbar(SnackbarMessage(
                title: "Could not change the autostart setting",
                icon: Icons.warning_rounded,
              ));
              return false;
            }
            await updateSettings("desktopStartWithSystem", value,
                updateGlobalState: false);
            setState(() {
              startWithSystem = value;
            });
            return true;
          },
        ),
      ],
    );
  }
}
