// Cashew Desktop: "Desktop" section in Settings (Linux).

import 'package:easy_localization/easy_localization.dart';
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
        SettingsHeader(title: "desktop-integration".tr()),
        Opacity(
          opacity: trayAvailable ? 1 : 0.5,
          child: SettingsContainerSwitch(
            title: "keep-running-in-tray".tr(),
            descriptionWithValue: (value) => trayAvailable
                ? (value
                    ? "keep-running-in-tray-on".tr()
                    : "keep-running-in-tray-off".tr())
                : "tray-not-available-setting".tr(),
            initialValue: appStateSettings["desktopCloseToTray"] == true,
            icon: outlined
                ? Icons.move_to_inbox_outlined
                : Icons.move_to_inbox_rounded,
            onSwitched: (value) async {
              if (!trayAvailable && value == true) {
                openSnackbar(SnackbarMessage(
                  title: "tray-not-available".tr(),
                  description: "tray-not-available-description".tr(),
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
          title: "start-with-system".tr(),
          descriptionWithValue: (value) => value
              ? (appStateSettings["desktopCloseToTray"] == true && trayAvailable
                  ? "start-with-system-tray".tr()
                  : "start-with-system-on".tr())
              : "start-with-system-off".tr(),
          initialValue: startWithSystem,
          syncWithInitialValue: false,
          icon: outlined
              ? Icons.power_settings_new_outlined
              : Icons.power_settings_new_rounded,
          onSwitched: (value) async {
            bool ok = await setStartWithSystem(value);
            if (!ok) {
              openSnackbar(SnackbarMessage(
                title: "start-with-system-error".tr(),
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
