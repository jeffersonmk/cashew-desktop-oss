// Cashew Desktop OSS: "Data Backup" page.
//
// Replaces the Google account / Google Drive page with local backups:
// a list of database copies stored in a folder on this computer.

import 'dart:io';

import 'package:budget/colors.dart';
import 'package:budget/functions.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/accountAndBackup.dart';
import 'package:budget/widgets/animatedExpanded.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/exportDB.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/globalSnackbar.dart';
import 'package:budget/widgets/importDB.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/openSnackbar.dart';
import 'package:budget/widgets/outlinedButtonStacked.dart';
import 'package:budget/widgets/settingsContainers.dart';
import 'package:budget/widgets/tappable.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

class AccountsPage extends StatefulWidget {
  const AccountsPage({Key? key}) : super(key: key);

  @override
  State<AccountsPage> createState() => AccountsPageState();
}

class AccountsPageState extends State<AccountsPage> {
  bool currentlyExporting = false;
  List<File> backups = [];
  String backupFolder = "";
  bool autoBackups = appStateSettings["autoBackups"] == true;

  @override
  void initState() {
    super.initState();
    loadBackups();
  }

  void refreshState() {
    loadBackups();
  }

  Future<void> loadBackups() async {
    try {
      Directory directory = await getLocalBackupDirectory();
      List<File> files = await getLocalBackups();
      if (!mounted) return;
      setState(() {
        backupFolder = directory.path;
        backups = files;
      });
    } catch (e) {
      print("Error listing backups: " + e.toString());
    }
  }

  Future<void> chooseBackupFolder() async {
    String? selected = await FilePicker.platform.getDirectoryPath();
    if (selected == null) return;
    await updateSettings("localBackupFolder", selected,
        pagesNeedingRefresh: [], updateGlobalState: false);
    await loadBackups();
  }

  Future<void> resetBackupFolder() async {
    await updateSettings("localBackupFolder", "",
        pagesNeedingRefresh: [], updateGlobalState: false);
    await loadBackups();
  }

  Future<void> deleteBackupFile(File file) async {
    dynamic result = await openPopup(
      context,
      icon: appStateSettings["outlinedIcons"]
          ? Icons.delete_outlined
          : Icons.delete_rounded,
      title: "delete-backup".tr(),
      beforeDescriptionWidget: Padding(
        padding: const EdgeInsetsDirectional.only(top: 8, bottom: 5),
        child: CodeBlock(text: p.basename(file.path)),
      ),
      onSubmit: () => popRoute(context, true),
      onSubmitLabel: "delete".tr(),
      onCancel: () => popRoute(context),
      onCancelLabel: "cancel".tr(),
    );
    if (result != true) return;
    try {
      await file.delete();
      openSnackbar(SnackbarMessage(
        title: "deleted-backup".tr(),
        description: p.basename(file.path),
        icon: Icons.delete_rounded,
      ));
    } catch (e) {
      openSnackbar(SnackbarMessage(title: e.toString()));
    }
    await loadBackups();
  }

