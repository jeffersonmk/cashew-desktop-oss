// Cashew Desktop: right-click menu for transactions.
//
// Shown when a transaction in any list is right-clicked with the mouse on
// desktop. Uses the same actions the app already has (open, duplicate,
// select, delete), so nothing here changes how data is stored.

import 'package:budget/database/tables.dart';
import 'package:budget/pages/addTransactionPage.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/selectedTransactionsAppBar.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

enum _TransactionMenuAction {
  open,
  duplicate,
  duplicateToday,
  select,
  delete,
}

Future<void> showTransactionContextMenu({
  required BuildContext context,
  required Offset globalPosition,
  required Transaction transaction,
  required VoidCallback openTransaction,
  required bool selected,
  // null when selecting is not allowed in this list
  required VoidCallback? toggleSelected,
}) async {
  final RenderBox? overlay =
      Overlay.maybeOf(context)?.context.findRenderObject() as RenderBox?;
  if (overlay == null) return;
  bool outlined = appStateSettings["outlinedIcons"] == true;

  PopupMenuItem<_TransactionMenuAction> item(
    _TransactionMenuAction value,
    IconData icon,
    String label, {
    Color? color,
  }) {
    return PopupMenuItem<_TransactionMenuAction>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          SizedBox(width: 12),
          Text(label, style: color == null ? null : TextStyle(color: color)),
        ],
      ),
    );
  }

  Color deleteColor = Theme.of(context).colorScheme.error;

  _TransactionMenuAction? action = await showMenu<_TransactionMenuAction>(
    context: context,
    position: RelativeRect.fromRect(
      Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
      Offset.zero & overlay.size,
    ),
    items: [
      item(
        _TransactionMenuAction.open,
        outlined ? Icons.edit_outlined : Icons.edit_rounded,
        "edit".tr(),
      ),
      item(
        _TransactionMenuAction.duplicate,
        outlined ? Icons.file_copy_outlined : Icons.file_copy_rounded,
        "duplicate".tr(),
      ),
      item(
        _TransactionMenuAction.duplicateToday,
        outlined ? Icons.today_outlined : Icons.today_rounded,
        "duplicate".tr() + " (" + "today".tr() + ")",
      ),
      if (toggleSelected != null)
        item(
          _TransactionMenuAction.select,
          selected
              ? (outlined ? Icons.deselect_outlined : Icons.deselect_rounded)
              : (outlined
                  ? Icons.check_circle_outline
                  : Icons.check_circle_rounded),
          selected ? "Deselect" : "select".tr(),
        ),
      PopupMenuDivider(),
      item(
        _TransactionMenuAction.delete,
        outlined ? Icons.delete_outlined : Icons.delete_rounded,
        "delete".tr(),
        color: deleteColor,
      ),
    ],
  );

  if (action == null || !context.mounted) return;
  switch (action) {
    case _TransactionMenuAction.open:
      openTransaction();
      break;
    case _TransactionMenuAction.duplicate:
      await duplicateTransaction(context, transaction.transactionPk);
      break;
    case _TransactionMenuAction.duplicateToday:
      await duplicateTransaction(
        context,
        transaction.transactionPk,
        useCurrentDate: true,
      );
      break;
    case _TransactionMenuAction.select:
      toggleSelected?.call();
      break;
    case _TransactionMenuAction.delete:
      // Asks for confirmation before deleting.
      await deleteTransactionsPopup(
        context,
        transactionPks: [transaction.transactionPk],
        routesToPopAfterDelete: RoutesToPopAfterDelete.None,
      );
      break;
  }
}
