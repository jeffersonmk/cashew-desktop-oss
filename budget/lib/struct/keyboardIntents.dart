// Cashew Desktop: keyboard shortcuts.
//
// Global shortcuts handled by MaterialApp (see main.dart). They work from any
// screen; text fields keep their own keys (typing, Ctrl+C/V, etc.) because a
// focused text field handles a key before these shortcuts do.

import 'package:budget/functions.dart';
import 'package:budget/main.dart';
import 'package:budget/pages/addTransactionPage.dart';
import 'package:budget/pages/transactionsSearchPage.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/navigationFramework.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Navigation page indexes (see PageNavigationFrameworkState.pages).
const int _homePage = 0;
const int _transactionsPage = 1;
const int _budgetsPage = 2;
const int _morePage = 3;
const int _backupsPage = 8;

bool _atRootOfNavigation() => !(navigatorKey.currentState?.canPop() ?? false);

// Close any open page/popup so the shortcut starts from the main screen.
void _popToRoot() {
  navigatorKey.currentState?.popUntil((route) => route.isFirst);
}

void _goToPage(int page) {
  _popToRoot();
  pageNavigationFrameworkKey.currentState?.changePage(page, switchNavbar: true);
}

bool _shortcutsHelpOpen = false;

// Label + keys, shown in the Ctrl+/ help popup.
const List<List<String>> shortcutHelpItems = [
  ["New transaction", "Ctrl + N"],
  ["Search transactions", "Ctrl + F"],
  ["Home", "Ctrl + 1"],
  ["Transactions", "Ctrl + 2"],
  ["Budgets", "Ctrl + 3"],
  ["More", "Ctrl + 4"],
  ["Backups", "Ctrl + B"],
  ["Back / close", "Esc"],
  ["Quit", "Ctrl + Q"],
  ["Show shortcuts", "Ctrl + /  or  F1"],
];

Future<void> openKeyboardShortcutsPopup() async {
  if (_shortcutsHelpOpen) return;
  BuildContext? context = navigatorKey.currentContext;
  if (context == null) return;
  _shortcutsHelpOpen = true;
  await openPopup(
    context,
    icon: appStateSettings["outlinedIcons"]
        ? Icons.keyboard_outlined
        : Icons.keyboard_rounded,
    title: "Keyboard shortcuts",
    descriptionWidget: Padding(
      padding: const EdgeInsetsDirectional.only(top: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (List<String> item in shortcutHelpItems)
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(child: TextFont(text: item[0], fontSize: 16)),
                  SizedBox(width: 20),
                  TextFont(
                    text: item[1],
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
    onSubmitLabel: "OK",
    onSubmit: () => navigatorKey.currentState?.pop(),
  );
  _shortcutsHelpOpen = false;
}

Map<Type, Action<Intent>> keyboardIntents = {
  EscapeIntent: CallbackAction<EscapeIntent>(
    onInvoke: (EscapeIntent intent) {
      if (!_atRootOfNavigation())
        navigatorKey.currentState!.pop();
      else
        pageNavigationFrameworkKey.currentState!
            .changePage(_homePage, switchNavbar: true);
      return null;
    },
  ),
  Digit1Intent: CallbackAction<Digit1Intent>(
    onInvoke: (Digit1Intent intent) => _goToPage(_homePage),
  ),
  Digit2Intent: CallbackAction<Digit2Intent>(
    onInvoke: (Digit2Intent intent) => _goToPage(_transactionsPage),
  ),
  Digit3Intent: CallbackAction<Digit3Intent>(
    onInvoke: (Digit3Intent intent) => _goToPage(_budgetsPage),
  ),
  Digit4Intent: CallbackAction<Digit4Intent>(
    onInvoke: (Digit4Intent intent) => _goToPage(_morePage),
  ),
  NewTransactionIntent: CallbackAction<NewTransactionIntent>(
    onInvoke: (NewTransactionIntent intent) {
      // Avoid stacking several "new transaction" pages.
      if (!_atRootOfNavigation()) return null;
      pushRoute(
        null,
        AddTransactionPage(
          routesToPopAfterDelete: RoutesToPopAfterDelete.None,
        ),
      );
      return null;
    },
  ),
  SearchIntent: CallbackAction<SearchIntent>(
    onInvoke: (SearchIntent intent) {
      if (!_atRootOfNavigation()) return null;
      pushRoute(null, TransactionsSearchPage());
      return null;
    },
  ),
  BackupsIntent: CallbackAction<BackupsIntent>(
    onInvoke: (BackupsIntent intent) => _goToPage(_backupsPage),
  ),
  QuitIntent: CallbackAction<QuitIntent>(
    onInvoke: (QuitIntent intent) async {
      // Same as closing the window: the native side saves the window state.
      await SystemNavigator.pop();
      return null;
    },
  ),
  ShortcutsHelpIntent: CallbackAction<ShortcutsHelpIntent>(
    onInvoke: (ShortcutsHelpIntent intent) => openKeyboardShortcutsPopup(),
  ),
};

Map<ShortcutActivator, Intent> shortcuts = {
  const SingleActivator(LogicalKeyboardKey.escape): const EscapeIntent(),
  const SingleActivator(LogicalKeyboardKey.digit1, control: true):
      const Digit1Intent(),
  const SingleActivator(LogicalKeyboardKey.digit2, control: true):
      const Digit2Intent(),
  const SingleActivator(LogicalKeyboardKey.digit3, control: true):
      const Digit3Intent(),
  const SingleActivator(LogicalKeyboardKey.digit4, control: true):
      const Digit4Intent(),
  const SingleActivator(LogicalKeyboardKey.keyN, control: true):
      const NewTransactionIntent(),
  const SingleActivator(LogicalKeyboardKey.keyF, control: true):
      const SearchIntent(),
  const SingleActivator(LogicalKeyboardKey.keyB, control: true):
      const BackupsIntent(),
  const SingleActivator(LogicalKeyboardKey.keyQ, control: true):
      const QuitIntent(),
  const SingleActivator(LogicalKeyboardKey.slash, control: true):
      const ShortcutsHelpIntent(),
  const SingleActivator(LogicalKeyboardKey.f1): const ShortcutsHelpIntent(),
};

class EscapeIntent extends Intent {
  const EscapeIntent();
}

class Digit1Intent extends Intent {
  const Digit1Intent();
}

class Digit2Intent extends Intent {
  const Digit2Intent();
}

class Digit3Intent extends Intent {
  const Digit3Intent();
}

class Digit4Intent extends Intent {
  const Digit4Intent();
}

class NewTransactionIntent extends Intent {
  const NewTransactionIntent();
}

class SearchIntent extends Intent {
  const SearchIntent();
}

class BackupsIntent extends Intent {
  const BackupsIntent();
}

class QuitIntent extends Intent {
  const QuitIntent();
}

class ShortcutsHelpIntent extends Intent {
  const ShortcutsHelpIntent();
}
