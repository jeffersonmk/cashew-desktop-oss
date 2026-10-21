// Cashew Desktop: progress of a goal or loan, shared by the goal widgets and
// by the "until goal reached" check of installment payments.
//
// Upstream computed the progress only inside the WatchTotalAndAmountOfObjective
// widget; the installment check had its own (broken) version that summed the
// loan column for goals (always 0) and ignored loans, so "until goal reached"
// installments never stopped. Both now use computeObjectiveProgress.

import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/objectivesListPage.dart'
    show getDifferenceOfLoan, getIsDifferenceOnlyLoan;
import 'package:budget/struct/currencyFunctions.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/settings.dart';

class ObjectiveProgress {
  const ObjectiveProgress(
      this.objectiveAmount, this.totalAmount, this.percentageTowardsGoal);
  final double objectiveAmount;
  final double totalAmount;
  final double percentageTowardsGoal;
  bool get reached => percentageTowardsGoal >= 1;
}

// [totalTowards]: sum of the paid transactions linked to the objective
// (watch/getTotalTowardsObjective), in the primary currency.
// [loanAmount]: for loans, the sum of the paid records that set the loan
// amount (watch/getTotalAmountObjectiveLoan); ignored for goals.
// [decimals]: decimals of the selected account, to decide when a
// difference-only loan is settled.
ObjectiveProgress computeObjectiveProgress({
  required AllWallets allWallets,
  required Objective objective,
  required double? totalTowards,
  double? loanAmount,
  int decimals = 2,
}) {
  if (objective.type == ObjectiveType.loan) {
    double objectiveAmount = loanAmount ?? 0;
    if (getIsDifferenceOnlyLoan(objective) == false) {
      double objectiveAmountConverted = objective.amount *
          amountRatioToPrimaryCurrency(
            allWallets,
            allWallets.indexedByPk[objective.walletFk]?.currency,
          );
      objectiveAmount = objectiveAmount +
          (objectiveAmountConverted * (objective.income ? -1 : 1));
    }
    double totalAmount = ((totalTowards ?? 0) - (loanAmount ?? 0)) * -1;
    double percentageTowardsGoal =
        objectiveAmount == 0 ? 0 : totalAmount / objectiveAmount;
    percentageTowardsGoal = absoluteZero(percentageTowardsGoal);
    if (getIsDifferenceOnlyLoan(objective)) {
      bool settled = double.tryParse(
              getDifferenceOfLoan(objective, totalAmount, objectiveAmount)
                  .abs()
                  .toStringAsFixed(decimals)) ==
          0;
      percentageTowardsGoal =
          settled && totalTowards != null && loanAmount != null ? 1 : 0;
    }
    return ObjectiveProgress(
      objectiveAmount * (objective.income ? -1 : 1),
      totalAmount * (objective.income ? -1 : 1),
      percentageTowardsGoal,
    );
  } else {
    double objectiveAmount =
        objectiveAmountToPrimaryCurrency(allWallets, objective);
    double totalAmount = totalTowards ?? 0;
    if (objective.income == false) totalAmount = totalAmount * -1;
    double percentageTowardsGoal =
        objectiveAmount == 0 ? 0 : totalAmount / objectiveAmount;
    percentageTowardsGoal = absoluteZero(percentageTowardsGoal);
    return ObjectiveProgress(
        objectiveAmount, totalAmount, percentageTowardsGoal);
  }
}

// Current progress read from the database (for code outside the widgets).
Future<ObjectiveProgress> getObjectiveProgress(
    AllWallets allWallets, Objective objective) async {
  double? totalTowards = await database.getTotalTowardsObjective(
      allWallets, objective.objectivePk, objective.type);
  double? loanAmount = objective.type == ObjectiveType.loan
      ? await database.getTotalAmountObjectiveLoan(allWallets, objective)
      : null;
  return computeObjectiveProgress(
    allWallets: allWallets,
    objective: objective,
    totalTowards: totalTowards,
    loanAmount: loanAmount,
    decimals: allWallets
            .indexedByPk[appStateSettings["selectedWalletPk"]]?.decimals ??
        2,
  );
}