  @override
  Widget build(BuildContext context) {
    return PageFramework(
      horizontalPaddingConstrained: true,
      dragDownToDismiss: true,
      expandedHeight: 56,
      title: "data-backup".tr(),
      appBarBackgroundColor: Theme.of(context).colorScheme.secondaryContainer,
      appBarBackgroundColorStart:
          Theme.of(context).colorScheme.secondaryContainer,
      listWidgets: [
        SizedBox(height: 15),
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 18.0),
          child: Row(
            children: [
              Expanded(
                child: IgnorePointer(
                  ignoring: currentlyExporting,
                  child: AnimatedOpacity(
                    opacity: currentlyExporting ? 0.4 : 1,
                    duration: Duration(milliseconds: 200),
                    child: OutlinedButtonStacked(
                      text: "backup".tr(),
                      iconData: appStateSettings["outlinedIcons"]
                          ? Icons.save_outlined
                          : Icons.save_rounded,
                      onTap: () async {
                        setState(() => currentlyExporting = true);
                        await createLocalBackup();
                        if (mounted) setState(() => currentlyExporting = false);
                        await loadBackups();
                      },
                    ),
                  ),
                ),
              ),
              SizedBox(width: 15),
              Expanded(
                child: Builder(builder: (boxContext) {
                  return OutlinedButtonStacked(
                    text: "export".tr(),
                    iconData: appStateSettings["outlinedIcons"]
                        ? Icons.upload_outlined
                        : Icons.upload_rounded,
                    onTap: () async {
                      await exportDB(boxContext: boxContext);
                    },
                  );
                }),
              ),
              SizedBox(width: 15),
              Expanded(
                child: OutlinedButtonStacked(
                  text: "import".tr(),
                  iconData: appStateSettings["outlinedIcons"]
                      ? Icons.download_outlined
                      : Icons.download_rounded,
                  onTap: () async {
                    await importDB(context);
                  },
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 10),
        SettingsContainerSwitch(
          onSwitched: (value) async {
            await updateSettings("autoBackups", value,
                pagesNeedingRefresh: [], updateGlobalState: false);
            setState(() => autoBackups = value);
          },
          initialValue: autoBackups,
          title: "auto-backups".tr(),
          description: "auto-backups-description".tr(),
          icon: appStateSettings["outlinedIcons"]
              ? Icons.history_outlined
              : Icons.history_rounded,
        ),
        AnimatedExpanded(
          expand: autoBackups,
          child: SettingsContainerDropdown(
            items: ["1", "2", "3", "7", "10", "14"],
            onChanged: (value) async {
              await updateSettings("autoBackupsFrequency", int.parse(value),
                  pagesNeedingRefresh: [], updateGlobalState: false);
            },
            initial: appStateSettings["autoBackupsFrequency"].toString(),
            title: "backup-frequency".tr(),
            description: "number-of-days".tr(),
            icon: appStateSettings["outlinedIcons"]
                ? Icons.event_repeat_outlined
                : Icons.event_repeat_rounded,
          ),
        ),
        SettingsContainerDropdown(
          title: "backup-limit".tr(),
          icon: Icons.format_list_numbered_rtl_outlined,
          initial: appStateSettings["backupLimit"].toString(),
          items: ["5", "10", "15", "20", "30"],
          onChanged: (value) async {
            await updateSettings("backupLimit", int.parse(value),
                pagesNeedingRefresh: [], updateGlobalState: false);
            await deleteOldLocalBackups();
            await loadBackups();
          },
        ),
        SettingsContainer(
          title: "Backup folder",
          description: backupFolder,
          icon: appStateSettings["outlinedIcons"]
              ? Icons.folder_outlined
              : Icons.folder_rounded,
          onTap: chooseBackupFolder,
          onLongPress: resetBackupFolder,
          afterWidget: ButtonIcon(
            onTap: () => openUrl(Uri.file(backupFolder).toString()),
            icon: appStateSettings["outlinedIcons"]
                ? Icons.open_in_new_outlined
                : Icons.open_in_new_rounded,
            size: 38,
          ),
        ),
        SettingsHeader(title: "backups".tr()),
        if (backups.isEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 20, vertical: 10),
            child: TextFont(
              text: "No backups yet.",
              fontSize: 15,
              textColor: getColor(context, "textLight"),
            ),
          ),
        for (File file in backups)
          Padding(
            padding: const EdgeInsetsDirectional.only(
                start: 15, end: 15, bottom: 8),
            child: Tappable(
              borderRadius: 15,
              color: appStateSettings["materialYou"]
                  ? Theme.of(context).colorScheme.secondaryContainer
                  : getColor(context, "lightDarkAccentHeavyLight"),
              onTap: () async {
                await restoreLocalBackup(context, file);
              },
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: 20, vertical: 15),
                child: Row(
                  children: [
                    Icon(
                      appStateSettings["outlinedIcons"]
                          ? Icons.description_outlined
                          : Icons.description_rounded,
                      color: Theme.of(context).colorScheme.secondary,
                      size: 30,
                    ),
                    SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFont(
                            text: getTimeAgo(file.lastModifiedSync())
                                .capitalizeFirst,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          TextFont(
                            text: p.basename(file.path) +
                                "  ·  " +
                                (file.lengthSync() / (1024 * 1024))
                                    .toStringAsFixed(2) +
                                " MB",
                            fontSize: 13,
                            maxLines: 2,
                          ),
                        ],
                      ),
                    ),
                    ButtonIcon(
                      onTap: () => deleteBackupFile(file),
                      icon: appStateSettings["outlinedIcons"]
                          ? Icons.close_outlined
                          : Icons.close_rounded,
                      size: 38,
                    ),
                  ],
                ),
              ),
            ),
          ),
        SizedBox(height: 75),
      ],
    );
  }
}

// Kept for pages that still link to the backup screen.
class BackupsCloudBackupButton extends StatelessWidget {
  const BackupsCloudBackupButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButtonStacked(
      text: "backups".tr(),
      iconData: appStateSettings["outlinedIcons"]
          ? Icons.folder_outlined
          : Icons.folder_rounded,
      onTap: onTap,
    );
  }
}
