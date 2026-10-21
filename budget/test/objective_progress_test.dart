// Goal / loan progress and the "until goal reached" check of installments
// (Cashew Desktop fix: upstream summed the loan column for goals).
import 'package:budget/database/tables.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/objectiveProgress.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/struct/defaultPreferences.dart';
import 'package:budget/struct/upcomingTransactionsFunctions.dart';
import 'package:budget/widgets/globalSnackbar.dart';
import 'package:budget/widgets/navigationFramework.dart' show snackbarKey;
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

late AllWallets allWallets;

Future<void> addObjective(String pk, ObjectiveType type, double amount,
    {required bool income}) async {
  await database.into(database.objectives).insert(ObjectivesCompanion.insert(
        objectivePk: Value(pk),
        type: Value(type),
        name: pk,
        amount: amount,
        order: 0,
        income: Value(income),
        walletFk: Value("0"),
      ));
}

int _n = 0;
Future<void> addTransaction(double amount,
    {String? goal, String? loan, bool paid = true}) async {
  _n++;
  await database.into(database.transactions).insert(
        TransactionsCompanion.insert(
          transactionPk: Value("t$_n"),
          name: "t$_n",
          amount: amount,
          note: "",
          categoryFk: "1",
          walletFk: Value("0"),
          income: Value(amount > 0),
          paid: Value(paid),
          objectiveFk: Value(goal),
          objectiveLoanFk: Value(loan),
        ),
      );
}

Future<ObjectiveProgress> progressOf(String pk) async =>
    getObjectiveProgress(
        allWallets, await database.getObjectiveInstance(pk));

void main() {
  setUp(() async {
    appStateSettings = {
      "selectedWalletPk": "0",
      "longTermLoansDifferenceFeature": false,
    };
    database = FinanceDatabase(NativeDatabase.memory());
    await database.into(database.wallets).insert(WalletsCompanion.insert(
        walletPk: Value("0"), name: "Conta", order: 0, currency: Value("brl")));
    await database.into(database.categories).insert(CategoriesCompanion.insert(
        categoryPk: Value("1"), name: "Geral", order: 0));
    allWallets = AllWallets(
      list: await database.select(database.wallets).get(),
      indexedByPk: {
        for (var w in await database.select(database.wallets).get())
          w.walletPk: w
      },
    );
  });
  tearDown(() async => database.close());

  test('savings goal: counts paid transactions linked to the goal', () async {
    await addObjective("trip", ObjectiveType.goal, 1000, income: true);
    await addTransaction(600, goal: "trip");
    await addTransaction(300, goal: "trip", paid: false); // not paid yet
    await addTransaction(999, loan: "trip"); // other column: ignored
    ObjectiveProgress p = await progressOf("trip");
    expect(p.totalAmount, 600);
    expect(p.reached, isFalse);

    await addTransaction(400, goal: "trip");
    p = await progressOf("trip");
    expect(p.totalAmount, 1000);
    expect(p.reached, isTrue);
  });

  test('expense goal: reached when the expenses add up to the amount',
      () async {
    await addObjective("car", ObjectiveType.goal, 500, income: false);
    await addTransaction(-200, goal: "car");
    expect((await progressOf("car")).reached, isFalse);
    await addTransaction(-300, goal: "car");
    ObjectiveProgress p = await progressOf("car");
    expect(p.totalAmount, 500);
    expect(p.reached, isTrue);
  });

  test('lent loan: settled when payments received reach the amount',
      () async {
    await addObjective("friend", ObjectiveType.loan, 300, income: true);
    await addTransaction(100, loan: "friend");
    await addTransaction(100, loan: "friend");
    expect((await progressOf("friend")).reached, isFalse);
    await addTransaction(100, loan: "friend");
    expect((await progressOf("friend")).reached, isTrue);
  });

  test('borrowed loan: settled when payments made reach the amount',
      () async {
    await addObjective("bank", ObjectiveType.loan, 200, income: false);
    await addTransaction(-150, loan: "bank");
    expect((await progressOf("bank")).reached, isFalse);
    await addTransaction(-50, loan: "bank");
    expect((await progressOf("bank")).reached, isTrue);
  });

  test('goal total: the one-shot query matches the live stream', () async {
    await addObjective("trip", ObjectiveType.goal, 1000, income: true);
    await addTransaction(250, goal: "trip");
    Objective o = await database.getObjectiveInstance("trip");
    expect(
        await database.getTotalTowardsObjective(
            allWallets, "trip", ObjectiveType.goal),
        await database.watchTotalTowardsObjective(allWallets, o).first);
  });

  // The real installment flow: paying an installment creates the next one
  // only while the goal is not reached.
  Future<int> countInstallments(String pk) async =>
      (await (database.select(database.transactions)
                ..where((t) =>
                    t.objectiveFk.equals(pk) | t.objectiveLoanFk.equals(pk)))
              .get())
          .length;

  Transaction installment(String pk, double amount, {bool loan = false}) =>
      Transaction(
        transactionPk: "inst-$pk",
        name: "Parcela",
        amount: amount,
        note: "",
        categoryFk: "1",
        walletFk: "0",
        dateCreated: DateTime(2026, 1, 10),
        income: amount > 0,
        paid: true,
        skipPaid: false,
        // As markAsPaid passes it: the copy from before it was marked.
        createdAnotherFutureTransaction: false,
        type: TransactionSpecialType.repetitive,
        periodLength: 1,
        reoccurrence: BudgetReoccurence.monthly,
        objectiveFk: loan ? null : pk,
        objectiveLoanFk: loan ? pk : null,
      );

  Future<void> pumpApp(WidgetTester tester) async {
    Map<String, dynamic> defaults = {};
    await tester.runAsync(() async {
      defaults = await getDefaultPreferences();
    });
    appStateSettings = {...defaults, ...appStateSettings};
    await tester.pumpWidget(Provider<AllWallets>.value(
      value: allWallets,
      child: MaterialApp(
        home: Scaffold(
          body: Stack(children: [GlobalSnackbar(key: snackbarKey)]),
        ),
      ),
    ));
  }

  for (bool loan in [false, true]) {
    String kind = loan ? "loan" : "goal";
    testWidgets('$kind installment stops once reached', (tester) async {
      await pumpApp(tester);
      BuildContext context = snackbarKey.currentContext!;
      await tester.runAsync(() async {
        await addObjective("x", loan ? ObjectiveType.loan : ObjectiveType.goal,
            300,
            income: true);
        Transaction t = installment("x", 100, loan: loan);
        await database.into(database.transactions).insert(t);
        await createNewSubscriptionTransaction(context, t);
        expect(await countInstallments("x"), 2,
            reason: "100 of 300: next installment created");

        Transaction paid3 = t.copyWith(transactionPk: "paid-200", amount: 200);
        await database.into(database.transactions).insert(paid3);
        Transaction t2 = t.copyWith(transactionPk: "inst-x-2");
        await createNewSubscriptionTransaction(context, t2);
        expect(await countInstallments("x"), 3,
            reason: "300 of 300: no new installment (only the 200 added)");
      });
      // Let the snackbars animate in and out before the tree is disposed.
      for (int i = 0; i < 60; i++) {
        await tester.pump(Duration(milliseconds: 500));
      }
      await tester.runAsync(
          () => Future.delayed(Duration(seconds: 6)));
      for (int i = 0; i < 60; i++) {
        await tester.pump(Duration(milliseconds: 500));
      }
      await tester.pumpWidget(SizedBox.shrink());
    });
  }
}
