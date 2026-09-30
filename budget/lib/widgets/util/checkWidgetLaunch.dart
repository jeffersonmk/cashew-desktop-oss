import 'dart:async';
import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/addTransactionPage.dart';
import 'package:budget/pages/transactionFilters.dart';
import 'package:budget/pages/walletDetailsPage.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:budget/pages/addWalletPage.dart';
import "package:budget/struct/throttler.dart";

class AndroidOnly extends StatelessWidget {
  const AndroidOnly({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (getPlatform(ignoreEmulation: true) != PlatformOS.isAndroid)
      return SizedBox.shrink();
    return child;
  }
}

// Desktop OSS: home-screen widgets are an Android-only feature and the
// home_widget package was removed. These are kept as no-op stubs so callers
// do not need to change.
class CheckWidgetLaunch extends StatelessWidget {
  const CheckWidgetLaunch({super.key});
  @override
  Widget build(BuildContext context) => SizedBox.shrink();
}

class RenderHomePageWidgets extends StatefulWidget {
  const RenderHomePageWidgets({super.key});

  @override
  State<RenderHomePageWidgets> createState() => RenderHomePageWidgetsState();
}

Future updateWidgetColorsAndText(BuildContext context) async {
  return;
}

class RenderHomePageWidgetsState extends State<RenderHomePageWidgets> {
  void refreshState() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => SizedBox.shrink();
}
